class BudgetCategoryPerformance {
  const BudgetCategoryPerformance({
    required this.displayLabel,
    required this.budgeted,
    required this.spent,
  });

  final String displayLabel;
  final double budgeted;
  final double spent;

  double get remaining => budgeted - spent;
  double get overspent => remaining < 0 ? -remaining : 0;
  bool get onTrack => remaining >= 0;
}

class BudgetPerformanceSnapshot {
  const BudgetPerformanceSnapshot({
    required this.periodType,
    required this.periodKey,
    required this.periodLabel,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.budgetedCategoryCount,
    required this.onTrackCategoryCount,
    required this.totalOverspent,
    required this.topOverspendingCategories,
  });

  final BudgetPeriodType periodType;
  final String periodKey;
  final String periodLabel;
  final double totalBudgeted;
  final double totalSpent;
  final int budgetedCategoryCount;
  final int onTrackCategoryCount;
  final double totalOverspent;
  final List<BudgetCategoryPerformance> topOverspendingCategories;
}

enum BudgetPeriodType { monthly, weekly, custom }

class BudgetPeriodRange {
  const BudgetPeriodRange({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}
