# Screen → data map

For maintainers. Lists **primary** sources; always confirm in code when refactoring.

Shared helpers: [`dashboard_queries.dart`](../lib/dashboard_queries.dart) (`monthlyGroupsForDashboardScope`, uncategorized helpers) — same results as [`buildDashboardSnapshot`](../lib/dashboard_snapshot.dart) for matching scope.

| Screen / surface | Scope | Transaction source | Grouping / uncategorized | Category / display |
|------------------|-------|--------------------|---------------------------|---------------------|
| Overview [`DashboardScreen`](../lib/screens/dashboard_screen.dart) | `GlobalDashboardScope` | `buildDashboardSnapshot` → `scopedTransactions` = `allTransactions` | `DashboardSnapshot.monthlyGroups`; **banner + review:** [`uncategorizedTransactionsForDashboardScope`](../lib/dashboard_queries.dart) (not `snap.uncategorizedCount` for the red card) | Snapshot uses `spendGroupLabel` + `spendGroupLabelForDisplay` + `effectiveFinancialRole` |
| Account detail [`AccountDetailScreen`](../lib/screens/account_detail_screen.dart) | `AccountDashboardScope(id)` | Same snapshot builder, scoped rows for that account | `snap.monthlyGroups` | Same |
| [`FinancialDashboardView`](../lib/screens/financial_dashboard_view.dart) | Passed in `scope` | Parent passes `scopedTransactions` into `buildDashboardSnapshot` | Month cards: `snap.monthlyGroups`; **attention count:** [`uncategorizedTransactionsForDashboardScope`](../lib/dashboard_queries.dart) `.length` (same list as [`TransactionReviewScreen`](../lib/screens/transaction_review_screen.dart)) | Rules screen not linked from dashboard (engine unchanged). Debug: one-line `reviewQueue` vs `snapUncat` in debug builds |
| [`TransactionReviewScreen`](../lib/screens/transaction_review_screen.dart) | **Must equal** parent `scope` | `transactionsForDashboardScope(scope)` | Queue: `uncategorizedBankStatementLines(...)` | Same maps as `AppState` |
| [`MonthDetailScreen`](../lib/screens/month_detail_screen.dart) | Same as dashboard that pushed it | **Does not** load by month key from state; uses **`MonthlyBankGroup group`** arg | Rows = `group.transactions` | Pickers use `appState` |
| [`UncategorizedTransactionsScreen`](../lib/screens/uncategorized_transactions_screen.dart) | Global (static helper) | `uncategorizedLines` → `GlobalDashboardScope` + `uncategorizedBankStatementLines` | Full list global overview | — |
| [`RulesManagementScreen`](../lib/screens/rules_management_screen.dart) | N/A | Reads `AppState.categoryRules` (persisted) | — | Edits rules; `spendGroupLabel` applies rules after overrides, before CSV/heuristics (see contract) |
| [`AiCategorizationFlowScreen`](../lib/screens/ai_category_review_screen.dart) | Account/import batch | Rows from import + uncategorized helpers for that account | — | AI suggests; user accept → persisted category fields |
| [`HomeShell`](../lib/screens/home_shell.dart) tabs | — | Dashboard / Accounts / Budgets each own child | — | — |

**Residual gotcha:** `AppState.monthlyGroups` is **active-account statement groups** only. It is **not** the list behind global Overview month cards. Use **`DashboardSnapshot.monthlyGroups`** for UI tied to `FinancialDashboardView` / `buildDashboardSnapshot`.
