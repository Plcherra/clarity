# Screen Data Map

For maintainers. Lists primary sources; always confirm in code when refactoring.

Shared helpers: [`dashboard_queries.dart`](../lib/features/dashboard/domain/dashboard_queries.dart)
(`monthlyGroupsForDashboardScope`, diagnostic uncategorized helpers) match
[`buildDashboardSnapshot`](../lib/features/dashboard/domain/dashboard_snapshot.dart)
for the same scope.

| Screen / surface | Scope | Transaction source | Grouping / category behavior |
|------------------|-------|--------------------|----------------------------|
| Overview [`DashboardScreen`](../lib/features/dashboard/presentation/dashboard_screen.dart) | `GlobalDashboardScope` | `DashboardUiController.buildSnapshot` -> `buildDashboardSnapshot` -> all transactions | `DashboardSnapshot.monthlyGroups`; no review queue |
| Account detail [`AccountDetailScreen`](../lib/features/accounts/presentation/account_detail_screen.dart) | `AccountDashboardScope(id)` | `AccountUiController.buildSnapshotForAccount` -> `buildDashboardSnapshot` with that account's rows | `snap.monthlyGroups`; CSV import/delete is account-scoped |
| [`FinancialDashboardView`](../lib/features/dashboard/presentation/financial_dashboard_view.dart) | Passed in `scope` | Parent supplies the snapshot builder for the chosen scope | Month cards use `snap.monthlyGroups` |
| [`MonthDetailScreen`](../lib/features/dashboard/presentation/month_detail_screen.dart) | Same as dashboard that pushed it | Uses the passed `MonthlyBankGroup group`; does not reload by month key from state | Rows = `group.transactions`, refreshed through `DashboardUiController.refreshedLinesForMonth`; category picker uses transaction controller |
| [`HomeShell`](../lib/features/shell/presentation/home_shell.dart) tabs | N/A | Receives `AppUiDependencies` and passes scoped controllers to child features | Dashboard / Accounts / Budgets each own child UI; import progress listens to import status |
| CSV import | Selected account | `CsvImportService.importAndCategorize(...)` | Parse, save, categorize, apply categories, refresh; see [`csv_import_ai_categorization.md`](csv_import_ai_categorization.md) |

Residual gotcha: month rows shown in dashboard UI should come from
`DashboardSnapshot.monthlyGroups` for the current `DashboardScope`, not from a
separate global mutable state field.
