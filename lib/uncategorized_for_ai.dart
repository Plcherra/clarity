import 'bank_statement_monthly.dart';
import 'category_rule.dart';
import 'models.dart';
import 'spend_categories.dart';

/// Statement rows that still resolve to Uncategorized (after rules/heuristics), for AI flows.
List<Transaction> uncategorizedDataRowsForImport({
  required List<Transaction> accountTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
  required List<CategoryRule> categoryRules,
}) {
  return accountTransactions
      .where((t) {
        if (!isBankStatementDataRow(t)) return false;
        final label = spendGroupLabelForDisplay(
          t,
          categoryOverrides: categoryOverrides,
          categoryDisplayRenamesLower: categoryDisplayRenamesLower,
          categoryRules: categoryRules,
        );
        return label.trim().toLowerCase() == 'uncategorized';
      })
      .toList();
}
