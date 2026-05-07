const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const openAiModel = "gpt-4o-mini";
const maxTransactionsPerOpenAiCall = 100;
const maxOpenAiConcurrency = 6;
const maxOpenAiAttempts = 2;
const openAiRequestTimeoutMs = 45_000;
const unknownCategoryName = "Unknown";
const maxCategoryNameLength = 40;
const maxDescriptionLength = 80;

type TransactionInput = {
  key: string;
  date: string;
  amount: number;
  description: string;
};

type Suggestion = {
  key: string;
  categoryName: string;
};

type ChunkResult = {
  suggestions: Suggestion[];
  error?: string;
};

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

function compactTransaction(transaction: TransactionInput) {
  return {
    k: transaction.key,
    a: transaction.amount,
    m: transaction.description.slice(0, maxDescriptionLength),
  };
}

function unknownSuggestions(transactions: TransactionInput[]): Suggestion[] {
  return transactions.map((transaction) => ({
    key: transaction.key,
    categoryName: unknownCategoryName,
  }));
}

function isRetryableOpenAiError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const message = error.message.toLowerCase();
  return (
    message.includes("timed out") ||
    message.includes("429") ||
    message.includes("500") ||
    message.includes("502") ||
    message.includes("503") ||
    message.includes("504") ||
    message.includes("network")
  );
}

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
  timeoutMs: number,
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`OpenAI request timed out after ${timeoutMs}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function parseStringArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const out: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") return null;
    const trimmed = item.trim();
    if (trimmed.length > 0) out.push(trimmed);
  }
  return out;
}

function parseTransactions(value: unknown): TransactionInput[] | null {
  if (!Array.isArray(value)) return null;
  const out: TransactionInput[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") return null;
    const row = item as Record<string, unknown>;
    const key = row.key;
    const date = row.date;
    const amount = row.amount;
    const description = row.description;
    if (
      typeof key !== "string" ||
      key.trim().length === 0 ||
      typeof date !== "string" ||
      typeof amount !== "number" ||
      typeof description !== "string"
    ) {
      return null;
    }
    out.push({
      key: key.trim(),
      date,
      amount,
      description,
    });
  }
  return out;
}

function normalizedCategoryKey(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replaceAll("&", " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function titleCaseWord(word: string): string {
  if (word.length === 0 || word === "/") return word;
  const lower = word.toLowerCase();
  return lower[0].toUpperCase() + lower.slice(1);
}

export function normalizeCategoryName(raw: unknown): string {
  if (typeof raw !== "string") return unknownCategoryName;
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > maxCategoryNameLength) {
    return unknownCategoryName;
  }
  const lower = trimmed.toLowerCase();
  if (
    lower.startsWith("http://") ||
    lower.startsWith("https://") ||
    lower.includes("@") ||
    /[<>{}\[\]\\`~^=]/.test(trimmed) ||
    !/[A-Za-z0-9]/.test(trimmed)
  ) {
    return unknownCategoryName;
  }
  const display = trimmed
    .replaceAll("&", " and ")
    .replace(/\s*\/\s*/g, " / ")
    .replace(/[\s\-_.,;:|!?'"()]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .map(titleCaseWord)
    .join(" ");
  if (
    display.length === 0 ||
    display.length > maxCategoryNameLength ||
    normalizedCategoryKey(display).length === 0
  ) {
    return unknownCategoryName;
  }
  return display;
}

async function categorizeChunk({
  openAiApiKey,
  transactions,
  allowedCategories,
}: {
  openAiApiKey: string;
  transactions: TransactionInput[];
  allowedCategories: string[];
}): Promise<ChunkResult> {
  const system = `JSON only. Return {"s":{"KEY":"Category"}}. ` +
    `Categorize each tx. Use C if it fits; else short new category. ` +
    `No merchant/private data. Unsafe/unsure="${unknownCategoryName}".`;
  const user = `C:${JSON.stringify(allowedCategories)}\n` +
    `T:${JSON.stringify(transactions.map(compactTransaction))}`;

  let lastError: unknown;
  for (let attempt = 1; attempt <= maxOpenAiAttempts; attempt += 1) {
    try {
      const response = await fetchWithTimeout(
        "https://api.openai.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${openAiApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: openAiModel,
            temperature: 0.1,
            max_tokens: 3000,
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: system },
              { role: "user", content: user },
            ],
          }),
        },
        openAiRequestTimeoutMs,
      );

      let data: unknown;
      try {
        data = await response.json();
      } catch {
        throw new Error(
          `OpenAI returned a non-JSON response (${response.status})`,
        );
      }

      if (!response.ok) {
        const message = typeof data === "object" && data && "error" in data
          ? JSON.stringify((data as Record<string, unknown>).error)
          : JSON.stringify(data);
        throw new Error(
          `OpenAI request failed (${response.status}): ${message}`,
        );
      }

      const choices = (data as Record<string, unknown>).choices;
      if (!Array.isArray(choices) || choices.length === 0) {
        throw new Error("OpenAI response has no choices");
      }
      const first = choices[0] as Record<string, unknown>;
      const message = first.message as Record<string, unknown> | undefined;
      const content = message?.content;
      if (typeof content !== "string" || content.trim().length === 0) {
        throw new Error("OpenAI response content is empty");
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(content);
      } catch {
        throw new Error("OpenAI response content is not valid JSON");
      }

      const expectedKeys = new Set(
        transactions.map((transaction) => transaction.key),
      );
      const suggestionByKey = new Map<string, string>();
      const duplicateKeys = new Set<string>();
      const seen = new Set<string>();
      const parsedRow = parsed as Record<string, unknown>;
      const compactSuggestions = parsedRow.s;
      if (compactSuggestions && typeof compactSuggestions === "object") {
        for (
          const [key, categoryName] of Object.entries(
            compactSuggestions as Record<string, unknown>,
          )
        ) {
          if (!expectedKeys.has(key) || seen.has(key)) {
            if (expectedKeys.has(key)) duplicateKeys.add(key);
            continue;
          }
          seen.add(key);
          suggestionByKey.set(key, normalizeCategoryName(categoryName));
        }
      } else {
        const rawSuggestions = parsedRow.suggestions;
        if (!Array.isArray(rawSuggestions)) {
          throw new Error("OpenAI response missing suggestions");
        }
        for (const item of rawSuggestions) {
          if (!item || typeof item !== "object") continue;
          const row = item as Record<string, unknown>;
          const key = row.key;
          if (
            typeof key !== "string" || !expectedKeys.has(key) || seen.has(key)
          ) {
            if (typeof key === "string" && expectedKeys.has(key)) {
              duplicateKeys.add(key);
            }
            continue;
          }
          seen.add(key);
          suggestionByKey.set(key, normalizeCategoryName(row.categoryName));
        }
      }

      const out: Suggestion[] = [];
      for (const transaction of transactions) {
        out.push({
          key: transaction.key,
          categoryName: duplicateKeys.has(transaction.key)
            ? unknownCategoryName
            : suggestionByKey.get(transaction.key) ?? unknownCategoryName,
        });
      }
      return { suggestions: out };
    } catch (error) {
      lastError = error;
      if (attempt >= maxOpenAiAttempts || !isRetryableOpenAiError(error)) {
        break;
      }
    }
  }

  const message = lastError instanceof Error
    ? lastError.message
    : "Could not categorize chunk";
  return { suggestions: unknownSuggestions(transactions), error: message };
}

export async function handleCategorizeTransactionsRequest(req: Request) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "Missing Supabase auth token" }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const transactions = parseTransactions(payload.transactions);
  const requestedCategories = parseStringArray(payload.allowedCategories);
  if (!transactions || transactions.length === 0) {
    return jsonResponse(
      { error: "transactions must be a non-empty array" },
      400,
    );
  }
  if (!requestedCategories || requestedCategories.length === 0) {
    return jsonResponse(
      { error: "allowedCategories must be a non-empty string array" },
      400,
    );
  }

  const openAiApiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAiApiKey) {
    return jsonResponse({ error: "Missing OPENAI_API_KEY secret" }, 500);
  }
  const apiKey = openAiApiKey;

  const allowedCategories = Array.from(
    new Set([...requestedCategories, unknownCategoryName]),
  );
  const categoryByNormalizedName = new Map(
    allowedCategories.map((
      category,
    ) => [normalizedCategoryKey(category), category]),
  );
  const chunks = chunk(transactions, maxTransactionsPerOpenAiCall);
  const suggestions: Suggestion[] = [];
  const errors: string[] = [];
  let nextChunkIndex = 0;

  async function worker() {
    while (true) {
      const chunkIndex = nextChunkIndex;
      if (chunkIndex >= chunks.length) return;
      nextChunkIndex += 1;
      const result = await categorizeChunk({
        openAiApiKey: apiKey,
        transactions: chunks[chunkIndex],
        allowedCategories: Array.from(categoryByNormalizedName.values()),
      });
      suggestions.push(...result.suggestions);
      if (result.error) {
        errors.push(
          `chunk ${chunkIndex + 1}/${chunks.length}: ${result.error}`,
        );
      }
    }
  }

  await Promise.all(
    Array.from(
      { length: Math.min(chunks.length, maxOpenAiConcurrency) },
      () => worker(),
    ),
  );

  return jsonResponse({ suggestions, errors }, 200);
}

if (import.meta.main) {
  Deno.serve(handleCategorizeTransactionsRequest);
}
