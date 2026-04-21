import 'package:clarity/dashboard_snapshot.dart';
import 'package:clarity/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global snapshot includes all accounts; account snapshot scopes totals', () {
    final accounts = const [
      Account(id: 'a1', name: 'Checking', type: AccountType.checking),
      Account(id: 'a2', name: 'Card', type: AccountType.creditCard),
    ];
    final ref = DateTime(2026, 4, 15, 12);

    final t1 = Transaction(
      date: DateTime(2026, 4, 1, 12),
      description: 'Shop A',
      amount: -10,
      accountId: 'a1',
    );
    final t2 = Transaction(
      date: DateTime(2026, 4, 2, 12),
      description: 'Shop B',
      amount: -5,
      accountId: 'a2',
    );
    final all = [t1, t2];

    final global = buildDashboardSnapshot(
      scope: const GlobalDashboardScope(),
      reference: ref,
      accounts: accounts,
      allTransactions: all,
      scopedTransactions: all,
      categoryOverrides: const {},
      categoryDisplayRenamesLower: const {},
      categoryRules: const [],
      scopedBalanceFromStatement: null,
    );
    expect(global.spentThisMonth, closeTo(15, 0.01));

    final a1 = buildDashboardSnapshot(
      scope: const AccountDashboardScope('a1'),
      reference: ref,
      accounts: accounts,
      allTransactions: all,
      scopedTransactions: [t1],
      categoryOverrides: const {},
      categoryDisplayRenamesLower: const {},
      categoryRules: const [],
      scopedBalanceFromStatement: null,
    );
    expect(a1.spentThisMonth, closeTo(10, 0.01));

    final a2 = buildDashboardSnapshot(
      scope: const AccountDashboardScope('a2'),
      reference: ref,
      accounts: accounts,
      allTransactions: all,
      scopedTransactions: [t2],
      categoryOverrides: const {},
      categoryDisplayRenamesLower: const {},
      categoryRules: const [],
      scopedBalanceFromStatement: null,
    );
    expect(a2.spentThisMonth, closeTo(5, 0.01));
  });
}

