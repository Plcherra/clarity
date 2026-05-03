const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Missing Supabase auth token' }, 401);
  }

  const openAiApiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openAiApiKey) {
    return jsonResponse({ error: 'Missing OPENAI_API_KEY secret' }, 500);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const messages = payload.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return jsonResponse({ error: 'messages must be a non-empty array' }, 400);
  }

  const openAiBody: Record<string, unknown> = {
    model: typeof payload.model === 'string' ? payload.model : 'gpt-4o-mini',
    messages,
  };

  if (typeof payload.temperature === 'number') {
    openAiBody.temperature = payload.temperature;
  }
  if (payload.response_format && typeof payload.response_format === 'object') {
    openAiBody.response_format = payload.response_format;
  }

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${openAiApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(openAiBody),
  });

  let data: unknown;
  try {
    data = await response.json();
  } catch {
    data = { error: 'OpenAI returned a non-JSON response' };
  }

  return jsonResponse(data, response.status);
});
