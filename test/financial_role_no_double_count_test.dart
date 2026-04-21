import 'package:clarity/app_state.dart';
import 'package:clarity/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppState _stateWithAccounts(List<Account> accounts) {
    final s = AppState();
    s.accounts = accounts;
    return s;
  }

  test('confirmed CC payment excludes checking outflow (no double count)', () {
    final state = _stateWithAccounts([
      const Account(
        id: 'checking',
        name: 'BOA Checking',
        type: AccountType.checking,
        institution: 'Bank of America',
      ),
      const Account(
        id: 'cap1',
        name: 'Capital One',
        type: AccountType.creditCard,
        institution: 'Capital One',
      ),
    ]);

    const checkingCsv = '''
Date,Description,Amount,Category
2026-04-10,Capital One payment,-300.00,Credit Card Payment
''';

    const cap1Csv = '''
Date,Description,Amount,Category
2026-04-10,Online payment received,300.00,Payment
2026-04-09,Market Basket,-100.00,Shopping
2026-04-11,Uber ride,-50.00,Transportation
''';

    state.loadFromCsv(
      checkingCsv,
      accountId: 'checking',
      reference: DateTime(2026, 4, 15),
    );
    state.loadFromCsv(
      cap1Csv,
      accountId: 'cap1',
      reference: DateTime(2026, 4, 15),
    );

    // Purchases should count as spend; the checking payment should be excluded.
    expect(state.spentThisMonth, closeTo(150.00, 0.01));
  });

  test('unconfirmed CC payment still counts as expense (conservative)', () {
    final state = _stateWithAccounts([
      const Account(
        id: 'checking',
        name: 'BOA Checking',
        type: AccountType.checking,
        institution: 'Bank of America',
      ),
      const Account(
        id: 'cap1',
        name: 'Capital One',
        type: AccountType.creditCard,
        institution: 'Capital One',
      ),
    ]);

    const checkingCsv = '''
Date,Description,Amount,Category
2026-04-10,Capital One payment,-300.00,Credit Card Payment
''';

    // No +300 payment row imported on the credit-card side.
    const cap1PurchasesOnlyCsv = '''
Date,Description,Amount,Category
2026-04-09,Market Basket,-100.00,Shopping
2026-04-11,Uber ride,-50.00,Transportation
''';

    state.loadFromCsv(
      checkingCsv,
      accountId: 'checking',
      reference: DateTime(2026, 4, 15),
    );
    state.loadFromCsv(
      cap1PurchasesOnlyCsv,
      accountId: 'cap1',
      reference: DateTime(2026, 4, 15),
    );

    // With no confirmed counterpart, treat the checking payment as real spend (for now).
    expect(state.spentThisMonth, closeTo(450.00, 0.01));
  });

  test('unrelated CC ledger does not exclude a different-institution payment', () {
    final state = _stateWithAccounts([
      const Account(
        id: 'checking',
        name: 'BOA Checking',
        type: AccountType.checking,
        institution: 'Bank of America',
      ),
      const Account(
        id: 'cap1',
        name: 'Capital One',
        type: AccountType.creditCard,
        institution: 'Capital One',
      ),
      const Account(
        id: 'amex',
        name: 'Amex',
        type: AccountType.creditCard,
        institution: 'Amex',
      ),
    ]);

    const checkingCsv = '''
Date,Description,Amount,Category
2026-04-10,Capital One payment,-300.00,Credit Card Payment
''';

    // Amex has activity this month, but no matching +300 payment exists for Capital One.
    const amexCsv = '''
Date,Description,Amount,Category
2026-04-08,Amazon,-25.00,Shopping
''';

    const cap1PurchasesOnlyCsv = '''
Date,Description,Amount,Category
2026-04-09,Market Basket,-100.00,Shopping
''';

    state.loadFromCsv(
      checkingCsv,
      accountId: 'checking',
      reference: DateTime(2026, 4, 15),
    );
    state.loadFromCsv(
      amexCsv,
      accountId: 'amex',
      reference: DateTime(2026, 4, 15),
    );
    state.loadFromCsv(
      cap1PurchasesOnlyCsv,
      accountId: 'cap1',
      reference: DateTime(2026, 4, 15),
    );

    // Capital One payment remains unconfirmed => counts as expense; Amex activity must not suppress it.
    expect(state.spentThisMonth, closeTo(425.00, 0.01));
  });
}

