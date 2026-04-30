import '../../../core/storage/budgets/budget_keys.dart';
import '../../dashboard/domain/dashboard_snapshot.dart';
import '../../transactions/domain/spend_categories.dart';
import '../data/budget_repository.dart';
import '../domain/budget_models.dart';

/// Budget vs spend rollups for the dashboard and Budgets screen.
///
/// Lives here because it joins [BudgetRepository] data with transaction-derived
/// spend totals and dashboard scope filtering.
BudgetPerformanceSnapshot buildBudgetPerformanceForScope(
  DashboardScope scope, {
  required BudgetRepository budgets,
  required Iterable<String> customCategories,
  required Set<String> categoriesHiddenFromPicker,
  required Map<String, String> categoryDisplayRenames,
  required Map<String, double> Function(
    DashboardScope scope, {
    required DateTime start,
    required DateTime end,
  })
  spentByDisplayCategoryForScopeInRange,
  BudgetPeriodType? periodType,
  String? periodKey,
}) {
  final type = periodType ?? budgets.resolvedActiveBudgetPeriodType;
  final key = (periodKey ?? budgets.resolvedActiveBudgetPeriodKey).trim();
  final fallbackType = BudgetPeriodType.monthly;
  final fallbackKey = budgets.budgetYearMonthKey(DateTime.now());
  final effectiveType = key.isEmpty ? fallbackType : type;
  final effectiveKey = key.isEmpty ? fallbackKey : key;
  final range =
      budgets.budgetPeriodRangeFor(
        periodType: effectiveType,
        periodKey: effectiveKey,
      ) ??
      budgets.monthRangeFromYearMonthKey(fallbackKey);
  final budgetMaps = budgets.budgetsForPeriod(
    periodType: effectiveType,
    periodKey: effectiveKey,
  );
  final displayByBudgetKey = <String, String>{};
  final canonicals = categoryPickerCanonicals(
    customCategories: customCategories,
    hiddenLower: categoriesHiddenFromPicker,
  );
  for (final canonical in canonicals) {
    final display = applyCategoryDisplayRenames(
      canonical,
      categoryDisplayRenames,
    );
    displayByBudgetKey[budgetDisplayKey(display)] = display;
  }
  final spentByDisplay = spentByDisplayCategoryForScopeInRange(
    scope,
    start: range.start,
    end: range.end,
  );
  final spentByBudgetKey = <String, double>{};
  for (final e in spentByDisplay.entries) {
    spentByBudgetKey[budgetDisplayKey(e.key)] = e.value;
  }

  var totalBudgeted = 0.0;
  var totalSpent = 0.0;
  var onTrackCount = 0;
  final overspending = <BudgetCategoryPerformance>[];
  for (final e in budgetMaps.entries) {
    final budgeted = e.value;
    final budgetKey = e.key;
    final display = displayByBudgetKey[budgetKey] ?? budgetKey;
    final spent = spentByBudgetKey[budgetKey] ?? 0.0;
    totalBudgeted += budgeted;
    totalSpent += spent;
    final stat = BudgetCategoryPerformance(
      displayLabel: display,
      budgeted: budgeted,
      spent: spent,
    );
    if (stat.onTrack) {
      onTrackCount += 1;
    } else {
      overspending.add(stat);
    }
  }
  overspending.sort((a, b) => b.overspent.compareTo(a.overspent));
  final totalOverspent = overspending.fold<double>(
    0,
    (sum, row) => sum + row.overspent,
  );
  return BudgetPerformanceSnapshot(
    periodType: effectiveType,
    periodKey: effectiveKey,
    periodLabel: budgets.budgetPeriodLabel(
      periodType: effectiveType,
      periodKey: effectiveKey,
    ),
    totalBudgeted: totalBudgeted,
    totalSpent: totalSpent,
    budgetedCategoryCount: budgetMaps.length,
    onTrackCategoryCount: onTrackCount,
    totalOverspent: totalOverspent,
    topOverspendingCategories: overspending.take(2).toList(),
  );
}
