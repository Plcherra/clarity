# Supabase Auth And OpenAI Edge Function Setup

## Flutter Config

Flutter uses `flutter_dotenv` and `supabase_flutter`.

Local `.env` must contain only public Supabase client config:

```dotenv
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-public-anon-key
```

Never put the OpenAI secret in Flutter `.env`, committed files, assets, or
client-side code.

## Database Schema

Schema lives in Supabase CLI migrations:

```text
supabase/migrations/000001_create_profiles_table.sql
supabase/migrations/000002_create_accounts_table.sql
supabase/migrations/000003_create_categories_table.sql
supabase/migrations/000004_create_budgets_table.sql
supabase/migrations/000005_create_transactions_table.sql
supabase/migrations/000006_add_transaction_import_id.sql
```

Apply migrations:

```sh
supabase db push
```

Verify migration status:

```sh
supabase migration list
```

All app tables use RLS. Profiles are keyed by `auth.users(id)`. Accounts,
categories, budgets, and transactions are scoped by `user_id`. Transactions
also include `import_id` for CSV upload history and batch deletion.

## Edge Function

The function lives at `supabase/functions/call-openai/index.ts`.

`supabase/config.toml` explicitly keeps JWT verification enabled:

```toml
[functions.call-openai]
verify_jwt = true
```

Deploy it:

```sh
supabase functions deploy call-openai
```

Do not deploy this function with `--no-verify-jwt`; the Flutter app must call it
with the signed-in user's Supabase session.

Set the server-side OpenAI secret:

```sh
supabase secrets set OPENAI_API_KEY=your-real-openai-key
```

Run locally:

```sh
supabase functions serve call-openai --env-file supabase/functions/.env
```

For local Edge Function testing only, `supabase/functions/.env` may contain:

```dotenv
OPENAI_API_KEY=your-real-openai-key
```

Do not commit that file.

Type-check the Edge Function after installing Deno:

```sh
deno check supabase/functions/call-openai/index.ts
```

## Flutter AI Boundary

Flutter calls the Edge Function through
`Supabase.functions.invoke('call-openai')` in
`lib/features/transactions/data/openai_proxy_client.dart`.

The only direct `https://api.openai.com` call should be inside
`supabase/functions/call-openai/index.ts`.
