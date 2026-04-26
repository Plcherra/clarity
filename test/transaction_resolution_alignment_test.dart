import 'package:clarity/app_state.dart';
import 'package:clarity/dashboard_queries.dart';
import 'package:clarity/dashboard_snapshot.dart';
import 'package:clarity/models.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx({
  required String accountId,
  required String description,
  required double amount,
  DateTime? date,
}) {
  return Transaction(
    date: date ?? DateTime(2026, 4, 15, 12),
    description: description,
    amount: amount,
    accountId: accountId,
  );
}

void main() {
  group('transaction resolution alignment', () {
    test('banner/review queue matches snapshot for global and account scopes', () {
      final dataRowUncatA = _tx(
        accountId: 'a',
        description: 'zzz unknown merchant qqq',
        amount: -5,
        date: DateTime(2026, 4, 10, 12),
      );
      final dataRowUncatB = _tx(
        accountId: 'b',
        description: 'another unknown merchant zzz',
        amount: -2,
        date: DateTime(2026, 4, 11, 12),
      );
      final skippedSummaryRow = _tx(
        accountId: 'a',
        description: 'Total Debits for period',
        amount: -999,
        date: DateTime(2026, 4, 12, 12),
      );

      final state = AppState();
      state.accounts = [
        const Account(id: 'a', name: 'A', type: AccountType.checking),
        const Account(id: 'b', name: 'B', type: AccountType.checking),
      ];
      state.transactionsByAccount = {
        'a': [dataRowUncatA, skippedSummaryRow],
        'b': [dataRowUncatB],
      };

      void assertScope(DashboardScope scope, int expected) {
        final queue = uncategorizedTransactionsForDashboardScope(state, scope);
        expect(queue.length, expected);

        final snap = buildDashboardSnapshot(
          scope: scope,
          reference: DateTime(2026, 4, 15),
          accounts: state.accounts,
          allTransactions: state.allTransactions,
          scopedTransactions: state.transactionsForDashboardScope(scope),
          categoryOverrides: state.categoryOverrides,
          categoryDisplayRenamesLower: state.categoryDisplayRenames,
          categoryRules: state.categoryRules,
          scopedBalanceFromStatement: null,
        );
        expect(snap.uncategorizedCount, expected);
      }

      assertScope(const GlobalDashboardScope(), 2);
      assertScope(const AccountDashboardScope('a'), 1);
      assertScope(const AccountDashboardScope('b'), 1);
    });
  });
}

