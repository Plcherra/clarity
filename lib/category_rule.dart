/// User-defined description match → category (v1: [matchTypeContains] only).
class CategoryRule {
  CategoryRule({
    required this.id,
    required this.pattern,
    required this.matchType,
    required this.categoryCanonical,
    required this.createdAt,
  });

  static const String matchTypeContains = 'contains';

  /// Stable id; preserved when updating category for the same [pattern].
  final String id;

  /// Stored normalized (see [normalizeDescriptionForMatching]).
  final String pattern;
  final String matchType;
  final String categoryCanonical;
  final DateTime createdAt;

  CategoryRule copyWith({
    String? id,
    String? pattern,
    String? matchType,
    String? categoryCanonical,
    DateTime? createdAt,
  }) {
    return CategoryRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchType: matchType ?? this.matchType,
      categoryCanonical: categoryCanonical ?? this.categoryCanonical,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pattern': pattern,
    'matchType': matchType,
    'categoryCanonical': categoryCanonical,
    'createdAt': createdAt.toIso8601String(),
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
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      createdAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return CategoryRule(
      id: id,
      pattern: pattern,
      matchType: matchType,
      categoryCanonical: categoryCanonical,
      createdAt: createdAt,
    );
  }
}
