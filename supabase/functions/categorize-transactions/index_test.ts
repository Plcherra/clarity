import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  handleCategorizeTransactionsRequest,
  normalizeCategoryName,
} from "./index.ts";

Deno.test("normalizes AI-created category names", () => {
  assertEquals(normalizeCategoryName(" pet-care!! "), "Pet Care");
  assertEquals(normalizeCategoryName("PET   care"), "Pet Care");
});

Deno.test("unsafe category names fall back to Unknown", () => {
  assertEquals(normalizeCategoryName("https://example.com"), "Unknown");
  assertEquals(normalizeCategoryName("person@example.com"), "Unknown");
  assertEquals(normalizeCategoryName("<script>"), "Unknown");
  assertEquals(normalizeCategoryName("!!!"), "Unknown");
});

Deno.test("rejects invalid request shape before OpenAI call", async () => {
  const response = await handleCategorizeTransactionsRequest(
    new Request("http://localhost", {
      method: "POST",
      headers: {
        Authorization: "Bearer test-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        allowedCategories: ["Unknown"],
        transactions: [],
      }),
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), {
    error: "transactions must be a non-empty array",
  });
});

Deno.test("chunks large imports into smaller OpenAI calls", async () => {
  const restore = setOpenAiTestEnv();
  let callCount = 0;
  globalThis.fetch = async (_input, init) => {
    callCount += 1;
    const txs = transactionsFromOpenAiRequest(init);
    return openAiJsonResponse(
      txs.map((transaction) => ({
        key: transaction.k,
        categoryName: "Pet Care",
      })),
    );
  };

  try {
    const response = await handleCategorizeTransactionsRequest(
      validRequest(250),
    );
    const body = await response.json();

    assertEquals(response.status, 200);
    assertEquals(callCount, 3);
    assertEquals(body.errors, []);
    assertEquals(body.suggestions.length, 250);
    assertEquals(body.suggestions[0].categoryName, "Pet Care");
  } finally {
    restore();
  }
});

Deno.test("failed chunks return Unknown instead of failing the whole import", async () => {
  const restore = setOpenAiTestEnv();
  globalThis.fetch = async () =>
    new Response(JSON.stringify({ error: "rate limited" }), {
      status: 429,
      headers: { "Content-Type": "application/json" },
    });

  try {
    const response = await handleCategorizeTransactionsRequest(
      validRequest(120),
    );
    const body = await response.json();

    assertEquals(response.status, 200);
    assertEquals(body.errors.length, 2);
    assertEquals(body.suggestions.length, 120);
    assertEquals(
      body.suggestions.every((suggestion: { categoryName: string }) =>
        suggestion.categoryName === "Unknown"
      ),
      true,
    );
  } finally {
    restore();
  }
});

function setOpenAiTestEnv() {
  const originalFetch = globalThis.fetch;
  const originalKey = Deno.env.get("OPENAI_API_KEY");
  Deno.env.set("OPENAI_API_KEY", "test-key");
  return () => {
    globalThis.fetch = originalFetch;
    if (originalKey == null) {
      Deno.env.delete("OPENAI_API_KEY");
    } else {
      Deno.env.set("OPENAI_API_KEY", originalKey);
    }
  };
}

function validRequest(count: number) {
  return new Request("http://localhost", {
    method: "POST",
    headers: {
      Authorization: "Bearer test-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      allowedCategories: ["Unknown"],
      transactions: Array.from({ length: count }, (_, index) => ({
        key: `txn-${index}`,
        date: "2025-01-01",
        amount: -12.34,
        description: `Merchant ${index}`,
      })),
    }),
  });
}

function transactionsFromOpenAiRequest(init?: RequestInit) {
  const body = JSON.parse(String(init?.body ?? "{}"));
  const content = body.messages?.[1]?.content;
  if (typeof content !== "string") return [];
  const marker = "T:";
  const index = content.indexOf(marker);
  if (index < 0) return [];
  return JSON.parse(content.slice(index + marker.length)) as Array<{
    k: string;
  }>;
}

function openAiJsonResponse(
  suggestions: Array<{ key: string; categoryName: string }>,
) {
  return new Response(
    JSON.stringify({
      choices: [
        {
          message: {
            content: JSON.stringify({ suggestions }),
          },
        },
      ],
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
}
