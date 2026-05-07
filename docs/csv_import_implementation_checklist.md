# CSV Import Implementation Checklist

Date: 2026-05-06

This is the executable master plan for the CSV import, AI categorization,
Budget category visibility, and merchant learning work.

Use these documents as inputs:

- [`csv_import_ai_categorization.md`](csv_import_ai_categorization.md) is the
  product and engineering contract.
- [`project_alignment_audit.md`](project_alignment_audit.md) is the current
  gap analysis.
- [`app_logic_contract.md`](app_logic_contract.md) is the supporting data-flow
  contract.

This checklist is the implementation plan. If code behavior diverges from the
product contract, update the code or update the contract in the same change.

## Non-Negotiable Product Outcomes

- [ ] CSV upload requires near-zero user effort.
- [ ] Upload progress starts immediately after file selection.
- [ ] AI categorizes all newly inserted transactions automatically.
- [ ] There is no mandatory "transactions need attention" review queue.
- [ ] AI can create useful per-user categories on first upload.
- [ ] Missing or failed AI categorization assigns `Unknown`, not null.
- [ ] Budget categories are driven by real transaction activity.
- [ ] Empty categories do not appear by default in the Budget page.
- [ ] Manual category correction teaches merchant mappings in Supabase.
- [ ] Learned merchant mappings apply to matching past and future transactions.
- [ ] No app-data persistence returns to `SharedPreferences`.

## Phase 0: Stabilization

Priority: Critical  
Estimated effort: Medium  
Goal: Make the current CSV import pipeline reliable, consistent, and testable
before adding new features.

### Tasks

- [x] Add explicit JWT verification config for `categorize-transactions` in
  `supabase/config.toml`.
- [x] Fully rename AI-centric classes, files, and variables to import-job
  terminology. Remove active `AiCategorization`, `ImportAi`, and similar names.
- [x] Make `CsvImportService.importAndCategorize(...)` the single clear owner of
  the import workflow: parsing, save, categorize, apply categories, and refresh.
- [x] Ensure progress UI starts immediately after CSV file selection, including
  before account selection.
- [ ] Guarantee every newly inserted transaction receives a non-null
  `category_id`, either from AI or fallback to the `Unknown` category.
- [x] Make import failure states persistent and informative.
- [x] Add solid test coverage for large CSVs and failure scenarios.

### Key Files To Modify

- `supabase/config.toml`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/transactions/application/transaction_workflow_service.dart`
- `lib/features/transactions/application/import_job_status_service.dart`
- `lib/features/shell/presentation/import_job_progress_banner.dart`

### New Files To Create

- `test/csv_import_service_test.dart`

### Files To Remove Or Deprecate

- Rename `lib/features/transactions/application/ai_categorization_service.dart`
  to `lib/features/transactions/application/import_job_status_service.dart`.
- Remove or deprecate any remaining `ai_category.dart` or old AI-specific
  models.

### Tests That Must Pass

- [x] `flutter analyze`
- [x] `flutter test`
- [x] `git diff --check`
- [x] Large CSV with 1500+ rows parses and inserts all rows correctly.
- [x] Duplicate rows are skipped reliably when the account already has 1000+
  existing transactions.
- [x] AI success applies category IDs to inserted transactions.
- [x] AI failure assigns `Unknown` to all inserted rows.
- [x] Missing AI suggestions assign `Unknown`.
- [x] Invalid AI suggestions assign `Unknown`.
- [x] Category assignment uses grouped bulk updates rather than one update per
  transaction.

### Acceptance Criteria

- [ ] A fresh user can upload a CSV and see one continuous import progress UI.
- [ ] All inserted rows end with a non-null `category_id`.
- [x] No disconnected "AI job" UI remains.
- [x] Import errors are persistent and informative.
- [x] The app never shows a review queue after successful import.
- [x] Dashboard, account detail, transaction lists, and budgets refresh after
  import completion.

### Risks If Skipped

- Future category and budget work will be built on an unreliable import path.
- Large imports may keep losing older rows or failing without useful feedback.
- Users will continue to experience upload and AI categorization as disconnected
  operations.

## Phase 1: AI Can Create Categories

Priority: Critical  
Estimated effort: Large  
Goal: Let AI create real Supabase categories instead of forcing every response
into a static built-in list.

### Tasks

- [x] Update `categorize-transactions` so AI can return new category names.
- [x] Keep `Unknown` as the only fallback for missing, empty, invalid, or
  unsafe suggestions.
- [x] Add category normalization before creating Supabase category rows.
- [x] Prevent duplicate categories that differ only by case, punctuation, or
  spacing.
- [x] Decide whether category uniqueness uses a `normalized_name` column or a
  database functional unique index.
- [x] Update Flutter category application so valid AI-created category names are
  created or reused.
- [x] Make created categories immediately available in selectors and downstream
  budget logic.
- [x] Add prompt rules that reduce category sprawl and keep names user-friendly.

### Key Files To Modify

- `supabase/functions/categorize-transactions/index.ts`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/categories/data/category_service.dart`
- `lib/features/categories/application/category_read_model.dart`
- `lib/features/transactions/domain/spend_categories.dart`
- `lib/features/transactions/application/category_workflow_service.dart`

### New Files To Create

- `supabase/migrations/000008_add_category_normalized_name.sql` or equivalent
- `test/category_creation_normalization_test.dart`
- Edge Function fixture tests for AI-created category responses

### Files To Remove Or Deprecate

- Deprecate assumptions that AI output must be limited to
  `kSelectableSpendCategories`.
- Keep built-in categories as seed suggestions, not as the only allowed output.

### Tests That Must Pass

- [x] AI-created category name inserts one user-owned Supabase category row.
- [x] Same category with different casing reuses the existing row.
- [x] AI-created category is assigned to inserted transactions.
- [x] AI-created category appears in category selectors after import.
- [x] Invalid category response falls back to `Unknown`.
- [x] Category creation is scoped to the authenticated user.

### Acceptance Criteria

- [x] A first-time user can upload a CSV and end with meaningful categories that
  did not exist before upload.
- [x] Category creation is deterministic enough to avoid obvious duplicates.
- [x] Built-in categories still work as normal category choices.

### Risks If Skipped

- AI categorization remains constrained to a generic static list.
- Budget pages cannot reflect the user's actual financial life with useful
  category names.
- Manual correction and learning will be less valuable because categories are
  too coarse.

## Phase 2: Activity-Driven Budget Page

Priority: High  
Estimated effort: Large  
Goal: Make the Budget page show only categories backed by real transaction
activity, plus existing budget rows needed for continuity.

### Tasks

- [ ] Replace picker-driven Budget row generation with activity-driven category
  generation.
- [ ] Include categories that have spend or income activity in the selected
  period and scope.
- [ ] Include existing budget rows even when current activity is zero, so saved
  budgets do not disappear unexpectedly.
- [ ] Hide empty built-in categories by default.
- [ ] Ensure AI-created categories appear automatically when they have matching
  transactions.
- [ ] Decide whether budgets should migrate from text `name` keys to
  `category_id`.
- [ ] Keep spend calculations aligned with `ResolvedTransaction` and dashboard
  scope rules.

### Key Files To Modify

- `lib/features/budgets/presentation/budgets_viewmodel.dart`
- `lib/features/budgets/presentation/budgets_screen.dart`
- `lib/features/budgets/presentation/budget_category_list.dart`
- `lib/features/budgets/data/budget_service.dart`
- `lib/app/ui_dependencies.dart`
- `lib/features/dashboard/application/dashboard_service.dart`
- `lib/features/transactions/domain/transaction_resolution.dart`

### New Files To Create

- `lib/features/budgets/domain/budget_category_source.dart`
- `test/budgets_activity_categories_test.dart`
- Optional migration:
  `supabase/migrations/000009_add_budget_category_id.sql`

### Files To Remove Or Deprecate

- Deprecate budget row generation from the full category picker list.
- Deprecate Budget behavior that shows every built-in category before the user
  has transaction activity.

### Tests That Must Pass

- [ ] Fresh user with no transactions sees no empty budget category list.
- [ ] After import, categories with transactions appear in Budgets.
- [ ] Category with no transactions and no saved budget row is hidden.
- [ ] Saved budget row remains visible for continuity.
- [ ] Renamed or AI-created categories do not break budget display.
- [ ] Budget spend totals match resolved transaction spend for the selected
  scope and period.

### Acceptance Criteria

- [ ] Budget page reflects real imported financial activity.
- [ ] AI-created categories automatically become budgetable categories.
- [ ] No stale local or empty static categories appear by default.

### Risks If Skipped

- Budgets will continue to look polished but disconnected from actual user data.
- First-upload categories will not naturally flow into the Budget page.
- Users may think imported data is stale or contaminated by old categories.

## Phase 3: Merchant Learning System

Priority: High  
Estimated effort: Large  
Goal: Manual category corrections teach Supabase-backed merchant mappings that
update matching past transactions and future imports.

### Tasks

- [ ] Create a Supabase table for merchant category memory.
- [ ] Build a data service for fetching, upserting, and applying learned
  merchant mappings.
- [ ] Start matching with exact normalized merchant keys.
- [ ] Add explicit alias support for merchant families such as `Dunkin`, `DD`,
  and `Dunkin Donuts`.
- [ ] On manual category correction, upsert the learned mapping.
- [ ] Bulk update matching past transactions after a manual correction.
- [ ] Apply learned merchant mappings to new CSV imports before AI.
- [ ] Prefer learned merchant category over a fresh AI guess.
- [ ] Define conflict behavior when a user changes an already learned merchant.
- [ ] Add an undo or manage-rules path only after the core learning behavior is
  stable.

### Key Files To Modify

- `lib/features/transactions/application/category_workflow_service.dart`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/transactions/data/transaction_service.dart`
- `lib/features/transactions/domain/merchant_normalization.dart`
- `lib/app/app_composition.dart`
- `lib/app/ui_dependencies.dart`
- `supabase/migrations/*`

### New Files To Create

- `supabase/migrations/000010_create_merchant_category_memory.sql`
- `lib/features/transactions/data/merchant_category_memory_service.dart`
- `lib/features/transactions/domain/merchant_alias_matcher.dart`
- `test/merchant_category_memory_service_test.dart`
- `test/manual_category_learning_test.dart`
- `test/csv_import_merchant_learning_test.dart`

### Files To Remove Or Deprecate

- Remove placeholder `merchantCategoryMemory => const {}` paths once the real
  service exists.
- Remove comments that describe merchant memory as future-only after it ships.

### Tests That Must Pass

- [ ] Correcting one `Dunkin` transaction stores a merchant mapping.
- [ ] Matching past `Dunkin`, `DD`, and `Dunkin Donuts` transactions update to
  the corrected category.
- [ ] Future import applies the learned category before AI.
- [ ] Learned mappings are scoped to the authenticated user.
- [ ] Manual correction wins over AI suggestion.
- [ ] Similarity matching does not over-apply to unrelated merchants.

### Acceptance Criteria

- [ ] User corrections improve both historical data and future imports.
- [ ] Merchant learning is fully Supabase-backed.
- [ ] The app can explain or inspect learned behavior during development.

### Risks If Skipped

- The product remains "AI categorization only" and does not get smarter from
  user corrections.
- Users will repeatedly fix the same merchants across imports.
- Accuracy targets are harder to reach without user-specific learning.

## Phase 4: Polish, Performance And Scale

Priority: Medium  
Estimated effort: Medium to Large  
Goal: Make the import and categorization system production-ready for larger
files, global users, slow AI responses, and observability.

### Tasks

- [ ] Add per-chunk retry with bounded backoff inside the Edge Function.
- [ ] Return partial chunk results so one failed chunk does not fail the whole
  import.
- [ ] Add request size limits and user-friendly oversized-file errors.
- [ ] Track model, duration, chunk count, inserted count, categorized count,
  fallback count, and AI error details.
- [ ] Consider an import history table for durable progress and support
  debugging.
- [ ] Consider a server-side job model if Edge Function request timeouts remain
  a practical limit.
- [ ] Build an evaluation CSV set for AI accuracy.
- [ ] Improve prompt strategy with examples, naming rules, and confidence
  scores.
- [ ] Add dashboard or logs for import failure rates and category fallback
  rates.

### Key Files To Modify

- `supabase/functions/categorize-transactions/index.ts`
- `lib/features/transactions/data/openai_proxy_client.dart`
- `lib/features/transactions/data/csv_import_service.dart`
- `lib/features/shell/presentation/import_ai_progress_banner.dart`
- `docs/supabase_auth_openai_setup.md`

### New Files To Create

- `docs/ai_categorization_operations.md`
- Edge Function test fixtures under
  `supabase/functions/categorize-transactions/`
- Optional migration:
  `supabase/migrations/000011_create_csv_import_jobs.sql`
- Optional test fixtures under `test/fixtures/ai_eval/`

### Files To Remove Or Deprecate

- Deprecate any import progress path that cannot survive a slow operation or
  communicate partial failure.
- Deprecate hidden debug-only status text once durable import history exists.

### Tests That Must Pass

- [ ] Edge Function splits large imports into predictable chunks.
- [ ] One chunk failure returns partial results or a clear fallback path.
- [ ] Retry succeeds after transient OpenAI failure.
- [ ] Oversized import returns a friendly error before expensive work starts.
- [ ] 1000-transaction import completes within the target operating range.
- [ ] Accuracy evaluation tracks first-pass categorization quality.

### Acceptance Criteria

- [ ] 1000 transactions categorize in roughly 1-3 minutes under normal network
  and OpenAI latency.
- [ ] A slow or failed AI chunk does not leave the user confused about what was
  saved.
- [ ] Developers can diagnose import failures from logs or import history.

### Risks If Skipped

- The app may work in demos but fail unpredictably on real bank exports.
- OpenAI or Edge Function latency can still create confusing timeouts.
- Accuracy work will be anecdotal instead of measurable.

## Global Definition Of Done

- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] `git diff --check` passes.
- [ ] No user-facing review queue references remain.
- [ ] No app-data `SharedPreferences` path returns.
- [ ] Supabase RLS is enabled for new tables.
- [ ] New Edge Functions have explicit JWT verification.
- [ ] Large CSV imports do not lose rows due to pagination.
- [ ] Every inserted transaction ends import with a category.
- [ ] AI-created categories flow into selectors and Budgets.
- [ ] Budget page is activity-driven.
- [ ] Manual corrections teach merchant mappings and backfill matching rows.

## Implementation Order

1. Phase 0: Stabilize current import reliability and tests.
2. Phase 1: Let AI create real categories safely.
3. Phase 2: Make Budgets activity-driven from transaction categories.
4. Phase 3: Add Supabase merchant learning and manual correction backfill.
5. Phase 4: Add operational hardening, performance, and accuracy measurement.

Do not start Phase 3 before Phase 1 and Phase 2 are stable. Merchant learning
depends on reliable categories and on the Budget page reflecting real
transaction category activity.
