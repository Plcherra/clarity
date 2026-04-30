import '../../../core/models/models.dart';
import '../../transactions/domain/bank_statement_monthly.dart';
import 'dashboard_snapshot.dart';

/// Central queries for dashboard scope — prefer these over recomputing ad hoc.
///
/// See [docs/app_logic_contract.md](../docs/app_logic_contract.md).

/// Month groups for [scope], newest first — same rows as [DashboardSnapshot.monthlyGroups]
/// when [buildDashboardSnapshot] uses the same [scopedTransactions].
List<MonthlyBankGroup> monthlyGroupsForDashboardScope(
  DashboardScope scope, {
  required List<Transaction> scopedTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
}) {
  return monthlyBankGroupsNewestFirstForScopedTransactions(
    scopedTransactions,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
  );
}

/// Single source for the red “needs attention” banner, review screen queue, and any row count.
///
/// Same rows as [uncategorizedBankStatementLines] on
/// the scoped dashboard transactions — banner count must be `.length` only.
List<BankStatementLine> uncategorizedTransactionsForDashboardScope(
  DashboardScope scope, {
  required List<Transaction> scopedTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
}) {
  return uncategorizedBankStatementLines(
    scopedTransactions,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
  );
}

/// Same as [uncategorizedTransactionsForDashboardScope] (…).length — avoids a second definition.
int uncategorizedCountForDashboardScope(
  DashboardScope scope, {
  required List<Transaction> scopedTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
}) => uncategorizedTransactionsForDashboardScope(
  scope,
  scopedTransactions: scopedTransactions,
  categoryOverrides: categoryOverrides,
  categoryDisplayRenamesLower: categoryDisplayRenamesLower,
).length;

/// Prefer [uncategorizedTransactionsForDashboardScope].
List<BankStatementLine> uncategorizedBankStatementLinesForDashboardScope(
  DashboardScope scope, {
  required List<Transaction> scopedTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
}) => uncategorizedTransactionsForDashboardScope(
  scope,
  scopedTransactions: scopedTransactions,
  categoryOverrides: categoryOverrides,
  categoryDisplayRenamesLower: categoryDisplayRenamesLower,
);
