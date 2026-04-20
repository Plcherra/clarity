/// How the rule was first recorded (or unknown for legacy data).
enum CategoryRuleSource {
  /// Created from the post-assignment “save pattern” flow on a transaction.
  learnedFromTransaction,

  /// Created or last saved from the Rules Management screen.
  manualFromRules,

  /// Persisted JSON had no `source` field (rules from before this metadata).
  unknown,
}

CategoryRuleSource _categoryRuleSourceFromJson(Object? raw) {
  if (raw is! String) return CategoryRuleSource.unknown;
  switch (raw) {
    case 'learned':
      return CategoryRuleSource.learnedFromTransaction;
    case 'manual':
      return CategoryRuleSource.manualFromRules;
    case 'unknown':
      return CategoryRuleSource.unknown;
    default:
      return CategoryRuleSource.unknown;
  }
}

String _categoryRuleSourceToJson(CategoryRuleSource s) {
  switch (s) {
    case CategoryRuleSource.learnedFromTransaction:
      return 'learned';
    case CategoryRuleSource.manualFromRules:
      return 'manual';
    case CategoryRuleSource.unknown:
      return 'unknown';
  }
}

/// User-defined description match → category (v1: [matchTypeContains] only).
class CategoryRule {
  CategoryRule({
    required this.id,
    required this.pattern,
    required this.matchType,
    required this.categoryCanonical,
    required this.createdAt,
    this.source = CategoryRuleSource.unknown,
  });

  static const String matchTypeContains = 'contains';

  /// Stable id; preserved when updating category for the same [pattern].
  final String id;

  /// Stored normalized (see [normalizeDescriptionForMatching]).
  final String pattern;
  final String matchType;
  final String categoryCanonical;
  final DateTime createdAt;

  /// Provenance for UI; persisted when not [CategoryRuleSource.unknown].
  final CategoryRuleSource source;

  CategoryRule copyWith({
    String? id,
    String? pattern,
    String? matchType,
    String? categoryCanonical,
    DateTime? createdAt,
    CategoryRuleSource? source,
  }) {
    return CategoryRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchType: matchType ?? this.matchType,
      categoryCanonical: categoryCanonical ?? this.categoryCanonical,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pattern': pattern,
    'matchType': matchType,
    'categoryCanonical': categoryCanonical,
    'createdAt': createdAt.toIso8601String(),
    'source': _categoryRuleSourceToJson(source),
  };

  static CategoryRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final pattern = json['pattern'];
    final matchType = json['matchType'];
    final categoryCanonical = json['categoryCanonical'];
    final createdAtRaw = json['createdAt'];
    if (id is! String ||
        pattern is! String ||
        matchType is! String ||
        categoryCanonical is! String) {
      return null;
    }
    DateTime createdAt;
    if (createdAtRaw is String) {
      createdAt =
          DateTime.tryParse(createdAtRaw) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      createdAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    final source = _categoryRuleSourceFromJson(json['source']);
    return CategoryRule(
      id: id,
      pattern: pattern,
      matchType: matchType,
      categoryCanonical: categoryCanonical,
      createdAt: createdAt,
      source: source,
    );
  }
}
