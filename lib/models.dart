enum AccountType {
  checking,
  savings,
  creditCard,
}

extension AccountTypeDisplay on AccountType {
  String get displayLabel => switch (this) {
        AccountType.checking => 'Checking',
        AccountType.savings => 'Savings',
        AccountType.creditCard => 'Credit Card',
      };
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.currentBalance,
  });

  final String id;
  final String name;
  final AccountType type;

  /// Optional running balance for the account (not required for CSV import v1).
  final double? currentBalance;
}

class Transaction {
  const Transaction({
    required this.date,
    required this.description,
    required this.amount,
    required this.accountId,
    this.category,
    this.balanceAfter,
    this.categoryId,
  });

  /// Parsed calendar date in local terms (time set to noon to avoid DST edge cases).
  final DateTime date;
  final String description;

  /// Signed: negative = money out (spend), positive = money in.
  final double amount;
  final String? category;
  final double? balanceAfter;

  /// Set in [AppState.loadFromCsv] after [parseBankCsv] (parser rows use empty id).
  final String accountId;

  /// User-chosen spend category (canonical label), persisted across imports and restarts.
  final String? categoryId;

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
