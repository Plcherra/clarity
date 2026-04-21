/// Normalizes bank transaction descriptions for substring rule matching.
///
/// Lowercase, trim, collapse internal whitespace to a single space.
/// Category rules may use comma-separated alternatives in the stored pattern; commas
/// are preserved (see [descriptionMatchesCategoryRule] in `spend_categories.dart`).
String normalizeDescriptionForMatching(String s) {
  var out = s.trim();
  // Capital One exports: strip common prefix wrappers for matching and rule suggestions.
  for (final prefix in const [
    'Debit Card Purchase - ',
    'Digital Card Purchase - ',
    'Deposit from ',
    'Withdrawal from ',
  ]) {
    if (out.toLowerCase().startsWith(prefix.toLowerCase())) {
      out = out.substring(prefix.length).trimLeft();
      break;
    }
  }
  return out.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Humble v1 suggestion for the "Save rule?" dialog: first few tokens, editable.
String suggestedPatternFromDescription(String description) {
  final n = normalizeDescriptionForMatching(description);
  if (n.isEmpty) return '';
  final parts = n.split(' ').where((p) => p.isNotEmpty).take(3).toList();
  return parts.join(' ');
}
