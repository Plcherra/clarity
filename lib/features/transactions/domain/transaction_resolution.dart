import '../../../core/models/models.dart';
import 'bank_statement_monthly.dart';
import 'financial_role.dart';
import 'spend_categories.dart';

class ResolvedTransaction {
  const ResolvedTransaction({
    required this.transaction,
    required this.canonicalCategory,
    required this.displayCategory,
    required this.financialRole,
    required this.isStatementDataRow,
    required this.countsAsSpend,
    required this.countsAsIncome,
    required this.needsCategorization,
  });

  final Transaction transaction;
  final String canonicalCategory;
  final String displayCategory;
  final FinancialRole financialRole;

  final bool isStatementDataRow;

  /// Dashboard spend should use this only (never recompute role logic).
  final bool countsAsSpend;

  /// Dashboard income should use this only (never recompute role logic).
  final bool countsAsIncome;

  /// Review queue and “needs attention” should use this only.
  final bool needsCategorization;
}

ResolvedTransaction resolveTransaction({
  required Transaction t,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
  required Map<String, Account> accountsById,
  required List<Transaction> allTransactions,
}) {
  final canonical = spendGroupLabel(
    t,
    categoryOverrides: categoryOverrides,
  );
  final display = applyCategoryDisplayRenames(canonical, categoryDisplayRenamesLower);

  final role = effectiveFinancialRole(
    t: t,
    effectiveCategoryLabel: canonical,
    accountsById: accountsById,
    allTransactions: allTransactions,
  );

  final ignoredByCanonical = isIgnoredCategoryLabel(canonical);

  final countsSpend =
      t.amount < 0 && role == FinancialRole.expense && !ignoredByCanonical;
  final countsIncome =
      t.amount > 0 && role == FinancialRole.income && !ignoredByCanonical;

  final isStatementRow = isBankStatementDataRow(t);
  final needsCat = isStatementRow && display.trim().toLowerCase() == 'uncategorized';

  return ResolvedTransaction(
    transaction: t,
    canonicalCategory: canonical,
    displayCategory: display,
    financialRole: role,
    isStatementDataRow: isStatementRow,
    countsAsSpend: countsSpend,
    countsAsIncome: countsIncome,
    needsCategorization: needsCat,
  );
}

List<ResolvedTransaction> resolveTransactions(
  List<Transaction> txs, {
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
  required Map<String, Account> accountsById,
  required List<Transaction> allTransactions,
}) {
  return txs
      .map(
        (t) => resolveTransaction(
          t: t,
          categoryOverrides: categoryOverrides,
          categoryDisplayRenamesLower: categoryDisplayRenamesLower,
          accountsById: accountsById,
          allTransactions: allTransactions,
        ),
      )
      .toList(growable: false);
}

