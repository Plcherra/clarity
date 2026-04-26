import 'package:clarity/app_state.dart';
import 'package:clarity/dashboard_queries.dart';
import 'package:clarity/dashboard_snapshot.dart';
import 'package:clarity/models.dart';
import 'package:clarity/spend_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dashboard_queries', () {
    test('monthlyGroups matches snapshot groups for same scope', () {
      final t1 = Transaction(
        date: DateTime(2026, 4, 10, 12),
        description: 'Coffee shop',
        amount: -4,
        accountId: 'a',
      );
      final state = AppState();
      state.accounts = [
        const Account(
          id: 'a',
          name: 'A',
          type: AccountType.checking,
        ),
      ];
      state.transactionsByAccount = {'a': [t1]};
      const scope = GlobalDashboardScope();
      final ref = DateTime(2026, 4, 15);
      final snap = buildDashboardSnapshot(
        scope: scope,
        reference: ref,
        accounts: state.accounts,
        allTransactions: state.allTransactions,
        scopedTransactions: state.transactionsForDashboardScope(scope),
        categoryOverrides: state.categoryOverrides,
        categoryDisplayRenamesLower: state.categoryDisplayRenames,
        categoryRules: state.categoryRules,
        scopedBalanceFromStatement: null,
      );
      final fromQueries = monthlyGroupsForDashboardScope(state, scope);
      expect(fromQueries.length, snap.monthlyGroups.length);
      for (var i = 0; i < fromQueries.length; i++) {
        expect(fromQueries[i].yearMonth, snap.monthlyGroups[i].yearMonth);
        expect(
          fromQueries[i].transactions.length,
          snap.monthlyGroups[i].transactions.length,
        );
      }
    });

    test('uncategorizedCountForDashboardScope matches snapshot', () {
      final obscure = Transaction(
        date: DateTime(2026, 4, 12, 12),
        description: 'zzz unique unknown place qqq',
        amount: -2,
        accountId: 'b',
      );
      final state = AppState();
      state.transactionsByAccount = {'b': [obscure]};
      state.accounts = [
        const Account(
          id: 'b',
          name: 'B',
          type: AccountType.checking,
        ),
      ];
      const scope = GlobalDashboardScope();
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
      expect(
        uncategorizedCountForDashboardScope(state, scope),
        snap.uncategorizedCount,
      );
      expect(
        uncategorizedTransactionsForDashboardScope(state, scope).length,
        snap.uncategorizedCount,
      );
    });

    test('uncategorized alignment respects display renames', () {
      final tx = Transaction(
        date: DateTime(2026, 4, 12, 12),
        description: 'zzz unique unknown place qqq',
        amount: -2,
        accountId: 'b',
      );
      final state = AppState();
      state.transactionsByAccount = {'b': [tx]};
      state.accounts = [
        const Account(id: 'b', name: 'B', type: AccountType.checking),
      ];
      // Rename Uncategorized -> something else: should remove it from needs-attention.
      state.categoryDisplayRenames = {'uncategorized': 'Needs manual'};

      const scope = GlobalDashboardScope();
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

      expect(uncategorizedCountForDashboardScope(state, scope), 0);
      expect(uncategorizedTransactionsForDashboardScope(state, scope), isEmpty);
      expect(snap.uncategorizedCount, 0);
    });

    test('effectiveCategoryDisplayLabel matches spendGroupLabelForDisplay', () {
      final t = Transaction(
        date: DateTime(2026, 4, 1, 12),
        description: 'Test merchant unknown',
        amount: -1,
        accountId: 'x',
      );
      final state = AppState();
      expect(
        state.effectiveCategoryDisplayLabel(t),
        spendGroupLabelForDisplay(
          t,
          categoryOverrides: state.categoryOverrides,
          categoryDisplayRenamesLower: state.categoryDisplayRenames,
          categoryRules: state.categoryRules,
        ),
      );
    });
  });
}
