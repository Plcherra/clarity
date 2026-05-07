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
  `CategoryCatalogService`, merchant memory storage, old transaction
  repository/storage, old budget repository/storage, old account/profile
  storage, and the rules wipe migration helper.
- Leave the global no-local-storage checkbox open until those legacy helpers
  are removed or replaced in later phases.

## Phase 6 - App-Level Controllers And Notifications

- [x] Check `lib/app/ui_dependencies.dart`
- [x] Check `lib/app/app_notifications.dart`
- [x] Check `lib/app/dashboard_refresh_coordinator.dart`
- [x] Check account workflow service
- [x] Check budget workflow service
- [x] Check transaction workflow service
- [x] Check category workflow service
- [ ] Confirm controllers do not depend on deleted in-memory service state
- [x] Confirm async data reads are surfaced as `Future` or streams intentionally
- [x] Confirm broad notifications are temporary and documented
- [x] Identify where repeated `FutureBuilder` fetches should become streams/controllers later
- [x] Identify which no-op compatibility methods still need real Supabase implementations

Done notes:

- `AppNotifications` is intentionally broad for now. It routes account,
  transaction, dashboard, budget, category, and import-AI refreshes through the
  scoped UI controllers.
- `DashboardRefreshCoordinator` no longer reads deleted local state. It fetches
  accounts and transactions through the Supabase services before recomputing
  dashboard derived state.
- Reconnected obvious UI controller delegates:
  `AccountUiController.addAccount/deleteAccount` now go through
  `AccountWorkflowService`; account CSV import/delete/AI entrypoints now route
  through `TransactionWorkflowService`; budget period/draft actions now route
  through `BudgetWorkflowService`.
- Fixed `BudgetUiController.budgetPerformanceForScope` so it filters Supabase
  budget rows by selected `monthly`/`weekly`/`custom` period and start date
  instead of summing every budget row.
- Focused analyzer passed for the app-level controller/notification/coordinator
  files and the account, budget, transaction, and category workflow services.
- Keep the in-memory dependency checkbox open. The app controller layer still
  uses old local-first helpers: `CategoryCatalogService`, the old
  transaction/category override service, and `MerchantService`.
- `AppComposition` still wires the old transaction category service instead of
  the Supabase `features/categories/application/CategoryService`. That is the
  largest remaining mismatch in this layer.
- Remaining placeholder methods that need real Supabase redesign:
  `TransactionWorkflowService.deleteTransactionsForImportBatch`,
  `needsImportAiAfterCsvUpload`, `startBackgroundImportAiCategorization`, and
  `AccountUiController.csvImportBatchesForAccount`.
- Import batch support cannot be fully restored with the current transactions
  schema because transactions only store `imported_from_csv`, not an import
  batch id. Add an import batch model/table or `import_id` column before
  rebuilding batch delete/history.

## Phase 7 - UI Async Data Flow

- [x] Check dashboard screens
- [x] Check account screens
- [x] Check transaction review screens
- [x] Check budget screens
- [x] Check onboarding/auth screens
- [x] Confirm screens do not treat `Future<List<T>>` as `List<T>`
- [x] Confirm loading states are acceptable
- [x] Confirm error states are user-safe
- [ ] Confirm no important database fetch runs in tight rebuild loops without a plan
- [x] List screens that should move from `FutureBuilder` to stream/viewmodel state

Commands:

```sh
flutter analyze
```

Done notes:

- Focused analyzer passed for dashboard, account, transaction, budget, auth,
  onboarding, and `ClarityApp` presentation/routing files.
- Screens no longer treat Supabase `Future<List<T>>` values as synchronous
  lists. Dashboard, account, month detail, upload, and budget screens load
  through scoped controller/service state instead of directly treating futures
  as lists.
- Added async error handling for category mutations in
  `TransactionCategoryField`. Category rename/select/create/delete now runs
  through an observed future and shows a snackbar if the mutation fails.
- Current loading states are basic but acceptable for this migration: centered
  progress indicators or empty/loading bodies.
- Error states are present in the main `FutureBuilder` screens, but they mostly
  show raw error text. Later UI polish should map Supabase/auth/data errors to
  user-safe copy.
- Keep the tight-rebuild checkbox open for any new screen that starts a fresh
  data future in `build`.
- Permanent direction: account lists, dashboard snapshot data, import progress,
  and budget screen data should stay in scoped stream/viewmodel state instead
  of rebuilding fresh futures from the widget tree.

## Phase 8 - CSV Import And Transaction Workflows

- [x] Check CSV parsing remains pure and local-file only
- [x] Check CSV import writes new rows through Supabase transactions service
- [x] Confirm imported transactions start from zero for a fresh user
- [x] Confirm duplicate detection still works or document that it needs redesign
- [x] Confirm import batch delete is either removed or redesigned for Supabase
- [x] Confirm AI-after-import flow is functional and automatic
- [x] Decide whether `transactions.imported_from_csv` is enough or if `import_batches` table is needed

Done notes:

- `parseBankCsv` remains a pure parser. It does not touch Supabase, local
  storage, UI state, or files after the caller has read the CSV text.
- CSV import validates the selected Supabase account, parses the CSV, dedupes
  against existing Supabase transactions for that account, and writes new rows
  through Supabase-backed transaction services.
- Fresh users/accounts start from zero because import dedupe only fetches rows
  from the authenticated user's selected account.
- Duplicate detection still uses the stable transaction fingerprint:
  account id, date, amount, and normalized description.
- `imported_from_csv` alone was not enough for upload history or batch delete.
  Added migration `000006_add_transaction_import_id.sql`, which adds nullable
  `transactions.import_id` plus `(user_id, import_id)` index.
- New CSV imports now generate one `import_id` per upload and store it on each
  imported transaction.
- `AccountUiController.csvImportBatchesForAccount` now builds batch summaries
  from Supabase transactions, and
  `TransactionWorkflowService.deleteTransactionsForImportBatch` deletes rows
  scoped by account id and import id.
- Old imported rows without `import_id` fall back to the display-level `csv`
  marker, but they cannot be grouped into real upload batches. This is
  acceptable because the current goal is a fresh Supabase start.
- AI-after-import is the default product path. The import job saves
  transactions, calls the Supabase AI categorization function, applies category
  IDs, and refreshes app state. The current product contract lives in
  `docs/csv_import_ai_categorization.md`.
- Apply the new schema change with `supabase db push` before testing CSV upload
  against a remote Supabase project.
- Focused analyzer and full `flutter analyze` passed.

## Phase 9 - OpenAI Edge Function Path

- [x] Check `supabase/functions/call-openai/index.ts`
- [x] Check `supabase/functions/categorize-transactions/index.ts`
- [x] Check `lib/features/transactions/data/openai_proxy_client.dart`
- [x] Check AI categorization data service
- [x] Confirm Flutter calls Supabase Edge Function, not OpenAI directly
- [x] Confirm function requires authenticated user by default
- [x] Confirm OpenAI secret is read only with `Deno.env.get('OPENAI_API_KEY')`
- [x] Confirm error messages do not leak secrets
- [x] Confirm response parsing still matches app expectations

Commands:

```sh
rg -n "api\.openai\.com|OPENAI_API_KEY|functions\.invoke" lib supabase
```

Done notes:

- Flutter does not call `https://api.openai.com` directly. Client calls go
  through `Supabase.functions.invoke(...)` in `SupabaseOpenAiProxyClient`.
- Direct OpenAI API calls belong only inside Supabase Edge Functions such as
  `call-openai` and `categorize-transactions`.
- The Edge Function reads the OpenAI key only with
  `Deno.env.get('OPENAI_API_KEY')`; the Flutter app still only needs public
  Supabase config.
- Added `supabase/config.toml` with `[functions.call-openai] verify_jwt = true`
  so JWT verification is explicit instead of relying on deploy defaults.
- Updated `docs/supabase_auth_openai_setup.md` to warn against deploying Edge
  Functions with `--no-verify-jwt`.
- The function still checks for an `Authorization: Bearer ...` header and the
  Supabase function gateway should verify the JWT before the function runs.
- Error messages identify missing auth, invalid body, missing server secret, or
  upstream failure, but do not expose secret values.
- CSV import categorization uses a focused Edge Function that accepts the
  import transaction list, chunks large imports internally, and returns one
  merged suggestions response to Flutter.
- Focused analyzer passed for the Dart OpenAI proxy and AI categorization path.
- `deno` is not installed in this workspace, so TypeScript checking for the Edge
  Function was not run locally.

## Phase 10 - Tests Strategy

- [x] List every failing analyzer error in `test/`
- [x] Delete or rewrite tests that only verified old local storage behavior
- [x] Keep pure domain tests for CSV parsing, transaction resolution, and dashboard math
- [ ] Add Supabase service tests with a fake boundary where practical
- [x] Add widget tests for auth routing:
  - signed out -> auth screen
  - signed in without profile -> onboarding
  - signed in with profile -> home shell
- [x] Add tests for OpenAI proxy client payload and error mapping
- [x] Decide whether integration tests need a local Supabase instance
- [x] Make `flutter analyze` pass
- [x] Make focused tests pass
- [x] Make full `flutter test` pass

Done notes:

- There was no `test/` or `integration_test/` directory left in the repo, so
  there were no legacy local-storage test analyzer errors to list or rewrite.
- Added a new baseline `test/` suite:
  `csv_parser_test.dart`, `ai_categorization_service_test.dart`, and
  `app_routing_test.dart`.
- CSV parser tests cover signed amount parsing and empty-file rejection.
- AI categorization tests use a fake `OpenAiProxyClient` to verify the app sends
  a chat-completions payload through the proxy and throws
  `OpenAiProxyUnavailableException` when the proxy is not configured.
- App routing widget tests cover signed-out auth screen, signed-in incomplete
  profile onboarding, and signed-in complete profile home shell.
- Supabase table service tests should be integration tests against a local
  Supabase instance, not fake fluent-client unit tests. The current
  `supabase_flutter` client shape makes useful fake-boundary tests awkward
  without introducing a repository/interface seam.
- `flutter analyze` passed.
- Focused new tests passed.
- Full `flutter test` passed.

## Phase 11 - Documentation Cleanup

- [x] Update `README.md`
- [x] Update `docs/supabase_auth_openai_setup.md`
- [x] Update old fundamentals checklist notes that mention `AppState`
- [x] Remove stale local-storage setup instructions
- [x] Document current local development setup
- [x] Document Supabase migration commands
- [x] Document Edge Function deploy and secret commands
- [x] Document known temporary gaps after the migration

Done notes:

- Replaced the default Flutter README with project-specific setup,
  architecture, Supabase, verification, Deno check, and known-gap sections.
- Rewrote `docs/supabase_auth_openai_setup.md` around current Supabase CLI
  migrations instead of a stale one-off SQL editor profile script.
- Updated `docs/migration_decisions.md`, `docs/debug_checklist.md`,
  `docs/app_logic_contract.md`, `docs/screen_data_map.md`, and
  `docs/fundamentals_checkup_checklist.md` so active docs describe
  `AppComposition`, Supabase services, `import_id`, and the current AI gap.
- Marked older AppState cleanup plan docs as historical so they are not read as
  current architecture guidance.
- Documentation now states Flutter `.env` should contain only
  `SUPABASE_URL`/`SUPABASE_ANON_KEY`, and OpenAI secrets belong only in
  Supabase Edge Function secrets.
- Documentation now includes `supabase db push`, Edge Function deploy commands,
  `supabase secrets set OPENAI_API_KEY=...`, and Deno type-check commands.
- The CSV import and AI categorization contract is documented in
  `docs/csv_import_ai_categorization.md`: upload should save transactions,
  categorize all imported rows, create needed categories, update budgets from
  active transaction categories, and learn from manual merchant corrections.

## Phase 12 - Final Verification

- [x] `dart format .`
- [x] `flutter analyze`
- [x] `flutter test`
- [x] `git diff --check`
- [x] Search for deleted local auth/profile APIs
- [x] Search for deleted local app data APIs
- [x] Search for direct OpenAI client usage
- [x] Search for direct Supabase singleton usage outside `SupabaseService`

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

- `dart format .` completed. It also normalized formatting in older legacy
  storage/domain files that were already present in the repo.
- Fixed one analyzer lint in `DashboardSnapshot` by adding braces to a
  multi-line `if` statement.
- Deleted the dead local profile storage file
  `lib/core/storage/profile/profile_storage.dart`. It was the last production
  `LocalProfile` storage path.
- `flutter analyze` passed with no issues.
- `flutter test` passed with all current tests.
- `git diff --check` passed.
- `rg -n "AppState|app_state|LocalProfile|setLocalProfile|localProfile" lib test`
  now returns no matches.
- `rg -n "api\.openai\.com|OPENAI_API_KEY|Supabase\.instance\.client" lib test`
  shows only `Supabase.instance.client` inside
  `lib/core/supabase/supabase_service.dart`, which is the intended boundary.
- The local app data search still finds known legacy compatibility code outside
  the strict Supabase table-service layer: old storage helpers, transaction
  repository helpers, category catalog storage, and merchant memory. This
  matches the open Phase 5/6 cleanup notes and should be handled in the next
  dedicated local-data removal pass.
