import 'category_rule.dart';
import 'csv_parser.dart';
import 'models.dart';
import 'spend_categories.dart';

/// One parsed line with a suggested category from [description] keywords.
class BankStatementLine {
  const BankStatementLine({
    required this.transaction,
    required this.suggestedCategory,
  });

  final Transaction transaction;
  final String suggestedCategory;
}

/// All transactions for a calendar month plus signed net total.
class MonthlyBankGroup {
  const MonthlyBankGroup({
    required this.yearMonth,
    required this.totalAmount,
    required this.transactions,
  });

  /// `YYYY-MM` (local date from each transaction).
  final String yearMonth;

  /// Sum of signed [Transaction.amount] for the month (net cash flow).
  final double totalAmount;

  final List<BankStatementLine> transactions;
}

bool _shouldSkipDescription(String description) {
  final d = description.toLowerCase();
  return d.contains('total credits') ||
      d.contains('total debits') ||
      d.contains('balance');
}

/// Same row filter as [monthlyGroupsFromTransactions] (summary/balance lines excluded).
bool isBankStatementDataRow(Transaction t) {
  if (t.description.trim().isEmpty) return false;
  if (t.amount.isNaN) return false;
  if (_shouldSkipDescription(t.description)) return false;
  return true;
}

String _yearMonthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Groups [transactions] by calendar month using the same rules as the bank
/// CSV path: drops summary / balance lines and invalid rows, enriches with
/// [spendGroupLabel] (same as dashboard), then groups by `YYYY-MM` with totals.
///
/// Months are ordered **chronologically** (oldest first). Within each month,
/// transactions are sorted by date ascending.
List<MonthlyBankGroup> monthlyGroupsFromTransactions(
  List<Transaction> transactions, {
  Map<String, String>? categoryOverrides,
  Map<String, String>? categoryDisplayRenamesLower,
  List<CategoryRule> categoryRules = const [],
}) {
  final kept = transactions.where(isBankStatementDataRow).toList();

  final byMonth = <String, List<BankStatementLine>>{};
  for (final t in kept) {
    final key = _yearMonthKey(t.date);
    byMonth
        .putIfAbsent(key, () => [])
        .add(
          BankStatementLine(
            transaction: t,
            suggestedCategory: spendGroupLabelForDisplay(
              t,
              categoryOverrides: categoryOverrides,
              categoryDisplayRenamesLower: categoryDisplayRenamesLower,
              categoryRules: categoryRules,
            ),
          ),
        );
  }

  final keys = byMonth.keys.toList()..sort();
  final out = <MonthlyBankGroup>[];
  for (final key in keys) {
    final lines = List<BankStatementLine>.from(byMonth[key]!);
    lines.sort((a, b) => a.transaction.date.compareTo(b.transaction.date));
    final total = lines.fold<double>(0, (sum, e) => sum + e.transaction.amount);
    out.add(
      MonthlyBankGroup(yearMonth: key, totalAmount: total, transactions: lines),
    );
  }
  return out;
}

/// Reads a bank CSV, then groups via [monthlyGroupsFromTransactions].
///
/// Prefer parsing once with [parseBankCsv] and calling
/// [monthlyGroupsFromTransactions] when you already have a transaction list.
List<MonthlyBankGroup> parseBankStatementGroupedByMonth(String csvText) {
  final result = parseBankCsv(csvText);
  return monthlyGroupsFromTransactions(result.transactions);
}
