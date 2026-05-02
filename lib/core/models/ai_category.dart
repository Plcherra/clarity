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
