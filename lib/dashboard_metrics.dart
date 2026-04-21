import 'bank_statement_monthly.dart';
import 'category_rule.dart';
import 'financial_role.dart';
import 'models.dart';
import 'spend_categories.dart';

bool _inMonth(DateTime d, DateTime reference) {
  return d.year == reference.year && d.month == reference.month;
}

DateTime _firstDayOfPreviousMonth(DateTime ref) {
  if (ref.month == 1) return DateTime(ref.year - 1, 12, 1);
  return DateTime(ref.year, ref.month - 1, 1);
}

/// Sum of positive inflows in the calendar month of [reference].
///
/// Rows whose effective category is [kIgnoredCategoryLabel] (e.g. reversals) are omitted.
double totalIncomeInMonth(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime reference, {
  Map<String, String> categoryOverrides = const {},
  Map<String, String> categoryDisplayRenamesLower = const {},
  List<CategoryRule> categoryRules = const [],
}) {
  final accountsById = {for (final a in accounts) a.id: a};
  var sum = 0.0;
  for (final t in txs) {
    if (t.amount <= 0 || !_inMonth(t.date, reference)) continue;
    final base = spendGroupLabel(
      t,
      categoryOverrides: categoryOverrides,
      categoryRules: categoryRules,
    );
    if (isIgnoredCategoryLabel(base)) continue;
    final display = applyCategoryDisplayRenames(base, categoryDisplayRenamesLower);
    if (isIgnoredCategoryLabel(display)) continue;
    final role = effectiveFinancialRole(
      t: t,
      effectiveCategoryLabel: base,
      accountsById: accountsById,
      allTransactions: txs,
    );
    if (role != FinancialRole.income) continue;
    sum += t.amount;
  }
  return sum;
}

/// Count of statement rows whose effective category is Uncategorized.
int uncategorizedTransactionCount(
  List<Transaction> txs, {
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
  List<CategoryRule> categoryRules = const [],
}) {
  var n = 0;
  for (final t in txs) {
    if (!isBankStatementDataRow(t)) continue;
    final label = spendGroupLabelForDisplay(
      t,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenamesLower,
      categoryRules: categoryRules,
    );
    if (label.trim().toLowerCase() == 'uncategorized') n++;
  }
  return n;
}

/// Spending by category (outflows, non-income labels), same rules as dashboard top categories.
Map<String, double> _spendByCategoryInMonth(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime month,
  Map<String, String> categoryOverrides,
  Map<String, String> categoryDisplayRenamesLower,
  List<CategoryRule> categoryRules,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final map = <String, double>{};
  for (final t in txs) {
    if (t.amount >= 0) continue;
    if (!_inMonth(t.date, month)) continue;
    final base = spendGroupLabel(
      t,
      categoryOverrides: categoryOverrides,
      categoryRules: categoryRules,
    );
    if (isIgnoredCategoryLabel(base)) continue;
    final role = effectiveFinancialRole(
      t: t,
      effectiveCategoryLabel: base,
      accountsById: accountsById,
      allTransactions: txs,
    );
    if (role != FinancialRole.expense) continue;
    final name = applyCategoryDisplayRenames(base, categoryDisplayRenamesLower);
    if (isIgnoredCategoryLabel(name)) continue;
    map[name] = (map[name] ?? 0) + (-t.amount);
  }
  return map;
}

double? _percentChange(double prev, double current) {
  if (prev <= 0) return null;
  return (current - prev) / prev;
}

/// Top [limit] spending categories for [reference] month with change vs previous month.
List<CategoryLeakStat> biggestCategoryLeaks(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime reference, {
  int limit = 3,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
  List<CategoryRule> categoryRules = const [],
}) {
  final thisMonth = _spendByCategoryInMonth(
    txs,
    accounts,
    reference,
    categoryOverrides,
    categoryDisplayRenamesLower,
    categoryRules,
  );
  final prevRef = _firstDayOfPreviousMonth(reference);
  final lastMonth = _spendByCategoryInMonth(
    txs,
    accounts,
    prevRef,
    categoryOverrides,
    categoryDisplayRenamesLower,
    categoryRules,
  );

  final sorted =
      thisMonth.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.take(limit).toList();

  return top
      .map((e) {
        final name = e.key;
        final cur = e.value;
        final prev = lastMonth[name] ?? 0.0;
        return CategoryLeakStat(
          name: name,
          amountThisMonth: cur,
          amountLastMonth: prev,
          percentChangeFromLastMonth: _percentChange(prev, cur),
        );
      })
      .toList();
}

/// Days of runway if [spentThisMonth] continues at per-day pace for elapsed days in month.
int? runwayDaysFromBurnRate({
  required double totalBalance,
  required double spentThisMonth,
  required DateTime referenceInMonth,
}) {
  if (totalBalance <= 0 || spentThisMonth <= 0) return null;
  final day = referenceInMonth.day;
  final daily = spentThisMonth / (day < 1 ? 1 : day);
  if (daily <= 0 || daily.isNaN) return null;
  final days = (totalBalance / daily).floor();
  if (days < 0) return null;
  return days;
}
