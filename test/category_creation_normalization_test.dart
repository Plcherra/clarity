import 'package:clarity/features/categories/domain/category_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes case, spacing, and punctuation for display and dedupe', () {
    final first = normalizeCategoryName(' pet-care!! ');
    final second = normalizeCategoryName('PET   care');

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.displayName, 'Pet Care');
    expect(first.normalizedName, 'pet care');
    expect(second!.displayName, 'Pet Care');
    expect(second.normalizedName, first.normalizedName);
  });

  test('rejects unsafe category suggestions', () {
    expect(normalizeCategoryName('https://example.com'), isNull);
    expect(normalizeCategoryName('person@example.com'), isNull);
    expect(normalizeCategoryName('<script>'), isNull);
    expect(normalizeCategoryName('!!!'), isNull);
  });

  test('keeps Unknown as the stable fallback category', () {
    final unknown = normalizeCategoryName(kUnknownCategoryName);

    expect(unknown, isNotNull);
    expect(unknown!.displayName, kUnknownCategoryName);
    expect(unknown.normalizedName, 'unknown');
  });
}
