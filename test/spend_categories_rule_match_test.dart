import 'package:clarity/category_description_normalize.dart';
import 'package:clarity/category_rule.dart';
import 'package:clarity/models.dart';
import 'package:clarity/spend_categories.dart';
import 'package:flutter_test/flutter_test.dart';

String _p(String raw) => normalizeDescriptionForMatching(raw);

void main() {
  group('descriptionMatchesCategoryRule', () {
    test('multi-token words match in any order (Capital One … pmt)', () {
      expect(
        descriptionMatchesCategoryRule(
          'Capital One DES: Online Pmt',
          _p('capital one pmt'),
        ),
        isTrue,
      );
    });

    test('single-token compact matches spaced cashback wording', () {
      expect(
        descriptionMatchesCategoryRule(
          'CASH BACK REWARDS',
          _p('cashback'),
        ),
        isTrue,
      );
    });

    test('comma OR matches second alternative', () {
      expect(
        descriptionMatchesCategoryRule(
          'Cash Reward from bank',
          _p('cashback, cash reward'),
        ),
        isTrue,
      );
      expect(
        descriptionMatchesCategoryRule(
          'CASH BACK REWARDS',
          _p('cashback, cash reward'),
        ),
        isTrue,
      );
      expect(
        descriptionMatchesCategoryRule(
          'Something else',
          _p('cashback, cash reward'),
        ),
        isFalse,
      );
    });

    test('comma OR with multi-token second alternative (bar baz)', () {
      expect(
        descriptionMatchesCategoryRule(
          'prefix bar middle baz suffix',
          _p('foo, bar baz'),
        ),
        isTrue,
      );
      expect(
        descriptionMatchesCategoryRule(
          'only foo here',
          _p('foo, bar baz'),
        ),
        isTrue,
      );
      expect(
        descriptionMatchesCategoryRule(
          'bar without second token',
          _p('foo, bar baz'),
        ),
        isFalse,
      );
    });

    test('legacy substring match still works', () {
      expect(
        descriptionMatchesCategoryRule(
          'STARBUCKS STORE 1234',
          _p('starbucks'),
        ),
        isTrue,
      );
    });

    test('multi-token does not match one token inside another word', () {
      expect(
        descriptionMatchesCategoryRule(
          'Something online only',
          _p('capital one'),
        ),
        isFalse,
      );
    });
  });

  group('spendGroupLabel with rules', () {
    final baseDate = DateTime(2026, 1, 1, 12);

    Transaction outflow(String description) => Transaction(
          date: baseDate,
          description: description,
          amount: -10,
          accountId: 'a1',
        );

    test('first matching rule wins', () {
      final rules = <CategoryRule>[
        CategoryRule(
          id: '1',
          pattern: _p('capital one pmt'),
          matchType: CategoryRule.matchTypeContains,
          categoryCanonical: 'Credit Card Payment',
          createdAt: DateTime.utc(2026),
        ),
        CategoryRule(
          id: '2',
          pattern: _p('capital'),
          matchType: CategoryRule.matchTypeContains,
          categoryCanonical: 'Other',
          createdAt: DateTime.utc(2026),
        ),
      ];
      final label = spendGroupLabel(
        outflow('Capital One DES: Online Pmt'),
        categoryRules: rules,
      );
      expect(label, 'Credit Card Payment');
    });
  });
}
