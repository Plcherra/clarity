enum FinancialRole {
  expense,
  income,
  transfer,
  creditCardPayment,
  refund,
  adjustment,
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
    this.importId,
    this.fingerprint,
    this.financialRole,
  });

  /// Parsed calendar date in local terms (time set to noon to avoid DST edge cases).
  final DateTime date;
  final String description;

  /// Signed: negative = money out (spend), positive = money in.
  final double amount;
  final String? category;
  final double? balanceAfter;

  /// Set after CSV parsing; parser rows use an empty id before account assignment.
  final String accountId;

  /// User-chosen spend category (canonical label), persisted across imports and restarts.
  final String? categoryId;

  /// Import batch identifier (helps debug and undo imports; v1 may be timestamp-based).
  final String? importId;

  /// Stable-ish fingerprint for dedupe within an account.
  final String? fingerprint;

  /// Optional stored role; when null, role is derived from heuristics + matcher.
  final FinancialRole? financialRole;

  bool get isOutflow => amount < 0;
}
