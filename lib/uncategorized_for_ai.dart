import 'bank_statement_monthly.dart';
import 'core/models/models.dart';
import 'transaction_resolution.dart';

/// Statement rows that still resolve to Uncategorized (after rules/heuristics), for AI flows.
List<Transaction> uncategorizedDataRowsForImport({
  required List<Transaction> accountTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
}) {
  final kept = accountTransactions.where(isBankStatementDataRow).toList();
  final resolved = resolveTransactions(
    kept,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
    accountsById: const {},
    allTransactions: accountTransactions,
  );
  return resolved.where((r) => r.needsCategorization).map((r) => r.transaction).toList();
}
