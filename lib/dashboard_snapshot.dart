import 'balance_resolve.dart';
import 'bank_statement_monthly.dart';
import 'category_rule.dart';
import 'dashboard_metrics.dart';
import 'financial_role.dart';
import 'models.dart';
import 'spend_categories.dart';

sealed class DashboardScope {
  const DashboardScope();
}

final class GlobalDashboardScope extends DashboardScope {
  const GlobalDashboardScope();
}

final class AccountDashboardScope extends DashboardScope {
  const AccountDashboardScope(this.accountId);
  final String accountId;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.totalBalance,
    required this.spentThisMonth,
    required this.incomeThisMonth,
    required this.availableThisMonth,
    required this.uncategorizedCount,
    required this.topCategories,
    required this.biggestLeaksThisMonth,
    required this.burnRunwayDays,
    required this.monthlyGroups,
  });

  final double totalBalance;
  final double spentThisMonth;
  final double incomeThisMonth;
  final double availableThisMonth;
  final int uncategorizedCount;
  final List<CategorySpend> topCategories;
  final List<CategoryLeakStat> biggestLeaksThisMonth;
  final int? burnRunwayDays;
  final List<MonthlyBankGroup> monthlyGroups;
}

DashboardSnapshot buildDashboardSnapshot({
  required DashboardScope scope,
  required DateTime reference,
  required List<Account> accounts,
  required List<Transaction> allTransactions,
  required List<Transaction> scopedTransactions,
  required Map<String, String> categoryOverrides,
  required Map<String, String> categoryDisplayRenamesLower,
  required List<CategoryRule> categoryRules,
  required double? scopedBalanceFromStatement,
}) {
  final accountsById = {for (final a in accounts) a.id: a};

  final y = reference.year;
  final m = reference.month;

  // Spend/income are computed over the scoped list, but role resolution uses global
  // transaction context so internal-payment matching remains correct.
  var spent = 0.0;
  var income = 0.0;
  for (final t in scopedTransactions) {
    if (t.date.year != y || t.date.month != m) continue;
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
      allTransactions: allTransactions,
    );
    if (t.amount < 0 && role == FinancialRole.expense) {
      spent += -t.amount;
    } else if (t.amount > 0 && role == FinancialRole.income) {
      income += t.amount;
    }
  }

  final available = income - spent;

  final uncategorized = uncategorizedTransactionCount(
    scopedTransactions,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
    categoryRules: categoryRules,
  );

  // Top categories (scoped, expense-role only).
  final topMap = <String, double>{};
  for (final t in scopedTransactions) {
    if (t.amount >= 0) continue;
    if (t.date.year != y || t.date.month != m) continue;
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
      allTransactions: allTransactions,
    );
    if (role != FinancialRole.expense) continue;
    final display = applyCategoryDisplayRenames(base, categoryDisplayRenamesLower);
    if (isIgnoredCategoryLabel(display) || isIncomeCategoryLabel(display)) continue;
    topMap[display] = (topMap[display] ?? 0) + (-t.amount);
  }
  final top =
      topMap.entries
          .map((e) => CategorySpend(name: e.key, amount: e.value))
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
  final top5 = top.length <= 5 ? top : top.sublist(0, 5);

  // Leaks (scoped). Note: biggestCategoryLeaks currently uses its provided list
  // for role resolution context. For v1, this is acceptable; the major correctness
  // issue (CC payment exclusion) is handled in spend/income above.
  final leaks = biggestCategoryLeaks(
    scopedTransactions,
    accounts,
    reference,
    limit: 3,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
    categoryRules: categoryRules,
  );

  final grouped = monthlyGroupsFromTransactions(
    scopedTransactions,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
    categoryRules: categoryRules,
  );
  final monthsNewestFirst = grouped.reversed.toList();

  final balance = switch (scope) {
    GlobalDashboardScope() =>
      // v1: keep global balance as whatever caller provides (often last active import).
      resolveTotalBalance(scopedTransactions, scopedBalanceFromStatement),
    AccountDashboardScope(:final accountId) =>
      accountsById[accountId]?.currentBalance ??
      resolveTotalBalance(scopedTransactions, scopedBalanceFromStatement),
  };

  final runway = runwayDaysFromBurnRate(
    totalBalance: balance,
    spentThisMonth: spent,
    referenceInMonth: reference,
  );

  return DashboardSnapshot(
    totalBalance: balance,
    spentThisMonth: spent,
    incomeThisMonth: income,
    availableThisMonth: available,
    uncategorizedCount: uncategorized,
    topCategories: top5,
    biggestLeaksThisMonth: leaks,
    burnRunwayDays: runway,
    monthlyGroups: monthsNewestFirst,
  );
}

