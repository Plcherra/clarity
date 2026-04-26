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

enum FinancialRole {
  expense,
  income,
  transfer,
  creditCardPayment,
  refund,
  adjustment,
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

  /// Set in [AppState.loadFromCsv] after [parseBankCsv] (parser rows use empty id).
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

class AiCategorySuggestion {
  const AiCategorySuggestion({
    required this.transactionKey,
    required this.suggestedCanonical,
    required this.confidence,
    this.rationale,
    required this.createdAtIso,
    required this.model,
    required this.promptVersion,
  });

  final String transactionKey;
  final String? suggestedCanonical;
  final double confidence;
  final String? rationale;
  final String createdAtIso;
  final String model;
  final int promptVersion;

  Map<String, dynamic> toJson() => {
        'transactionKey': transactionKey,
        'suggestedCanonical': suggestedCanonical,
        'confidence': confidence,
        'rationale': rationale,
        'createdAtIso': createdAtIso,
        'model': model,
        'promptVersion': promptVersion,
      };

  factory AiCategorySuggestion.fromJson(Map<String, dynamic> json) {
    final key = json['transactionKey'];
    final conf = json['confidence'];
    final created = json['createdAtIso'];
    final model = json['model'];
    final pv = json['promptVersion'];
    if (key is! String || key.trim().isEmpty) {
      throw const FormatException('Missing transactionKey');
    }
    if (conf is! num) throw const FormatException('Missing confidence');
    if (created is! String || created.trim().isEmpty) {
      throw const FormatException('Missing createdAtIso');
    }
    if (model is! String || model.trim().isEmpty) {
      throw const FormatException('Missing model');
    }
    if (pv is! int) throw const FormatException('Missing promptVersion');

    final suggested = json['suggestedCanonical'];
    final rationale = json['rationale'];
    return AiCategorySuggestion(
      transactionKey: key,
      suggestedCanonical: suggested is String ? suggested : null,
      confidence: conf.toDouble(),
      rationale: rationale is String ? rationale : null,
      createdAtIso: created,
      model: model,
      promptVersion: pv,
    );
  }
}

class AiAppliedCategoryChange {
  const AiAppliedCategoryChange({
    required this.key,
    required this.previousCategoryId,
    required this.newCategoryId,
    required this.appliedAtIso,
  });

  final String key;
  final String? previousCategoryId;
  final String newCategoryId;
  final String appliedAtIso;

  Map<String, dynamic> toJson() => {
        'key': key,
        'previousCategoryId': previousCategoryId,
        'newCategoryId': newCategoryId,
        'appliedAtIso': appliedAtIso,
      };

  factory AiAppliedCategoryChange.fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final next = json['newCategoryId'];
    final appliedAtIso = json['appliedAtIso'];
    if (key is! String || key.trim().isEmpty) {
      throw const FormatException('Missing key');
    }
    if (next is! String || next.trim().isEmpty) {
      throw const FormatException('Missing newCategoryId');
    }
    if (appliedAtIso is! String || appliedAtIso.trim().isEmpty) {
      throw const FormatException('Missing appliedAtIso');
    }
    final prev = json['previousCategoryId'];
    return AiAppliedCategoryChange(
      key: key,
      previousCategoryId: prev is String ? prev : null,
      newCategoryId: next,
      appliedAtIso: appliedAtIso,
    );
  }
}

