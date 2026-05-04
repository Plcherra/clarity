# SharedPreferences to Supabase Migration Plan

## Summary

The app already has Supabase Auth, core Supabase table services, and migrations for profiles, accounts, categories, budgets, and transactions. The remaining work is to finish replacing legacy SharedPreferences-backed repositories and storage helpers with Supabase-backed repositories, then remove the old local storage code entirely.

Default product decision for this plan: this is a fresh Supabase start. Existing SharedPreferences data should not be silently imported into user accounts. If preserving old local data becomes necessary, do it through an explicit, one-time, user-confirmed migration/export flow, not as hidden startup behavior.

Effort scale:

- Small: less than half a day
- Medium: 1-2 days
- Big: 3-5 days

## Current State

Already Supabase-backed:

- Auth and profile ownership
- `profiles`
- `accounts`
- `categories`
- `budgets`
- `transactions`
- `transactions.import_id`
- OpenAI calls through Supabase Edge Function

Remaining local-storage debt:

- `lib/core/storage/accounts/account_storage.dart`
- `lib/core/storage/categories/category_catalog_storage.dart`
- `lib/core/storage/budgets/budget_storage.dart`
- `lib/core/storage/transactions/transaction_storage.dart`
- `lib/core/storage/transactions/transaction_category_storage.dart`
- `lib/core/storage/migrations/rules_wipe_migration.dart`
- `lib/features/budgets/data/budget_repository.dart`
- `lib/features/transactions/data/transaction_repository.dart`
- `lib/features/transactions/data/csv_import_service.dart` still accepts the old `TransactionRepository`
- `lib/features/budgets/application/budget_performance.dart` still depends on old budget repository concepts

## Phase 1: Database Design

Status: mostly done. Keep the existing migrations as the baseline and add only the missing tables needed to remove remaining SharedPreferences behavior.

### Existing Tables

`profiles` - Small

- `id uuid primary key references auth.users(id) on delete cascade`
- `email`
- `full_name`
- `avatar_url`
- timestamps
- RLS by `auth.uid() = id`

`accounts` - Small

- user-owned bank/account records
- indexed by `user_id`
- active account state should be app/session UI state, not persisted globally in SharedPreferences

`categories` - Medium

- user-owned custom categories
- built-in display categories can stay as static app constants
- user-created categories live only in Supabase
- category rename/hide behavior should be represented in Supabase if it remains a product feature

Recommended follow-up columns or table:

- Add `is_hidden_from_picker boolean not null default false` if hidden categories remain supported.
- Add `display_name text` only if rename semantics must differ from canonical `name`.

`budgets` - Medium

- user-owned budget rows
- money uses `numeric(12,2)`
- supports `monthly`, `weekly`, and `custom` only if the current UI needs all three
- ensure `start_date` and any future `end_date` semantics are explicit

Recommended follow-up:

- Add `end_date date` for custom budget periods if custom ranges are kept.
- Add `category_id uuid references public.categories(id) on delete set null` if budgets become category-specific rather than name-keyed.

`transactions` - Medium

- user-owned transaction rows
- account foreign key is required
- category foreign key is nullable
- `imported_from_csv`
- `import_id`
- indexed by `user_id`, `account_id`, `category_id`, and `(user_id, date desc)`

### Missing Or Optional Tables

`csv_import_batches` - Medium

Purpose: replace any local import bookkeeping and make undo/delete-by-upload reliable.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references auth.users(id) on delete cascade`
- `account_id uuid not null`
- `source_filename text`
- `row_count integer not null default 0`
- `created_transaction_count integer not null default 0`
- `duplicate_transaction_count integer not null default 0`
- `status text not null default 'completed'`
- `created_at timestamptz not null default now()`
- RLS: `auth.uid() = user_id`
- Indexes: `(user_id, created_at desc)`, `(user_id, account_id)`

`merchant_category_memory` - Medium

Purpose: replace deprecated merchant memory SharedPreferences if merchant learning returns.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references auth.users(id) on delete cascade`
- `merchant_normalized text not null`
- `category_id uuid references public.categories(id) on delete set null`
- `confidence numeric(5,4)`
- `source text not null default 'user'`
- timestamps
- Unique index: `(user_id, merchant_normalized)`
- RLS: `auth.uid() = user_id`

`ai_category_suggestions` - Medium/Big

Purpose: if low-confidence review and AI suggestion history are product requirements, persist AI suggestions in Supabase instead of local storage.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references auth.users(id) on delete cascade`
- `transaction_id uuid not null`
- `suggested_category_id uuid references public.categories(id) on delete set null`
- `confidence numeric(5,4)`
- `rationale text`
- `model text`
- `prompt_version text`
- `status text not null default 'pending'`
- timestamps
- Unique index: `(user_id, transaction_id, prompt_version)`
- RLS: `auth.uid() = user_id`

## Phase 2: Repository Layer

Goal: one repository boundary for Supabase data and no production imports from `lib/core/storage`.

### Target Shape

Keep `SupabaseRepository` as the composition point:

- `profiles`
- `accounts`
- `categories`
- `budgets`
- `transactions`
- later: `csvImportBatches`
- later: `merchantCategoryMemory`
- later: `aiCategorySuggestions`

Each service should:

- Receive `SupabaseService` through the constructor.
- Resolve the current user through `supabaseService.auth.currentUser`.
- Throw `SupabaseAuthRequiredException` if no user exists.
- Wrap PostgREST failures in `SupabaseDataException`.
- Filter every read/write by authenticated user:
  - profile: `id == user.id`
  - all other tables: `user_id == user.id`
- Expose simple CRUD methods plus streams where screens/controllers benefit from live updates.
- Return table-aligned record models first, then map to UI/domain models in workflow/controller code.

### Repository Cleanup Steps

1. Replace `TransactionRepository` with `TransactionService` everywhere - Medium

- Move CSV import persistence to `TransactionService` or a new Supabase-backed `CsvImportService`.
- Replace delete-by-upload logic with `import_id` or `csv_import_batches`.
- Remove `transaction_storage.dart` once there are no imports.

2. Replace `BudgetRepository` with `BudgetService` everywhere - Medium

- Move budget performance reads to `BudgetService.fetchBudgets()`.
- Remove `budget_storage.dart` and `budget_keys.dart` from production paths.

3. Replace category catalog storage with `CategoryService` plus read model - Small/Medium

- Built-in categories remain static constants.
- User-created or hidden categories come from Supabase.
- Remove `category_catalog_storage.dart`.

4. Remove transaction category override storage - Small/Medium

- Transaction category assignment is `transactions.category_id`.
- Remove `transaction_category_storage.dart`.

5. Remove account storage - Small

- Accounts are already Supabase-backed.
- Remove any remaining active account persistence from SharedPreferences.

6. Remove local migration helper - Small

- Delete `rules_wipe_migration.dart` after all SharedPreferences app-data paths are gone.

## Phase 3: Existing Local Data Strategy

### Recommended Default: Fresh Start

Because the current product direction is to test the Supabase foundation from a clean slate, do not auto-migrate existing SharedPreferences data.

Behavior:

- Ignore old SharedPreferences app data after Supabase login.
- Do not read old account, budget, transaction, category, AI, or merchant-memory keys.
- Do not clear user device preferences unrelated to app data.
- Add a release note or internal QA note stating that financial data starts empty after the Supabase migration.

Effort: Small

### Optional Manual Migration Path

Only build this if preserving local data becomes a requirement.

Flow:

1. User signs in.
2. App detects old local data.
3. App shows a one-time migration prompt.
4. User confirms import.
5. Migration creates Supabase records in this order:
   - accounts
   - categories
   - budgets
   - transactions
   - transaction category assignments
   - import batches
6. App stores a local migration-complete marker.
7. App never reads the old data path again.

Important rules:

- Never run this silently.
- Map old local IDs to Supabase UUIDs.
- Batch inserts where possible.
- Fail safely before deleting or marking old data as migrated.
- Keep an export option before migration if the data matters.

Effort: Big

## Phase 4: Order Of Migration

### 1. Freeze The Supabase Schema Baseline - Small

Actions:

- Review current migrations.
- Add missing schema only for features still backed by SharedPreferences.
- Confirm RLS policies on every user-owned table.
- Confirm `supabase db push` works against the target project.

Exit criteria:

- All required tables exist.
- All tables have `user_id` indexes where applicable.
- All tables have RLS enabled.

### 2. Accounts - Small

Reason: accounts are the parent of transactions and CSV imports.

Actions:

- Ensure all account reads/writes use `AccountService`.
- Remove any old active-account persistence.
- Delete account SharedPreferences storage once unused.

Exit criteria:

- `rg -n "account_storage|SharedPreferences" lib/features/accounts lib/core/storage/accounts` has no production usage.
- Account creation, deletion, and selection work after sign-in.

### 3. Categories - Medium

Reason: transactions and AI categorization depend on category IDs.

Actions:

- Keep built-in categories as constants.
- Store custom categories, hidden picker state, and rename/display behavior in Supabase if those features remain.
- Make category assignment write to `transactions.category_id`.
- Remove category catalog and category override SharedPreferences storage.

Exit criteria:

- No production imports of `category_catalog_storage.dart`.
- No production imports of `transaction_category_storage.dart`.
- Category picker values are built from constants plus Supabase rows.

### 4. Transactions And CSV Import - Big

Reason: largest data volume and highest risk.

Actions:

- Replace old `TransactionRepository` usage with `TransactionService`.
- Update CSV import to create transactions through Supabase.
- Use `import_id` or `csv_import_batches` for upload tracking.
- Make duplicate detection query Supabase, scoped by `user_id` and account.
- Keep parsing pure and local; persist only through Supabase services.

Exit criteria:

- Uploading a CSV into a fresh account creates Supabase transactions.
- Deleting an import batch removes only that user/account/import set.
- No production imports of `transaction_storage.dart`.

### 5. Budgets And Budget Performance - Medium/Big

Reason: budgets currently have legacy repository concepts and period-specific behavior.

Actions:

- Replace `BudgetRepository` usage with `BudgetService`.
- Move budget key/period behavior into domain helpers that do not depend on SharedPreferences.
- Compute budget performance from Supabase budgets and Supabase transactions.
- Add `end_date` or category foreign keys if custom periods/category budgets need stronger schema.

Exit criteria:

- Budget screen works from Supabase records only.
- Budget performance has no dependency on `budget_storage.dart` or `budget_keys.dart`.

### 6. Dashboard And Derived Metrics - Medium

Reason: dashboard should be derived from Supabase-backed accounts, transactions, categories, and budgets.

Actions:

- Keep dashboard calculations in Dart for now unless performance requires SQL views/RPC.
- Ensure dashboard refresh uses repository services only.
- Avoid storing derived dashboard state in Supabase unless it becomes expensive to recompute.

Exit criteria:

- Dashboard reload after transaction/account/budget/category changes is correct.
- No local persistence is used for dashboard inputs.

### 7. AI Suggestions And Merchant Memory - Medium/Big

Reason: OpenAI calls already go through Supabase Edge Function, but persistent suggestion/review history needs a deliberate schema.

Actions:

- Keep current Edge Function path.
- If AI review history is required, add `ai_category_suggestions`.
- If merchant learning returns, add `merchant_category_memory`.
- Do not restore SharedPreferences for either feature.

Exit criteria:

- No AI or merchant-memory data is stored in SharedPreferences.
- AI review screens read from Supabase-backed data if persistent review is required.

### 8. Delete Legacy Local Storage - Small

Actions:

- Delete or deprecate remaining `lib/core/storage/**` app-data files.
- Delete old local repositories after all imports are gone.
- Remove unused tests tied to SharedPreferences storage, or rewrite them against service fakes.

Exit criteria:

- `rg -n "SharedPreferences|core/storage" lib` shows no app-data production usage.
- `rg -n "BudgetRepository|TransactionRepository" lib` shows no old repository usage.
- `flutter analyze` is clean.
- `flutter test` is clean.

## Phase 5: Testing And Verification

Run after each migrated feature:

```sh
dart analyze
flutter analyze
flutter test
git diff --check
```

Run before declaring the migration done:

```sh
rg -n "SharedPreferences|core/storage" lib
rg -n "BudgetRepository|TransactionRepository" lib
rg -n "account_storage|budget_storage|transaction_storage|category_catalog_storage|transaction_category_storage" lib
supabase db push
flutter analyze
flutter test
git diff --check
```

Expected final state:

- Supabase is the only source of truth for user data.
- SharedPreferences is not used for accounts, categories, budgets, transactions, profile, AI suggestions, merchant memory, or import tracking.
- Local parsing and UI state can remain local, but persistence cannot.

## Recommended Immediate Next Step

Start with transactions and CSV import, because that is the biggest remaining local persistence path and it depends on accounts/categories already being Supabase-backed. The first concrete implementation task should be:

1. Replace `TransactionRepository` in CSV import and transaction workflows with `TransactionService`.
2. Use `transactions.import_id` for import tracking.
3. Remove production imports of `transaction_storage.dart`.

Effort: Big
