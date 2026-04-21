# Migration and product decisions

Record **what we chose** so refactors do not re-litigate the same questions. Update when product intent changes.

## Implemented in code (current)

| Topic | Decision |
|-------|----------|
| **Overview dashboard default** | **Global** — all accounts in `buildDashboardSnapshot` with `GlobalDashboardScope`. |
| **Per-account view** | **Account** scope on account detail — same snapshot pipeline, scoped transactions. |
| **Banner “needs attention” vs Review** | Same definition: `uncategorizedTransactionCount` / `uncategorizedBankStatementLines` on **`transactionsForDashboardScope(scope)`** — was fixed so Overview and `TransactionReviewScreen` share scope. |
| **Month detail** | Driven by **passed `MonthlyBankGroup`** from snapshot list, not `AppState.monthlyGroups` lookup for Overview. |
| **Rules** | **Persisted globally** (`category_rules_storage`); **not** cleared on normal import; integrated in `spendGroupLabel` **after** overrides, **before** CSV/heuristics in the stack described in [`app_logic_contract.md`](app_logic_contract.md). |
| **Rules UI** | Not linked from the main dashboard overflow (reduces “split brain” with AI). Rules engine still applies via `spendGroupLabel`. `RulesManagementScreen` remains in codebase for a future entry point or deep link. **Debug:** one line under Overview title compares `reviewQueue` vs `snap.uncategorizedCount` in debug builds only. |
| **AI categorization** | Optional path when `OPENAI_API_KEY` present (see [`constants.dart`](../lib/constants.dart)); flows from account creation / CSV import entry points; not a substitute for the manual review list unless product expands it. |
| **Financial semantics** | `FinancialRole` + `effectiveFinancialRole` used for spend/income in snapshot (with global context for internal payments). |

## Open / product choices (explicitly not locked here unless stated)

- Whether **Budgets** tab sums should be global vs account (verify [`budgets_screen.dart`](../lib/screens/budgets_screen.dart) when touching budgets).
- Whether to **hide** Rules from primary UI long-term (engine stays even if nav changes).
- **Append vs replace** on re-import: follow `AppState` / CSV import implementation in each path.

## When you change behavior

1. Update [`app_logic_contract.md`](app_logic_contract.md) if truth for scope or category order changes.
2. Update this file’s **Implemented** table with a one-line note and date in the commit message.
3. Add or extend tests under `test/` for scope alignment (see existing `dashboard_scope_test.dart`).
