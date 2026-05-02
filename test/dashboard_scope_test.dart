import 'package:clarity/app/app_state.dart';
import 'package:clarity/core/models/models.dart';
import 'package:clarity/features/dashboard/application/dashboard_service.dart';
import 'package:clarity/features/dashboard/domain/dashboard_metrics.dart';
import 'package:clarity/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:clarity/features/dashboard/presentation/month_detail_screen.dart';
import 'package:clarity/features/transactions/domain/bank_statement_monthly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx({
  required String accountId,
  required String description,
  required double amount,
  DateTime? date,
}) {
  final d = date ?? DateTime(2026, 4, 15, 12);
  return Transaction(
    date: d,
    description: description,
    amount: amount,
    accountId: accountId,
  );
}

void main() {
  group('uncategorizedBankStatementLines', () {
    test('lists Uncategorized display lines newest first', () {
      final txs = [
        _tx(
          accountId: 'x',
          description: 'zzz totally unknown merchant qqq',
          amount: -5,
          date: DateTime(2026, 4, 10, 12),
        ),
        _tx(
          accountId: 'x',
          description: 'another unknown place',
          amount: -3,
          date: DateTime(2026, 4, 20, 12),
        ),
      ];
      final lines = uncategorizedBankStatementLines(
        txs,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
      );
      expect(lines.length, 2);
      expect(
        lines.first.transaction.date.isAfter(lines.last.transaction.date),
        isTrue,
      );
    });
  });

  group('transactionsForDashboardScope', () {
    test('global includes all accounts; account scope is one list', () {
      final dashboardService = DashboardService();
      final obscureB = _tx(
        accountId: 'b',
        description: 'zzz solo uncategorized on b',
        amount: -12,
      );
      final transactionsByAccount = <String, List<Transaction>>{
        'a': [],
        'b': [obscureB],
      };
      final allTransactions = transactionsByAccount.values
          .expand((txs) => txs)
          .toList();

      final globalTxs = dashboardService.transactionsForDashboardScope(
        scope: const GlobalDashboardScope(),
        allTransactions: allTransactions,
        transactionsByAccount: transactionsByAccount,
      );
      final accountATxs = dashboardService.transactionsForDashboardScope(
        scope: const AccountDashboardScope('a'),
        allTransactions: allTransactions,
        transactionsByAccount: transactionsByAccount,
      );
      final accountBTxs = dashboardService.transactionsForDashboardScope(
        scope: const AccountDashboardScope('b'),
        allTransactions: allTransactions,
        transactionsByAccount: transactionsByAccount,
      );

      expect(globalTxs.length, 1);
      expect(accountATxs, isEmpty);
      expect(accountBTxs.length, 1);

      final globalUncat = uncategorizedBankStatementLines(
        globalTxs,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
      );
      final aUncat = uncategorizedBankStatementLines(
        accountATxs,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
      );

      expect(globalUncat.length, greaterThan(0));
      expect(aUncat, isEmpty);
    });
  });

  group('uncategorized metric alignment', () {
    test('count helper matches bank-line helper length', () {
      final txs = [
        _tx(accountId: 'a', description: 'balance nonsense', amount: -1),
        _tx(accountId: 'a', description: 'unknown zzz merchant', amount: -4),
      ];
      const overrides = <String, String>{};
      const renames = <String, String>{};
      final n = uncategorizedTransactionCount(
        txs,
        categoryOverrides: overrides,
        categoryDisplayRenamesLower: renames,
      );
      final lines = uncategorizedBankStatementLines(
        txs,
        categoryOverrides: overrides,
        categoryDisplayRenamesLower: renames,
      );
      expect(n, lines.length);
    });
  });

  group('MonthDetailScreen', () {
    testWidgets('uses provided MonthlyBankGroup for row count', (tester) async {
      final line1 = BankStatementLine(
        transaction: _tx(
          accountId: 'a',
          description: 'Coffee',
          amount: -3,
          date: DateTime(2026, 4, 1, 12),
        ),
        suggestedCategory: 'Dining',
      );
      final line2 = BankStatementLine(
        transaction: _tx(
          accountId: 'a',
          description: 'Bread',
          amount: -5,
          date: DateTime(2026, 4, 2, 12),
        ),
        suggestedCategory: 'Groceries',
      );
      final group = MonthlyBankGroup(
        yearMonth: '2026-04',
        totalAmount: -8,
        transactions: [line1, line2],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MonthDetailScreen(
            controller: AppState().ui.dashboard,
            group: group,
          ),
        ),
      );
      expect(find.text('2 transactions'), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
    });
  });
}
