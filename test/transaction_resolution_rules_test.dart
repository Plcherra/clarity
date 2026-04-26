import 'package:clarity/app_state.dart';
import 'package:clarity/category_rule.dart';
import 'package:clarity/dashboard_metrics.dart';
import 'package:clarity/dashboard_snapshot.dart';
import 'package:clarity/models.dart';
import 'package:clarity/spend_categories.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx({
  required String accountId,
  required String description,
  required double amount,
  DateTime? date,
  String? category,
  String? categoryId,
}) {
  return Transaction(
    date: date ?? DateTime(2026, 4, 15, 12),
    description: description,
    amount: amount,
    accountId: accountId,
    category: category,
    categoryId: categoryId,
  );
}

void main() {
  group('transaction resolution rules', () {
    test('manual categorization clears needsCategorization', () {
      final state = AppState();
      state.accounts = const [
        Account(id: 'a', name: 'A', type: AccountType.checking),
      ];
      final t = _tx(
        accountId: 'a',
        description: 'zzz unknown merchant qqq',
        amount: -5,
        date: DateTime(2026, 4, 10, 12),
      );
      state.transactionsByAccount = {'a': [t]};

      final key = transactionCategoryKey(t);
      state.categoryOverrides = {key: 'Food & Drink'};

      final r = state.resolveTransaction(t, allTransactionsContext: state.allTransactions);
      expect(r.needsCategorization, isFalse);
      expect(r.displayCategory.toLowerCase(), isNot('uncategorized'));
    });

    test('category rule categorizes matching sibling rows', () {
      final state = AppState();
      state.accounts = const [
        Account(id: 'a', name: 'A', type: AccountType.checking),
      ];
      final t1 = _tx(
        accountId: 'a',
        description: 'ACME COFFEE 123',
        amount: -4,
        date: DateTime(2026, 4, 10, 12),
      );
      final t2 = _tx(
        accountId: 'a',
        description: 'ACME COFFEE 123',
        amount: -6,
        date: DateTime(2026, 4, 11, 12),
      );
      state.transactionsByAccount = {'a': [t1, t2]};

      state.categoryRules = [
        CategoryRule(
          id: '1',
          pattern: 'acme coffee',
          matchType: CategoryRule.matchTypeContains,
          categoryCanonical: 'Coffee / Quick Food',
          createdAt: DateTime(2026, 4, 1).toUtc(),
          source: CategoryRuleSource.manualFromRules,
        ),
      ];

      final rs = state.resolveTransactions(
        state.allTransactions,
        allTransactionsContext: state.allTransactions,
      );
      expect(rs.length, 2);
      expect(rs[0].canonicalCategory, 'Coffee / Quick Food');
      expect(rs[1].canonicalCategory, 'Coffee / Quick Food');
      expect(rs.every((r) => r.needsCategorization == false), isTrue);
    });

    test('dashboard spend excludes non-expense roles (Transfer Out)', () {
      final accounts = const [
        Account(id: 'a', name: 'A', type: AccountType.checking),
      ];
      final ref = DateTime(2026, 4, 15, 12);

      // Suggestion path: description contains "zelle" + "payment to" -> Transfer Out.
      final transfer = _tx(
        accountId: 'a',
        description: 'Zelle payment to John Doe',
        amount: -50,
        date: DateTime(2026, 4, 10, 12),
      );

      final snap = buildDashboardSnapshot(
        scope: const AccountDashboardScope('a'),
        reference: ref,
        accounts: accounts,
        allTransactions: [transfer],
        scopedTransactions: [transfer],
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
        categoryRules: const [],
        scopedBalanceFromStatement: null,
      );

      expect(snap.spentThisMonth, closeTo(0, 0.01));
    });

    test('confirmed credit card payment is excluded from biggest leaks', () {
      final accounts = const [
        Account(
          id: 'checking',
          name: 'BOA Checking',
          type: AccountType.checking,
          institution: 'Bank of America',
        ),
        Account(
          id: 'cap1',
          name: 'Capital One',
          type: AccountType.creditCard,
          institution: 'Capital One',
        ),
      ];

      final checkingPayment = _tx(
        accountId: 'checking',
        description: 'Capital One payment',
        amount: -300,
        date: DateTime(2026, 4, 10, 12),
        category: 'Credit Card Payment',
      );
      final cap1Counterpart = _tx(
        accountId: 'cap1',
        description: 'Online payment received',
        amount: 300,
        date: DateTime(2026, 4, 10, 12),
      );
      final purchase = _tx(
        accountId: 'cap1',
        description: 'Market Basket',
        amount: -100,
        date: DateTime(2026, 4, 9, 12),
        category: 'Shopping',
      );

      final all = [checkingPayment, cap1Counterpart, purchase];
      final leaks = biggestCategoryLeaks(
        all,
        accounts,
        DateTime(2026, 4, 15),
        limit: 10,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
        categoryRules: const [],
      );

      // If the payment is confirmed, its financial role becomes creditCardPayment, not expense,
      // so it must not contribute to spend-by-category (and therefore not appear as a leak).
      expect(leaks.any((e) => e.name.toLowerCase() == 'credit card payment'), isFalse);
    });
  });
}

