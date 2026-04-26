import '../../../app_state.dart';
import '../../transactions/domain/bank_statement_monthly.dart';
import 'dashboard_snapshot.dart';

/// Central queries for dashboard scope — prefer these over recomputing ad hoc.
///
/// See [docs/app_logic_contract.md](../docs/app_logic_contract.md).

/// Month groups for [scope], newest first — same rows as [DashboardSnapshot.monthlyGroups]
/// when [buildDashboardSnapshot] uses `scopedTransactions: appState.transactionsForDashboardScope(scope)`.
List<MonthlyBankGroup> monthlyGroupsForDashboardScope(
  AppState appState,
  DashboardScope scope,
) {
  final scoped = appState.transactionsForDashboardScope(scope);
  return monthlyBankGroupsNewestFirstForScopedTransactions(
    scoped,
    categoryOverrides: appState.categoryOverrides,
    categoryDisplayRenamesLower: appState.categoryDisplayRenames,
  );
}

/// Single source for the red “needs attention” banner, review screen queue, and any row count.
///
/// Same rows as [uncategorizedBankStatementLines] on
/// [AppState.transactionsForDashboardScope] — banner count must be `.length` only.
List<BankStatementLine> uncategorizedTransactionsForDashboardScope(
  AppState appState,
  DashboardScope scope,
) {
  return uncategorizedBankStatementLines(
    appState.transactionsForDashboardScope(scope),
    categoryOverrides: appState.categoryOverrides,
    categoryDisplayRenamesLower: appState.categoryDisplayRenames,
  );
}

/// Same as [uncategorizedTransactionsForDashboardScope] (…).length — avoids a second definition.
int uncategorizedCountForDashboardScope(
  AppState appState,
  DashboardScope scope,
) =>
    uncategorizedTransactionsForDashboardScope(appState, scope).length;

/// Prefer [uncategorizedTransactionsForDashboardScope].
List<BankStatementLine> uncategorizedBankStatementLinesForDashboardScope(
  AppState appState,
  DashboardScope scope,
) =>
    uncategorizedTransactionsForDashboardScope(appState, scope);

