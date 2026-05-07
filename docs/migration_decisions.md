# Migration and product decisions

Record **what we chose** so refactors do not re-litigate the same questions. Update when product intent changes.

## Implemented in code (current)

| Topic | Decision |
|-------|----------|
| **Overview dashboard default** | **Global** — all accounts in `buildDashboardSnapshot` with `GlobalDashboardScope`. |
| **Per-account view** | **Account** scope on account detail — same snapshot pipeline, scoped transactions. |
| **CSV import + AI categorization** | Import is automatic: save transactions, categorize all inserted rows through Supabase AI, apply category IDs, and refresh. See [`csv_import_ai_categorization.md`](csv_import_ai_categorization.md). |
| **Month detail** | Driven by **passed `MonthlyBankGroup`** from snapshot list, not a global state month lookup. |
| **Rules** | Removed from active app behavior. Categorization now uses saved category IDs, learned merchant mappings, AI categories, keywords, and CSV labels. |
| **AI categorization** | Flutter calls Supabase Edge Functions through `Supabase.functions.invoke`; the real OpenAI key is stored only as a Supabase secret. |
| **Auth/profile** | Supabase Auth owns sessions. `profiles` rows are keyed by `auth.users(id)`. `ProfileController` owns profile/onboarding route state. |
| **Composition** | `AppState` has been deleted. `AppComposition` wires services, workflows, controllers, and startup. |
| **CSV import batches** | Imported transactions store `import_id`; upload history and batch deletion use `account_id + import_id`. |
| **Financial semantics** | `FinancialRole` + `effectiveFinancialRole` used for spend/income in snapshot (with global context for internal payments). |

## Open / product choices (explicitly not locked here unless stated)

- Whether **Budgets** tab sums should be global vs account (verify [`budgets_screen.dart`](../lib/features/budgets/presentation/budgets_screen.dart) when touching budgets).
- **Append vs replace** on re-import: current CSV import appends non-duplicate
  Supabase transaction rows for the selected account.
- Exact merchant-similarity rules for learning aliases such as `Dunkin`, `DD`,
  and `Dunkin Donuts`.

## When you change behavior

1. Update [`app_logic_contract.md`](app_logic_contract.md) if truth for scope or category order changes.
2. Update this file’s **Implemented** table with a one-line note and date in the commit message.
3. Add or extend tests under `test/` for scope alignment (see existing `dashboard_scope_test.dart`).
