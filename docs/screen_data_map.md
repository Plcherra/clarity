# Screen Data Map

For maintainers. Lists primary sources; always confirm in code when refactoring.

Shared helpers: [`dashboard_queries.dart`](../lib/features/dashboard/domain/dashboard_queries.dart)
(`monthlyGroupsForDashboardScope`, uncategorized helpers) match
[`buildDashboardSnapshot`](../lib/features/dashboard/domain/dashboard_snapshot.dart)
for the same scope.

| Screen / surface | Scope | Transaction source | Grouping / uncategorized | Category / display |
|------------------|-------|--------------------|---------------------------|---------------------|
| Overview [`DashboardScreen`](../lib/features/dashboard/presentation/dashboard_screen.dart) | `GlobalDashboardScope` | `DashboardUiController.buildSnapshot` -> `buildDashboardSnapshot` -> all transactions | `DashboardSnapshot.monthlyGroups`; banner + review use `uncategorizedTransactionsForDashboardScope` | Snapshot uses transaction resolution, display renames, and financial role |
| Account detail [`AccountDetailScreen`](../lib/features/accounts/presentation/account_detail_screen.dart) | `AccountDashboardScope(id)` | `AccountUiController.buildSnapshotForAccount` -> `buildDashboardSnapshot` with that account's rows | `snap.monthlyGroups` | Same |
| [`FinancialDashboardView`](../lib/features/dashboard/presentation/financial_dashboard_view.dart) | Passed in `scope` | Parent supplies the snapshot builder for the chosen scope | Month cards use `snap.monthlyGroups`; attention count uses the same uncategorized helper as review | Debug builds show `reviewQueue` vs `snapUncat` for drift checks |
| [`TransactionReviewScreen`](../lib/features/transactions/presentation/transaction_review_screen.dart) | Must equal parent dashboard scope | `TransactionUiController.uncategorizedQueue(scope)` | `uncategorizedBankStatementLines(...)` | Uses category/display maps exposed by `TransactionUiController` |
| [`MonthDetailScreen`](../lib/features/dashboard/presentation/month_detail_screen.dart) | Same as dashboard that pushed it | Uses the passed `MonthlyBankGroup group`; does not reload by month key from state | Rows = `group.transactions`, refreshed through `DashboardUiController.refreshedLinesForMonth` | Category picker uses `TransactionUiController` |
| [`UncategorizedTransactionsScreen`](../lib/features/transactions/presentation/uncategorized_transactions_screen.dart) | Caller-provided transaction controller/scope | Controller uncategorized helpers | Full uncategorized list for the selected scope | Category picker uses `TransactionUiController` |
| [`AiCategorizationFlowScreen`](../lib/features/transactions/presentation/ai_category_review_screen.dart) | Account/import flow | Import uncategorized helpers for that account | AI suggestions are pending until saved | Temporarily limited until category assignments are fully Supabase-backed |
| [`HomeShell`](../lib/features/shell/presentation/home_shell.dart) tabs | N/A | Receives `AppUiDependencies` and passes scoped controllers to child features | Dashboard / Accounts / Budgets each own child UI | Import AI banner listens to `ImportAiStatusController` |

Residual gotcha: month rows shown in dashboard UI should come from
`DashboardSnapshot.monthlyGroups` for the current `DashboardScope`, not from a
separate global mutable state field.
