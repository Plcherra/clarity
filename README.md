# Clarity

Flutter personal finance app with Supabase Auth, Supabase-backed profile and
financial tables, CSV import, dashboard/budget views, and AI categorization
through a Supabase Edge Function.

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

Deploy the OpenAI proxy Edge Function:

```sh
supabase functions deploy call-openai
supabase secrets set OPENAI_API_KEY=your-real-openai-key
```

`supabase/config.toml` keeps JWT verification enabled for `call-openai`.
Do not deploy this function with `--no-verify-jwt`.

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
```

## Known Temporary Gaps

- Category catalog, merchant memory, and AI suggestion storage still have
  local-storage-backed compatibility helpers.
- AI categorization after CSV import is temporarily disabled until category
  assignments are fully Supabase-backed.
- Some screens still use `FutureBuilder` directly and should later move to
  scoped stream/viewmodel state.
