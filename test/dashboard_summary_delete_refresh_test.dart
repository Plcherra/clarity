import 'package:clarity/app/app_state.dart';
import 'package:clarity/core/formatting/formatting.dart';
import 'package:clarity/core/models/models.dart';
import 'package:clarity/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:clarity/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DashboardSnapshot _globalSnapshot(AppState s) {
  return buildDashboardSnapshot(
    scope: const GlobalDashboardScope(),
    reference: s.spendReference,
    accounts: s.accounts,
    allTransactions: s.allTransactions,
    scopedTransactions: s.allTransactions,
    categoryOverrides: s.categoryOverrides,
    categoryDisplayRenamesLower: s.categoryDisplayRenames,
    scopedBalanceFromStatement: null,
  );
}

String _summaryLine(AppState s) {
  final snap = _globalSnapshot(s);
  return 'Income ${formatMoney(snap.incomeThisMonth)} · '
      'Spending ${formatMoney(snap.spentThisMonth)}';
}

Transaction _tx({
  required DateTime date,
  required String description,
  required double amount,
  required String accountId,
  required String importId,
}) {
  return Transaction(
    date: DateTime(date.year, date.month, date.day, 12),
    description: description,
    amount: amount,
    accountId: accountId,
    importId: importId,
  );
}

void main() {
  testWidgets(
    'Dashboard summary refreshes after transaction, CSV batch, and account delete',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      state.accounts = const [
        Account(id: 'a', name: 'A', type: AccountType.checking),
        Account(id: 'b', name: 'B', type: AccountType.checking),
      ];

      final ref = state.spendReference;
      final tA1 = _tx(
        date: DateTime(ref.year, ref.month, 5, 12),
        description: 'Store A',
        amount: -10,
        accountId: 'a',
        importId: '100',
      );
      final tA2 = _tx(
        date: DateTime(ref.year, ref.month, 6, 12),
        description: 'Store B',
        amount: -20,
        accountId: 'a',
        importId: '100',
      );
      final tA3 = _tx(
        date: DateTime(ref.year, ref.month, 7, 12),
        description: 'Income C',
        amount: 50,
        accountId: 'a',
        importId: '200',
      );
      final tB1 = _tx(
        date: DateTime(ref.year, ref.month, 8, 12),
        description: 'Store D',
        amount: -5,
        accountId: 'b',
        importId: '300',
      );

      state.transactionsByAccount = {
        'a': [tA1, tA2, tA3],
        'b': [tB1],
      };
      state.activeAccountId = 'a';

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(controller: state.ui.dashboard, isRoot: true),
        ),
      );
      await tester.pump();

      final initial = _summaryLine(state);
      expect(find.text(initial), findsOneWidget);

      await state.deleteTransaction(tA1);
      await tester.pump();
      final afterSingleDelete = _summaryLine(state);
      expect(afterSingleDelete, isNot(initial));
      expect(find.text(afterSingleDelete), findsOneWidget);

      await state.deleteTransactionsForImportBatch(
        accountId: 'a',
        importId: '100',
      );
      await tester.pump();
      final afterBatchDelete = _summaryLine(state);
      expect(afterBatchDelete, isNot(afterSingleDelete));
      expect(find.text(afterBatchDelete), findsOneWidget);

      await state.deleteAccount('b');
      await tester.pump();
      final afterAccountDelete = _summaryLine(state);
      expect(afterAccountDelete, isNot(afterBatchDelete));
      expect(find.text(afterAccountDelete), findsOneWidget);
    },
  );
}
