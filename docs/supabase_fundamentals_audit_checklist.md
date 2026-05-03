# Supabase Fundamentals Audit Checklist

Use this checklist after the Supabase Auth, profile, data-service, and OpenAI
Edge Function migration. Mark each task with `[x]` when completed and add a
short note under the phase.

Goal: make the app foundation coherent before adding new features or rewriting
tests.

## Phase 1 - Startup, Composition, And Routing

- [x] Check `lib/main.dart`
- [x] Check `lib/app/bootstrap.dart`
- [x] Check `lib/app/app.dart`
- [x] Check `lib/app/app_composition.dart`
- [x] Check `lib/app/app_startup_service.dart`
- [x] Confirm Supabase initializes once before services are created
- [x] Confirm `.env` is loaded before `SupabaseService.initializeFromEnv()`
- [x] Confirm `ClarityApp` route order is correct:
  - no session -> auth screen
  - session without complete profile -> onboarding/profile setup
  - session with profile -> home shell
- [x] Confirm app startup does not hydrate deleted local app data
- [x] Confirm composition owns construction only and does not become another god object

Done notes:

- `main()` remains a thin call into `bootstrap()`.
- `bootstrap()` now loads `.env`, initializes Supabase, creates `AppComposition`,
  starts Supabase startup hydration/watchers, hydrates the current profile, then
  runs `ClarityApp`.
- Removed the old `runRulesWipeMigrationIfNeeded()` call from startup because it
  touched deleted local app storage.
- `AppStartupService` now listens to auth changes. If the user signs in after
  app launch, it fetches initial Supabase data and starts account/budget/
  transaction streams. If the user signs out, it stops those streams and
  notifies scoped UI controllers.
- `ClarityApp` route order is auth first, then profile completeness, then
  `HomeShell`.
- `AppComposition` still contains wiring callbacks, but no feature data source
  logic was added back into it.

## Phase 2 - Environment And Secrets

- [x] Check `.env`
- [x] Check `.gitignore`
- [x] Check `lib/core/supabase/supabase_service.dart`
- [x] Check `lib/core/constants/`
- [x] Search for `OPENAI_API_KEY`
- [x] Search for `api.openai.com`
- [x] Search for `SUPABASE_URL`
- [x] Search for `SUPABASE_ANON_KEY`
- [x] Confirm Flutter `.env` contains only public Supabase config
- [x] Confirm OpenAI key is not in Flutter code, assets, docs examples that look real, or committed env files
- [x] Confirm Edge Function secret setup is documented
- [x] Confirm missing Supabase config fails with a clear error

Commands:

```sh
rg -n "OPENAI_API_KEY|api\.openai\.com|Constants\.openAIKey" lib test docs supabase
rg -n "SUPABASE_URL|SUPABASE_ANON_KEY" .
```

Done notes:

- `.env` currently contains only `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
  Values were checked without printing them.
- `.env` is ignored by Git, including `supabase/functions/.env`.
- Updated `.gitignore` wording so it no longer implies the Flutter `.env`
  should contain an OpenAI key.
- `lib/core/constants/` currently has no constants files, so there is no old
  `Constants.openAIKey` path to clean.
- `SupabaseService` reads only `SUPABASE_URL` and `SUPABASE_ANON_KEY`, validates
  both are present, initializes Supabase once from bootstrap, and uses
  `debug: kDebugMode`.
- No Flutter client code calls `https://api.openai.com`.
- `api.openai.com` and `Deno.env.get('OPENAI_API_KEY')` appear only in
  `supabase/functions/call-openai/index.ts`, which is the correct server-side
  boundary.
- Docs reference `OPENAI_API_KEY` only as Supabase Edge Function secret setup
  guidance or audit checklist text, not as a Flutter client config value.

## Phase 3 - Auth And Profile Ownership

- [x] Check `lib/features/auth/application/auth_service.dart`
- [x] Check `lib/features/auth/application/auth_controller.dart`
- [x] Check `lib/features/auth/presentation/auth_screen.dart`
- [x] Check `lib/features/profile/application/profile_service.dart`
- [x] Check `lib/features/profile/application/profile_controller.dart`
- [x] Check `lib/features/onboarding/presentation/onboarding_screen.dart`
- [x] Confirm profile state is Supabase-backed only
- [x] Confirm no `LocalProfile` storage is used by production auth/profile flow
- [x] Confirm sign up handles both immediate session and email-confirmation flows
- [x] Confirm sign out clears profile state
- [x] Confirm profile setup writes to `profiles`
- [x] Confirm profile reads are scoped to current authenticated user

Commands:

```sh
rg -n "LocalProfile|profile_storage|setLocalProfile|localProfile" lib
```

Done notes:

- `AuthService` is a thin Supabase Auth wrapper for email/password sign up,
  sign in, sign out, current session/user, and auth state changes.
- `AuthController` handles loading/error/info state and supports both immediate
  session sign-up and email-confirmation sign-up. When Supabase returns no
  session, it shows the "check your email" info message.
- `ProfileService` reads, upserts, updates, and watches only the current
  authenticated user's `profiles` row.
- `ProfileController` stores `ProfileRecord? profile`, clears it on sign-out,
  and listens for profile row changes while signed in.
- Removed `LocalProfile` from the production onboarding/profile setup flow.
  `OnboardingScreen` now accepts `saveProfileName(String fullName)`.
- Removed direct `HomeShell` navigation from onboarding. After profile save,
  `ProfileController` notifies listeners and `ClarityApp` performs the normal
  route decision.
- Focused analyzer passed for auth, profile, onboarding, and app routing files.

## Phase 4 - Supabase Schema And RLS

- [x] Check `supabase/migrations/000001_create_profiles_table.sql`
- [x] Check `supabase/migrations/000002_create_accounts_table.sql`
- [x] Check `supabase/migrations/000003_create_categories_table.sql`
- [x] Check `supabase/migrations/000004_create_budgets_table.sql`
- [x] Check `supabase/migrations/000005_create_transactions_table.sql`
- [x] Confirm every user-owned table has `user_id` or profile `id`
- [x] Confirm RLS is enabled on every app table
- [x] Confirm policies restrict access to `auth.uid()`
- [x] Confirm `updated_at` trigger exists on each table
- [x] Confirm money columns use `numeric(12,2)`
- [x] Confirm transactions use user-scoped foreign keys where needed
- [x] Confirm indexes exist for `user_id` and common query paths

Commands:

```sh
supabase migration list
supabase db push
```

Done notes:

- The five migrations are ordered one table per file and all app tables have
  user ownership through `user_id`; `profiles.id` correctly references
  `auth.users(id)`.
- RLS is enabled on profiles, accounts, categories, budgets, and transactions.
  Policies use `auth.uid()` to restrict reads/writes to the authenticated user.
- `public.set_updated_at()` is defined in the profiles migration and attached
  to every app table.
- Money columns use `numeric(12,2)` for account balances, budgets, and
  transaction amounts.
- Transactions use composite user-scoped foreign keys for account/category
  ownership. This prevents linking a transaction to another user's account or
  category.
- Fixed the budget period contract. The app supports monthly, weekly, and
  custom budgets, so the budgets migration now allows those values instead of
  only `monthly`/`yearly`.
- Fixed the Dart budget period mapping so weekly and custom budgets are stored
  as `weekly` and `custom`, not silently collapsed into `monthly`.
- Added a budgets index on `(user_id, period, start_date)` for the current
  period lookup path.
- Focused analyzer passed for the budget workflow and budget viewmodel files.

## Phase 5 - Supabase Service Layer

- [x] Check `lib/core/supabase/supabase_service.dart`
- [x] Check `lib/core/supabase/supabase_exceptions.dart`
- [x] Check `lib/core/supabase/supabase_records.dart`
- [x] Check `lib/core/supabase/supabase_repository.dart`
- [x] Check account service
- [x] Check category service
- [x] Check budget service
- [x] Check transaction service
- [x] Check profile service
- [x] Confirm every Supabase table service requires injected `SupabaseService`
- [x] Confirm only `SupabaseService` references `Supabase.instance.client`
- [ ] Confirm no service uses `SharedPreferences`, local files, Hive, or old storage helpers
- [x] Confirm every Supabase table-service query filters by current authenticated user
- [x] Confirm missing auth throws `SupabaseAuthRequiredException`
- [x] Confirm Supabase failures are wrapped in `SupabaseDataException`
- [x] Confirm Supabase table-service APIs are table CRUD/stream APIs only

Commands:

```sh
rg -n "Supabase\.instance\.client" lib
rg -n "SharedPreferences|core/storage|hydratePersisted|saveAccounts|loadAccounts|saveTransactions|loadTransactions" lib/core/supabase lib/features
```

Done notes:

- The strict Supabase table-service layer is clean: profile, accounts,
  categories, budgets, and transactions all require injected
  `SupabaseService`.
- `SupabaseService` is the only production file that references
  `Supabase.instance.client`.
- `SupabaseRepository` only composes the five table services and does not cache
  data.
- Each table service resolves the current Supabase user and throws
  `SupabaseAuthRequiredException` if there is no signed-in user.
- Profile queries filter by `profiles.id == user.id`; accounts, categories,
  budgets, and transactions filter by `user_id == user.id`.
- CRUD failures are wrapped in `SupabaseDataException` with table/action
  context.
- Focused analyzer passed for the core Supabase files and the five table
  services.
- The broader codebase is not fully clean yet. Old local-storage-backed helpers
  still exist outside the strict table-service layer:
  `CategoryCatalogService`, AI suggestion storage, merchant memory storage,
  old transaction repository/storage, old budget repository/storage, old
  account/profile storage, and the rules wipe migration helper.
- Leave the global no-local-storage checkbox open until those legacy helpers
  are removed or replaced in later phases.

## Phase 6 - App-Level Controllers And Notifications

- [ ] Check `lib/app/ui_dependencies.dart`
- [ ] Check `lib/app/app_notifications.dart`
- [ ] Check `lib/app/dashboard_refresh_coordinator.dart`
- [ ] Check account workflow service
- [ ] Check budget workflow service
- [ ] Check transaction workflow service
- [ ] Check category workflow service
- [ ] Confirm controllers do not depend on deleted in-memory service state
- [ ] Confirm async data reads are surfaced as `Future` or streams intentionally
- [ ] Confirm broad notifications are temporary and documented
- [ ] Identify where repeated `FutureBuilder` fetches should become streams/controllers later
- [ ] Identify which no-op compatibility methods still need real Supabase implementations

Done notes:

## Phase 7 - UI Async Data Flow

- [ ] Check dashboard screens
- [ ] Check account screens
- [ ] Check transaction review screens
- [ ] Check budget screens
- [ ] Check onboarding/auth screens
- [ ] Confirm screens do not treat `Future<List<T>>` as `List<T>`
- [ ] Confirm loading states are acceptable
- [ ] Confirm error states are user-safe
- [ ] Confirm no important database fetch runs in tight rebuild loops without a plan
- [ ] List screens that should move from `FutureBuilder` to stream/viewmodel state

Commands:

```sh
flutter analyze
```

Done notes:

## Phase 8 - CSV Import And Transaction Workflows

- [ ] Check CSV parsing remains pure and local-file only
- [ ] Check CSV import writes new rows through Supabase transactions service
- [ ] Confirm imported transactions start from zero for a fresh user
- [ ] Confirm duplicate detection still works or document that it needs redesign
- [ ] Confirm import batch delete is either removed or redesigned for Supabase
- [ ] Confirm AI-after-import flow is either functional or clearly disabled
- [ ] Decide whether `transactions.imported_from_csv` is enough or if `import_batches` table is needed

Done notes:

## Phase 9 - OpenAI Edge Function Path

- [ ] Check `supabase/functions/call-openai/index.ts`
- [ ] Check `lib/features/transactions/data/openai_proxy_client.dart`
- [ ] Check AI categorization data service
- [ ] Confirm Flutter calls Supabase Edge Function, not OpenAI directly
- [ ] Confirm function requires authenticated user by default
- [ ] Confirm OpenAI secret is read only with `Deno.env.get('OPENAI_API_KEY')`
- [ ] Confirm error messages do not leak secrets
- [ ] Confirm response parsing still matches app expectations

Commands:

```sh
rg -n "api\.openai\.com|OPENAI_API_KEY|functions\.invoke" lib supabase
```

Done notes:

## Phase 10 - Tests Strategy

- [ ] List every failing analyzer error in `test/`
- [ ] Delete or rewrite tests that only verified old local storage behavior
- [ ] Keep pure domain tests for CSV parsing, transaction resolution, and dashboard math
- [ ] Add Supabase service tests with a fake boundary where practical
- [ ] Add widget tests for auth routing:
  - signed out -> auth screen
  - signed in without profile -> onboarding
  - signed in with profile -> home shell
- [ ] Add tests for OpenAI proxy client payload and error mapping
- [ ] Decide whether integration tests need a local Supabase instance
- [ ] Make `flutter analyze` pass
- [ ] Make focused tests pass
- [ ] Make full `flutter test` pass

Done notes:

## Phase 11 - Documentation Cleanup

- [ ] Update `README.md`
- [ ] Update `docs/supabase_auth_openai_setup.md`
- [ ] Update old fundamentals checklist notes that mention `AppState`
- [ ] Remove stale local-storage setup instructions
- [ ] Document current local development setup
- [ ] Document Supabase migration commands
- [ ] Document Edge Function deploy and secret commands
- [ ] Document known temporary gaps after the migration

Done notes:

## Phase 12 - Final Verification

- [ ] `dart format .`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `git diff --check`
- [ ] Search for deleted local auth/profile APIs
- [ ] Search for deleted local app data APIs
- [ ] Search for direct OpenAI client usage
- [ ] Search for direct Supabase singleton usage outside `SupabaseService`

Commands:

```sh
dart format .
flutter analyze
flutter test
git diff --check
rg -n "AppState|app_state|LocalProfile|setLocalProfile|localProfile" lib test
rg -n "SharedPreferences|core/storage|hydratePersisted|transactionsByAccount|activeAccountId" lib
rg -n "api\.openai\.com|OPENAI_API_KEY|Supabase\.instance\.client" lib test
```

Done notes:
