import 'helpers/app_composition_test_fixture.dart';
import 'package:clarity/core/models/models.dart';
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

    final state = createTestAppComposition();
    state.accountService.accounts = const [
      Account(id: 'acct', name: 'Acct', type: AccountType.checking),
    ];

    state.transactionWorkflowService.loadFromCsv(
      csvA,
      accountId: 'acct',
      reference: DateTime(2026, 4, 1),
    );
    final first =
        state.transactionService.transactionsByAccount['acct'] ?? const [];
    expect(first.length, 2);
    final firstSum = first.fold<double>(0, (a, t) => a + t.amount);

    state.transactionWorkflowService.loadFromCsv(
      csvB,
      accountId: 'acct',
      reference: DateTime(2026, 4, 1),
    );
    final second =
        state.transactionService.transactionsByAccount['acct'] ?? const [];
    expect(second.length, 2);
    final secondSum = second.fold<double>(0, (a, t) => a + t.amount);

    expect(secondSum, firstSum);
  });
}
