# Clarity

Flutter personal finance app with Supabase Auth, Supabase-backed profile and
financial tables, CSV import, dashboard/budget views, and AI categorization
through a Supabase Edge Function.

Feature contract: [`docs/csv_import_ai_categorization.md`](docs/csv_import_ai_categorization.md)
is the source of truth for CSV import, automatic AI categorization, category
creation, Budget page category visibility, and merchant learning.

## Current Architecture

- App startup: `lib/main.dart` -> `lib/app/bootstrap.dart`
- Composition root: `lib/app/app_composition.dart`
- Routing shell: `lib/app/app.dart`
- UI controller wiring: `lib/app/ui_dependencies.dart`
- Supabase boundary: `lib/core/supabase/`
- Feature-first UI and workflows: `lib/features/`

`AppState` has been removed. Auth/profile routing is owned by
`AuthController` and `ProfileController`. App data services use Supabase table
services through `SupabaseRepository`.

## Local Setup

Install dependencies:

```sh
flutter pub get
```

Create a local `.env` file:

```dotenv
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-public-anon-key
```

Only public Supabase config belongs in Flutter `.env`. Do not put
`OPENAI_API_KEY` or other server secrets in Flutter config.

## Supabase

Apply database migrations:

```sh
supabase db push
```

Deploy the OpenAI Edge Functions:

```sh
supabase functions deploy call-openai
supabase functions deploy categorize-transactions
supabase secrets set OPENAI_API_KEY=your-real-openai-key
```

Keep JWT verification enabled for Edge Functions. Do not deploy these functions
with `--no-verify-jwt`.

## Verification

Run:

```sh
flutter analyze
flutter test
git diff --check
```

Optional Edge Function type check, after installing Deno:

```sh
deno check supabase/functions/call-openai/index.ts
deno check supabase/functions/categorize-transactions/index.ts
```

## Product Direction

- CSV import is intended to be near-zero effort: select a file, save
  transactions, categorize everything with AI, apply categories, then refresh
  dashboard and budgets.
- Budget categories should be driven by categories that actually have
  transactions, not an empty static list.
- Manual category corrections should become Supabase-backed merchant learning
  and apply to matching past and future transactions.
