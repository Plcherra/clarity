import 'package:clarity/ai_categorization_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeSuggestionToAllowed', () {
    test('matches case-insensitively', () {
      const allowed = ['Shopping', 'Food & Drink'];
      expect(normalizeSuggestionToAllowed('shopping', allowed), 'Shopping');
      expect(normalizeSuggestionToAllowed('FOOD & DRINK', allowed), 'Food & Drink');
    });

    test('returns null when not in list', () {
      const allowed = ['Shopping'];
      expect(normalizeSuggestionToAllowed('Unknown', allowed), isNull);
      expect(normalizeSuggestionToAllowed('', allowed), isNull);
      expect(normalizeSuggestionToAllowed(null, allowed), isNull);
    });
  });

  group('parseSuggestionsFromResponseContent', () {
    test('parses suggestions and normalizes categories', () {
      const allowed = ['Shopping', 'Transportation'];
      final keys = {'a|2024-01-01T12:00:00.000|10.0|X|'}.toSet();
      const json = '{"suggestions":[{"key":"a|2024-01-01T12:00:00.000|10.0|X|","categoryId":"shopping"},'
          '{"key":"missing","categoryId":"Transportation"}]}';
      // Note: second key not in expectedKeys so skipped
      final out = parseSuggestionsFromResponseContent(json, allowed, keys);
      expect(out.length, 1);
      expect(out['a|2024-01-01T12:00:00.000|10.0|X|'], 'Shopping');
    });

    test('null category for unrecognized label', () {
      const allowed = ['Shopping'];
      final keys = {'k1'}.toSet();
      const json = '{"suggestions":[{"key":"k1","categoryId":"NotInList"}]}';
      final out = parseSuggestionsFromResponseContent(json, allowed, keys);
      expect(out['k1'], isNull);
    });
  });
}
