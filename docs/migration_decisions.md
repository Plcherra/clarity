# Migration and product decisions

Record **what we chose** so refactors do not re-litigate the same questions. Update when product intent changes.

## Implemented in code (current)

| Topic | Decision |
|-------|----------|
| **Overview dashboard default** | **Global** — all accounts in `buildDashboardSnapshot` with `GlobalDashboardScope`. |
| **Per-account view** | **Account** scope on account detail — same snapshot pipeline, scoped transactions. |
| **Banner “needs attention” vs Review** | Same definition: `uncategorizedTransactionCount` / `uncategorizedBankStatementLines` on **`transactionsForDashboardScope(scope)`** — was fixed so Overview and `TransactionReviewScreen` share scope. |
| **Month detail** | Driven by **passed `MonthlyBankGroup`** from snapshot list, not `AppState.monthlyGroups` lookup for Overview. |
| **Rules** | Removed from active app behavior. The one-time migration deletes old persisted rules data; categorization now uses saved category IDs, manual overrides, merchant memory, keywords, and CSV labels. |
| **AI categorization** | Flutter calls the Supabase `call-openai` Edge Function through `Supabase.functions.invoke`; the real OpenAI key is stored only as a Supabase secret. |
| **Financial semantics** | `FinancialRole` + `effectiveFinancialRole` used for spend/income in snapshot (with global context for internal payments). |

## Open / product choices (explicitly not locked here unless stated)

- Whether **Budgets** tab sums should be global vs account (verify [`budgets_screen.dart`](../lib/features/budgets/presentation/budgets_screen.dart) when touching budgets).
- **Append vs replace** on re-import: follow `AppState` / CSV import implementation in each path.

## When you change behavior

1. Update [`app_logic_contract.md`](app_logic_contract.md) if truth for scope or category order changes.
2. Update this file’s **Implemented** table with a one-line note and date in the commit message.
3. Add or extend tests under `test/` for scope alignment (see existing `dashboard_scope_test.dart`).
