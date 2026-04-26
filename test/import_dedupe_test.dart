import 'package:clarity/app_state.dart';
import 'package:clarity/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('importing same CSV twice is idempotent', () {
    const csvA = '''
Date,Description,Amount,Running Bal.
2026-04-10,Market Basket,-12.34,100.00
2026-04-11,Uber ride,-9.87,90.13
''';
    const csvB = '''
Date,Description,Amount,Running Bal.
2026-04-10,Market Basket,-12.34,999.99
2026-04-11,Uber ride,-9.87,888.88
''';

    final state = AppState();
    state.accounts = const [
      Account(id: 'acct', name: 'Acct', type: AccountType.checking),
    ];

    state.loadFromCsv(
      csvA,
      accountId: 'acct',
      reference: DateTime(2026, 4, 1),
    );
    final first = state.transactionsByAccount['acct'] ?? const [];
    expect(first.length, 2);
    final firstSum = first.fold<double>(0, (a, t) => a + t.amount);

    state.loadFromCsv(
      csvB,
      accountId: 'acct',
      reference: DateTime(2026, 4, 1),
    );
    final second = state.transactionsByAccount['acct'] ?? const [];
    expect(second.length, 2);
    final secondSum = second.fold<double>(0, (a, t) => a + t.amount);

    expect(secondSum, firstSum);
  });
}

