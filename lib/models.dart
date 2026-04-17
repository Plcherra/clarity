class Transaction {
  const Transaction({
    required this.date,
    required this.description,
    required this.amount,
    this.category,
    this.balanceAfter,
  });

  /// Parsed calendar date in local terms (time set to noon to avoid DST edge cases).
  final DateTime date;
  final String description;

  /// Signed: negative = money out (spend), positive = money in.
  final double amount;
  final String? category;
  final double? balanceAfter;

  bool get isOutflow => amount < 0;
}

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

  /// null when [amountLastMonth] is zero (show “New” in UI).
  final double? percentChangeFromLastMonth;
}
