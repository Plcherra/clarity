final class ProfileRecord {
  const ProfileRecord({
    required this.id,
    this.email,
    this.fullName,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? email;
  final String? fullName;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProfileRecord.fromJson(Map<String, dynamic> json) {
    return ProfileRecord(
      id: _string(json, 'id'),
      email: _nullableString(json, 'email'),
      fullName: _nullableString(json, 'full_name'),
      avatarUrl: _nullableString(json, 'avatar_url'),
      createdAt: _dateTime(json, 'created_at'),
      updatedAt: _dateTime(json, 'updated_at'),
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
    'id': userId,
    'email': email,
    'full_name': fullName,
    'avatar_url': avatarUrl,
  };

  Map<String, dynamic> toUpdateJson() => {
    if (email != null) 'email': email,
    if (fullName != null) 'full_name': fullName,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };
}

final class CategoryRecord {
  const CategoryRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.color,
    this.icon,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String type;
  final String? color;
  final String? icon;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CategoryRecord.fromJson(Map<String, dynamic> json) {
    return CategoryRecord(
      id: _string(json, 'id'),
      userId: _string(json, 'user_id'),
      name: _string(json, 'name'),
      type: _string(json, 'type'),
      color: _nullableString(json, 'color'),
      icon: _nullableString(json, 'icon'),
      createdAt: _dateTime(json, 'created_at'),
      updatedAt: _dateTime(json, 'updated_at'),
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'type': type,
    'color': color,
    'icon': icon,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'type': type,
    'color': color,
    'icon': icon,
  };
}

final class BudgetRecord {
  const BudgetRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.amount,
    required this.period,
    this.startDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final double amount;
  final String period;
  final DateTime? startDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BudgetRecord.fromJson(Map<String, dynamic> json) {
    return BudgetRecord(
      id: _string(json, 'id'),
      userId: _string(json, 'user_id'),
      name: _string(json, 'name'),
      amount: _money(json, 'amount'),
      period: _string(json, 'period'),
      startDate: _nullableDate(json, 'start_date'),
      createdAt: _dateTime(json, 'created_at'),
      updatedAt: _dateTime(json, 'updated_at'),
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'amount': amount,
    'period': period,
    'start_date': startDate?.toIso8601String().split('T').first,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'amount': amount,
    'period': period,
    'start_date': startDate?.toIso8601String().split('T').first,
  };
}

final class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.userId,
    required this.accountId,
    this.categoryId,
    required this.amount,
    required this.type,
    this.description,
    required this.date,
    this.merchant,
    required this.importedFromCsv,
    this.importId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;
  final double amount;
  final String type;
  final String? description;
  final DateTime date;
  final String? merchant;
  final bool importedFromCsv;
  final String? importId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: _string(json, 'id'),
      userId: _string(json, 'user_id'),
      accountId: _string(json, 'account_id'),
      categoryId: _nullableString(json, 'category_id'),
      amount: _money(json, 'amount'),
      type: _string(json, 'type'),
      description: _nullableString(json, 'description'),
      date: _date(json, 'date'),
      merchant: _nullableString(json, 'merchant'),
      importedFromCsv: _bool(json, 'imported_from_csv'),
      importId: _nullableString(json, 'import_id'),
      createdAt: _dateTime(json, 'created_at'),
      updatedAt: _dateTime(json, 'updated_at'),
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'account_id': accountId,
    'category_id': categoryId,
    'amount': amount,
    'type': type,
    'description': description,
    'date': date.toIso8601String().split('T').first,
    'merchant': merchant,
    'imported_from_csv': importedFromCsv,
    'import_id': importId,
  };

  Map<String, dynamic> toUpdateJson() => {
    'account_id': accountId,
    'category_id': categoryId,
    'amount': amount,
    'type': type,
    'description': description,
    'date': date.toIso8601String().split('T').first,
    'merchant': merchant,
    'imported_from_csv': importedFromCsv,
    'import_id': importId,
  };
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Missing or invalid "$key".');
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Invalid "$key".');
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Missing or invalid "$key".');
}

double _money(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Missing or invalid "$key".');
}

DateTime _dateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return DateTime.parse(value);
  throw FormatException('Missing or invalid "$key".');
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return DateTime.parse(value);
  throw FormatException('Missing or invalid "$key".');
}

DateTime? _nullableDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return DateTime.parse(value);
  throw FormatException('Invalid "$key".');
}
