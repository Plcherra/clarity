const String kUnknownCategoryName = 'Unknown';

const int _maxCategoryNameLength = 40;

final RegExp _separatorPattern = RegExp(r'''[\s\-_.,;:|!?'"()]+''');
final RegExp _unsafePattern = RegExp(r'[<>{}\[\]\\`~^=]');
final RegExp _hasLetterOrNumberPattern = RegExp(r'[A-Za-z0-9]');
final RegExp _normalizationSeparatorPattern = RegExp(r'[^a-z0-9]+');

final class NormalizedCategoryName {
  const NormalizedCategoryName({
    required this.displayName,
    required this.normalizedName,
  });

  final String displayName;
  final String normalizedName;
}

NormalizedCategoryName? normalizeCategoryName(String raw) {
  final displayName = normalizeCategoryDisplayName(raw);
  if (displayName == null) return null;
  return NormalizedCategoryName(
    displayName: displayName,
    normalizedName: normalizedCategoryKey(displayName),
  );
}

String? normalizeCategoryDisplayName(String raw) {
  var name = raw.trim();
  if (name.isEmpty) return null;
  if (name.length > _maxCategoryNameLength) return null;
  final lower = name.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return null;
  if (lower.contains('@')) return null;
  if (_unsafePattern.hasMatch(name)) return null;
  if (!_hasLetterOrNumberPattern.hasMatch(name)) return null;

  name = name.replaceAll('&', ' and ');
  name = name.replaceAll(RegExp(r'\s*/\s*'), ' / ');
  name = name.replaceAll(_separatorPattern, ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty || name.length > _maxCategoryNameLength) return null;

  final words = name.split(' ');
  return words.map(_titleCaseWord).join(' ');
}

String normalizedCategoryKey(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(_normalizationSeparatorPattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String categoryRecordKey({required String name, String? normalizedName}) {
  final key = normalizedName?.trim();
  if (key != null && key.isNotEmpty) return key;
  return normalizedCategoryKey(name);
}

String _titleCaseWord(String word) {
  if (word.isEmpty) return word;
  if (word == '/') return word;
  final lower = word.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}
