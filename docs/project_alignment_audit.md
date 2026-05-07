# Project Alignment Audit

Date: 2026-05-06  
Source of truth reviewed first:
[`csv_import_ai_categorization.md`](csv_import_ai_categorization.md)

This audit compares the current project against the CSV import and AI
categorization product contract. It is intended to be the master roadmap for
the next phase of development.

## 1. Project Vision Summary

Clarity should feel like a near-zero-effort finance app: the user uploads a CSV
bank statement, Clarity saves every non-duplicate transaction, categorizes all
transactions automatically with AI, creates useful categories when needed,
updates dashboard and budget views without a review queue, and learns from
manual corrections so matching past and future merchants are categorized
consistently. The Budget page should be driven by real transaction activity, not
static or stale category lists, and the architecture must scale to large imports
and many users without dropping rows, timing out unpredictably, or mixing local
state with Supabase data.

## 2. Current State Vs Desired State

### CSV Import

| Area | New docs require | Current code/docs | Gap |
|------|------------------|-------------------|-----|
| Primary flow | User selects account/file and one import job parses, saves, categorizes, applies categories, and refreshes. | `CsvImportService.importAndCategorize(...)` exists in `lib/features/transactions/data/csv_import_service.dart` and is called through `TransactionWorkflowService.loadFromCsv(...)`. | Direction is right, but the public UI still passes CSV text through `TransactionWorkflowService`, which writes a temp file. The service API wants `File csvFile`; the UI abstraction still has old shape. |
| Progress | Progress starts immediately after file selection and covers parsing, saving, AI, applying, refreshing, complete/failed. | `CsvImportProgress` and `ImportAiProgressBanner` exist. Account detail and account selection can show import status. | Initial `UploadScreen` only shows a button spinner while reading/picking before account selection. The progress model is still named "AI" in `AiCategorizationApplicationService` and `ImportAiStatusController`, even though it now represents the whole import. |
| Duplicate detection | Dedupe against all existing transactions for the account, not only first 1000. | `TransactionService.fetchTransactions(...)` paginates with `_transactionPageSize = 1000`, and import dedupes with transaction fingerprints. | This is aligned at service level. Needs tests for >1000 existing rows and for the provided large CSV. |
| Insert behavior | Save all non-duplicate transactions and keep inserted IDs for category assignment. | `TransactionService.createTransactions(...)` bulk inserts chunks and returns inserted `TransactionRecord`s. | Good baseline. Needs tests for partial insert failure and returned row count consistency. |
| Deletion | Delete one CSV import by account + `import_id`. | `deleteTransactionsForImportBatch(...)` exists and account detail shows a blocking dialog. | Mostly aligned. Needs manual verification and tests for import batch deletion count. |

### AI Categorization

| Area | New docs require | Current code/docs | Gap |
|------|------------------|-------------------|-----|
| Automatic categorization | Every newly inserted transaction must end with AI category, learned merchant category, or `Unknown`. | Import calls `_categorizeInsertedRows(...)`, catches AI errors, then `_applyCategories(...)` assigns suggested categories or `Unknown`. | Good baseline for AI or `Unknown`. Learned merchant category path does not exist. |
| One app request | Flutter makes one categorization request per import; Edge Function chunks internally. | `SupabaseOpenAiProxyClient.categorizeTransactions(...)` invokes `categorize-transactions`. Edge Function chunks at `maxTransactionsPerOpenAiCall = 400`, concurrency `4`. | Aligned structurally. The Flutter timeout is 5 minutes; large/global imports may still fail. No retry/fallback per chunk. |
| AI-created categories | AI may create new category names on first upload. | Flutter sends only `kSelectableSpendCategories`. Edge Function requires each category to be from allowed list and normalizes anything else to `Unknown`. `_parseCategorizationResponse(...)` also rejects categories outside built-ins + `Unknown`. | Critical mismatch. Current AI cannot create new categories. It can only select built-ins or `Unknown`. |
| Accuracy | AI should categorize all transactions correctly enough for a zero-effort baseline. | Prompt is minimal and category list is limited. No confidence, merchant memory, examples, or schema validation beyond JSON shape. | Accuracy risk remains high, especially for ambiguous merchants, transfers, payroll, refunds, and local businesses. |
| Error handling | AI failure should not roll back saved rows; user sees persistent failure state. | AI failures are converted to `Unknown`; final snack says AI failed. `CsvImportProgress.failed` rethrows for hard failures. | Good baseline, but final error is still a snackbar and can disappear. Need persistent UI/history for import results. |
| Security | OpenAI key only in Supabase Edge Function. | Direct `api.openai.com` calls only in Edge Functions. | Good. `supabase/config.toml` currently only explicitly lists `call-openai`; `categorize-transactions` should also have explicit JWT verification. |

### Budget Page

| Area | New docs require | Current code/docs | Gap |
|------|------------------|-------------------|-----|
| Category source | Budget page should show categories that actually have transactions. | `BudgetsViewModel.sortedRows()` uses `categoryPickerCanonicals(...)`, which returns built-in categories plus custom categories. | Critical mismatch. Budget rows are still picker-driven, not activity-driven. Empty built-in categories can appear. |
| Fresh user state | Before first import, no stale or empty imported categories. | Local storage is removed, but built-in category list can still appear because budgets use picker categories. | Supabase stale local state is gone, but empty static categories are still shown. |
| After import | AI-created transaction categories should appear in Budget page automatically. | Custom Supabase categories appear in picker/read model if created; budgets derive rows from picker categories. | Partially works only for created categories, but AI cannot currently create non-built-in categories and Budget does not filter by transaction activity. |
| Existing budgets | Existing budget rows can remain for continuity. | Budgets are keyed by `name` text, not `category_id`. | Name-keyed budgets are fragile if categories are renamed or merged. Consider category ID migration. |
| Metrics | Budget totals should match real categorized transaction spend. | `BudgetUiController.spentByDisplayCategoryForScopeInRange(...)` computes spend by display category from transactions. | Spend side is close. Category list generation is the bigger gap. |

### Data Model

| Area | New docs require | Current schema/code | Gap |
|------|------------------|---------------------|-----|
| Core tables | Accounts, transactions, categories, budgets, profiles in Supabase with RLS. | Migrations exist for all five tables with RLS. | Core foundation is good. |
| Transactions | `transactions.category_id` is authoritative. `import_id` groups CSV uploads. | Schema and services support both. Fetch pagination exists. | Good. Potential missing fields for future: `merchant_normalized`, `category_source`, `ai_model`, `categorized_at`, `ai_error`. |
| Categories | AI can create categories; duplicates should be avoided case-insensitively. | `categories` has `name`, `type`, `user_id`, no unique lower-name constraint. `CategoryService.createCategory(...)` inserts directly. | Duplicate category risk. Need normalized/category uniqueness strategy. |
| Budgets | Budget categories should align with transaction categories. | `budgets.name` stores display label; no `category_id`. | Category rename/merge will drift budget data. Consider `budgets.category_id` or a stable normalized key. |
| Merchant learning | Supabase table for learned mappings. | No migration/table. Only `merchant_normalization.dart` and empty `merchantCategoryMemory` maps remain. | Major missing feature. |
| Edge functions | `categorize-transactions` should be authenticated and deployed. | Function exists. `supabase/config.toml` only has `[functions.call-openai] verify_jwt = true`. | Add explicit `categorize-transactions` config and deployment/type-check docs are already updated. |

### Merchant Learning

| Area | New docs require | Current code/docs | Gap |
|------|------------------|-------------------|-----|
| Manual correction behavior | Changing one transaction category updates all matching past transactions. | `CategoryWorkflowService.setCategoryOverride(...)` updates only the selected transaction. | Critical missing behavior. |
| Future import behavior | Learned merchant mapping is applied before or instead of AI for future imports. | `CsvImportService` sends every inserted row to AI. No merchant memory lookup. | Missing. |
| Similar merchant names | Dunkin, DD, Dunkin Donuts, etc. should group together. | `merchant_normalization.dart` normalizes banking noise, punctuation, and long numbers. No alias/similarity service. | Normalization helper is a seed, not a product-ready matcher. |
| Persistence | Learned mapping must be Supabase-backed. | No Supabase table/service. Old local merchant storage was removed. | Need schema, service, workflow integration, tests. |
| Conflict behavior | Manual user correction should override AI. | Saved `transactions.category_id` wins in category resolution. | Per-row override works; merchant-level override does not. Need conflict/update rules. |

### Architecture

| Area | New docs require | Current code/docs | Gap |
|------|------------------|-------------------|-----|
| Simple import service | One high-level import service owns parse/save/AI/apply. | `CsvImportService` owns most of the workflow. `TransactionWorkflowService` wraps it and translates progress into app status. | Good direction. Naming and boundaries still carry old AI-centric terms. |
| UI coordination | UI should not coordinate low-level AI/import steps. | UI calls controller `loadFromCsv(...)`; controller delegates to workflow/service. | Acceptable. Later expose file-based import method directly instead of text/temp file path. |
| Removed review queue | No user-facing review screens. | Transaction review screens are removed from `lib/features/transactions/presentation`; dashboard no longer shows attention card. | Good. Some historical docs still mention old screens as history, but active docs point to new contract. |
| Supabase-only data | No SharedPreferences app-data path. | No active `lib/core/storage` app-data files in current file map. | Good. Keep audits in CI/checklist. |
| Tests | Contract needs coverage for CSV, AI success/failure, budgets, merchant learning. | Only `test/app_routing_test.dart` and `test/csv_parser_test.dart` remain. Old AI data-service test was removed. | Major test coverage gap. |

## 3. Specific Action Plan

### Priority 0 - Stabilize The Current Import Pipeline

Do this first because all later product behavior depends on reliable imports.

Files to change:

- `supabase/config.toml`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/transactions/data/openai_proxy_client.dart`
- `lib/features/transactions/data/transaction_service.dart`
- `lib/features/transactions/application/transaction_workflow_service.dart`
- `lib/features/transactions/application/ai_categorization_service.dart`
- `lib/features/shell/presentation/import_ai_progress_banner.dart`
- `lib/features/transactions/presentation/upload_screen.dart`
- `lib/features/accounts/presentation/account_selection_screen.dart`
- `lib/features/accounts/presentation/account_detail_screen.dart`

New files to create:

- `test/csv_import_service_test.dart`
- `test/transaction_service_pagination_test.dart` or service fake tests around pagination behavior
- `supabase/functions/categorize-transactions/index_test.ts` if Edge Function testing is added

Required work:

1. Add explicit `[functions.categorize-transactions] verify_jwt = true`.
2. Rename AI-centric progress classes/controllers to import-job names:
   `AiCategorizationApplicationService` -> `CsvImportProgressService` or
   `ImportJobStatusService`.
3. Make upload progress visible as early as possible after file selection,
   including the pre-account-selection path.
4. Add tests that the provided large CSV parses all rows and that imports over
   1000 rows do not drop older months.
5. Add tests for AI success, AI failure -> `Unknown`, missing suggestions ->
   `Unknown`, and bulk category updates.
6. Make final import errors persistent enough to inspect, not only a short
   snackbar.

Files to remove or deprecate:

- `lib/core/models/ai_category.dart` if it remains empty.
- `lib/features/transactions/application/ai_categorization_service.dart` name
  should be deprecated or renamed if it only owns import progress state.

### Priority 1 - Allow AI To Create Real Categories

This is the biggest functional mismatch with the new contract.

Files to change:

- `supabase/functions/categorize-transactions/index.ts`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/categories/data/category_service.dart`
- `lib/features/categories/application/category_read_model.dart`
- `lib/features/transactions/domain/spend_categories.dart`
- `supabase/migrations/*`

New files to create:

- `supabase/migrations/000008_add_category_normalized_name.sql` or equivalent
- `test/category_creation_normalization_test.dart`

Required work:

1. Change the Edge Function contract so AI can return new category names, not
   only entries from `kSelectableSpendCategories`.
2. Add category normalization and case-insensitive duplicate prevention.
3. Decide whether categories should have a `normalized_name` column or use a
   functional unique index on `lower(trim(name))`.
4. Update Flutter parsing so unknown-but-valid AI category names are accepted
   and created in Supabase.
5. Keep `Unknown` as explicit fallback for invalid or empty suggestions.
6. Add tests for "AI returned new category -> category row created ->
   transactions assigned -> picker includes it".

Files to remove or deprecate:

- Any code that assumes AI category outputs must be limited to
  `kSelectableSpendCategories`.

### Priority 2 - Make Budgets Activity-Driven

This must happen after category assignment is reliable.

Files to change:

- `lib/features/budgets/presentation/budgets_viewmodel.dart`
- `lib/features/budgets/presentation/budgets_screen.dart`
- `lib/features/budgets/presentation/budget_category_list.dart`
- `lib/app/ui_dependencies.dart`
- `lib/features/budgets/data/budget_service.dart`
- `lib/features/dashboard/application/dashboard_service.dart`
- `lib/features/transactions/domain/transaction_resolution.dart`

New files to create:

- `lib/features/budgets/domain/budget_category_source.dart`
- `test/budgets_activity_categories_test.dart`

Required work:

1. Replace `BudgetsViewModel.sortedRows()` source from picker categories to
   activity-driven categories for the selected period/scope.
2. Include categories with real spend/income activity in the selected period.
3. Include existing budget rows for continuity even if current spend is zero,
   but visually separate or document that behavior.
4. Hide categories that have no transactions and no existing budget row.
5. Decide whether Budget rows should migrate from `name` to `category_id`.
6. Add tests for fresh user, after import, empty category filtering, and
   renamed/category-created behavior.

Possible migration:

- `supabase/migrations/000009_add_budget_category_id.sql`
  - Add nullable `category_id`.
  - Add composite FK `(user_id, category_id)` to `categories(user_id, id)`.
  - Backfill by matching `budgets.name` to category names where possible.

### Priority 3 - Build Supabase Merchant Learning

This is the core "manual corrections get smarter" product promise.

Files to change:

- `lib/features/transactions/application/category_workflow_service.dart`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/transactions/data/transaction_service.dart`
- `lib/features/transactions/domain/merchant_normalization.dart`
- `lib/features/transactions/domain/spend_categories.dart`
- `lib/app/app_composition.dart`
- `lib/app/ui_dependencies.dart`
- `supabase/migrations/*`

New files to create:

- `supabase/migrations/000010_create_merchant_category_memory.sql`
- `lib/features/transactions/data/merchant_category_memory_service.dart`
- `lib/features/transactions/domain/merchant_alias_matcher.dart`
- `test/merchant_category_memory_service_test.dart`
- `test/manual_category_learning_test.dart`
- `test/csv_import_merchant_learning_test.dart`

Required work:

1. Add a Supabase table for merchant/category mappings.
2. Add a service that can fetch, upsert, and watch learned merchant mappings.
3. On manual category correction:
   - normalize the merchant
   - upsert the mapping
   - find matching past transactions
   - bulk update their `category_id`
   - refresh dashboard and budgets
4. On CSV import:
   - apply learned merchant categories first
   - send only unresolved rows to AI or include learned category as strong
     context
   - persist categories for every inserted row
5. Add alias support for merchant families like `Dunkin`, `DD`, and
   `Dunkin Donuts`.
6. Define conflict rules:
   - manual correction beats AI
   - newer manual correction can replace older learned mapping
   - user can undo/override a learned mapping later

Files to remove or deprecate:

- Empty placeholder `merchantCategoryMemory => const {}` getters after the real
  service exists.
- Old comments that describe merchant memory as "future" once implemented.

### Priority 4 - Operationalize AI At Scale

Do this before larger beta testing or real-user uploads.

Files to change:

- `supabase/functions/categorize-transactions/index.ts`
- `lib/features/transactions/data/openai_proxy_client.dart`
- `lib/features/transactions/data/csv_import_service.dart`
- `docs/supabase_auth_openai_setup.md`

New files to create:

- `docs/ai_categorization_operations.md`
- Edge Function test fixtures under `supabase/functions/categorize-transactions/`

Required work:

1. Add per-chunk retry with bounded backoff in the Edge Function.
2. Return partial chunk errors if some chunks fail, so Flutter can mark only
   unresolved rows `Unknown` instead of the entire import.
3. Add request size limits and friendly error messages for extremely large
   uploads.
4. Track model, duration, chunk count, and categorized count in logs or a
   future import history table.
5. Consider a background job model if one Edge Function request cannot reliably
   finish within platform timeouts.

## 4. Risk Areas

### AI Performance And Timeouts

Current categorization uses one Flutter request to an Edge Function, then the
Edge Function chunks into 400-row OpenAI calls with concurrency 4. This is much
better than one request per transaction, but it still has risks:

- A single slow OpenAI chunk can block the whole import.
- Any chunk failure currently fails the full Edge Function response.
- Flutter waits up to 5 minutes. Large imports or OpenAI latency can still hit
  that timeout.
- The progress bar cannot show true per-chunk progress while the Edge Function
  is running because Flutter receives one final response.

Recommended mitigation: add chunk retries, partial result handling, and logging
before increasing user scale.

### AI Accuracy

The current prompt forces categories to a small built-in list. That directly
conflicts with the product requirement that AI can create categories. Once this
is opened up, accuracy risks shift:

- AI may create too many near-duplicate categories.
- AI may use inconsistent names across imports.
- Without examples or merchant memory, local merchant categorization will vary.

Recommended mitigation: use a category normalization layer, seeded allowed
categories, explicit category naming rules, and merchant learning before free
category creation is widely enabled.

### Budget Consistency

Budgets are currently display-name keyed and the Budget page is picker-driven.
This creates several risks:

- Empty built-in categories show before there is activity.
- Renamed categories can drift from old budget rows.
- AI-created categories may not line up cleanly with budget rows.
- Category merges or aliases are hard when budgets store only text names.

Recommended mitigation: make Budget category rows activity-driven immediately,
then consider adding `budgets.category_id` for stronger long-term consistency.

### Merchant Learning Correctness

Merchant learning is product-critical but absent. The risk is not just missing
functionality; a naive matcher can also over-apply corrections:

- `DD` may mean Dunkin in one bank description but something else elsewhere.
- Similarity matching can accidentally group unrelated merchants.
- Bulk past updates need clear user expectations and undo strategy.

Recommended mitigation: start with exact normalized merchant keys, add explicit
aliases only after confirmation, and record learned mappings in Supabase with
timestamps and source metadata.

### Global Scale

The app is moving from local workflows to Supabase-backed global scale. Key
risks:

- Large accounts need pagination everywhere, not just transaction fetch.
- Realtime streams over large tables can become expensive.
- Import dedupe loads all account transactions; this may become slow for very
  large accounts.
- Bulk updates by large ID lists can hit request size limits.

Recommended mitigation: add database-level indexes, consider server-side RPC for
dedupe and bulk categorization, and test with 10k+ transaction accounts before
real-world use.

### Documentation Drift

The docs now have a clear source of truth, but older historical docs still
contain old observations by design. Developers should treat
`docs/csv_import_ai_categorization.md` and this audit as current roadmap docs.
Historical reports should not drive new implementation decisions unless they
are explicitly refreshed.

## Recommended Next Sprint

1. Add explicit `categorize-transactions` JWT config and tests around the new
   CSV import service.
2. Change AI output handling so new categories can be created safely.
3. Make Budget categories activity-driven.
4. Add the Supabase merchant learning table and implement manual correction
   backfill.
5. Add Edge Function retry/partial-result handling before large-scale testing.

The biggest product unlock is Priority 1 plus Priority 2: AI-created categories
must become real transaction categories, and Budgets must consume only active
transaction categories. Merchant learning is the next major differentiator once
that foundation is stable.
