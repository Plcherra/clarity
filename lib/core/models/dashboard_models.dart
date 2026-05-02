class CategorySpend {
  const CategorySpend({required this.name, required this.amount});

  final String name;

  /// Positive: total spent in this category (outflows only).
  final double amount;
}

/// Top spending category with month-over-month comparison (dashboard only).
class CategoryLeakStat {
  const CategoryLeakStat({
    required this.name,
    required this.amountThisMonth,
    required this.amountLastMonth,
    this.percentChangeFromLastMonth,
  });

  final String name;
  final double amountThisMonth;
  final double amountLastMonth;

  /// null when [amountLastMonth] is zero (show "New" in UI).
  final double? percentChangeFromLastMonth;
}
