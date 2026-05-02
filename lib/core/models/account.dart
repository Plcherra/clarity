enum AccountType { checking, savings, creditCard }

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
    this.institution,
    this.currentBalance,
  });

  final String id;
  final String name;
  final AccountType type;
  final String? institution;

  /// Optional running balance for the account (not required for CSV import v1).
  final double? currentBalance;
}
