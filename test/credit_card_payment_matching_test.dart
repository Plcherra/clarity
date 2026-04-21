import 'package:clarity/app_state.dart';
import 'package:clarity/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmed CC payment excludes checking outflow from spend', () {
    final state = AppState();
    state.accounts = [
      const Account(
        id: 'checking',
        name: 'BofA Checking',
        institution: 'Bank of America',
        type: AccountType.checking,
      ),
      const Account(
        id: 'cap1',
        name: 'Capital One',
        institution: 'Capital One',
        type: AccountType.creditCard,
      ),
    ];

    const checkingCsv = '''
Date,Description,Amount
2026-04-05,Online Banking payment to CRD 5324 Confirmation# abc,-300.00
''';

    const cap1Csv = '''
Date,Description,Amount
2026-04-04,Purchase A,-100.00
2026-04-04,Purchase B,-200.00
2026-04-06,Payment Received,300.00
''';

    // Import both sides.
    state.loadFromCsv(checkingCsv, accountId: 'checking', reference: DateTime(2026, 4, 15));
    state.loadFromCsv(cap1Csv, accountId: 'cap1', reference: DateTime(2026, 4, 15));

    // Only the underlying purchases should count as expense spending (300).
    expect(state.spentThisMonth, closeTo(300, 0.01));
  });

  test('unconfirmed CC payment still counts as expense (conservative)', () {
    final state = AppState();
    state.accounts = [
      const Account(
        id: 'checking',
        name: 'BofA Checking',
        institution: 'Bank of America',
        type: AccountType.checking,
      ),
      const Account(
        id: 'cap1',
        name: 'Capital One',
        institution: 'Capital One',
        type: AccountType.creditCard,
      ),
    ];

    const checkingCsv = '''
Date,Description,Amount
2026-04-05,Online Banking payment to CRD 5324 Confirmation# abc,-300.00
''';

    const cap1Csv = '''
Date,Description,Amount
2026-04-04,Purchase A,-100.00
2026-04-04,Purchase B,-200.00
''';

    state.loadFromCsv(checkingCsv, accountId: 'checking', reference: DateTime(2026, 4, 15));
    state.loadFromCsv(cap1Csv, accountId: 'cap1', reference: DateTime(2026, 4, 15));

    // Without the +300 counterpart payment row, the checking payment stays counted.
    expect(state.spentThisMonth, closeTo(600, 0.01));
  });

  test('Amex activity does not suppress Capital One payment without counterpart', () {
    final state = AppState();
    state.accounts = [
      const Account(
        id: 'checking',
        name: 'BofA Checking',
        institution: 'Bank of America',
        type: AccountType.checking,
      ),
      const Account(
        id: 'cap1',
        name: 'Capital One',
        institution: 'Capital One',
        type: AccountType.creditCard,
      ),
      const Account(
        id: 'amex',
        name: 'Amex',
        institution: 'American Express',
        type: AccountType.creditCard,
      ),
    ];

    const checkingCsv = '''
Date,Description,Amount
2026-04-05,Capital One payment thank you,-300.00
''';

    // Amex has a +300 payment row, but the checking description hints Capital One.
    // This must NOT be treated as a confirmed match.
    const amexCsv = '''
Date,Description,Amount
2026-04-06,Payment Received,300.00
2026-04-04,Purchase,-10.00
''';

    state.loadFromCsv(checkingCsv, accountId: 'checking', reference: DateTime(2026, 4, 15));
    state.loadFromCsv(amexCsv, accountId: 'amex', reference: DateTime(2026, 4, 15));

    // No confirmed counterpart in Capital One ledger, so payment remains counted.
    expect(state.spentThisMonth, closeTo(310, 0.01));
  });
}

