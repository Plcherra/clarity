import 'package:clarity/core/models/models.dart';
import 'package:clarity/features/dashboard/application/dashboard_service.dart';
import 'package:clarity/features/dashboard/domain/dashboard_queries.dart';
import 'package:clarity/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:clarity/features/transactions/application/category_service.dart';
import 'package:clarity/features/transactions/application/transaction_service.dart';
import 'package:clarity/features/transactions/domain/spend_categories.dart';
import 'package:flutter_test/flutter_test.dart';

List<Transaction> _allTransactions(
  Map<String, List<Transaction>> transactionsByAccount,
) {
  return transactionsByAccount.values.expand((txs) => txs).toList();
}

List<Transaction> _transactionsForScope({
  required DashboardService dashboard,
  required DashboardScope scope,
  required Map<String, List<Transaction>> transactionsByAccount,
}) {
  return dashboard.transactionsForDashboardScope(
    scope: scope,
    allTransactions: _allTransactions(transactionsByAccount),
    transactionsByAccount: transactionsByAccount,
  );
}

void main() {
  group('dashboard_queries', () {
    test('monthlyGroups matches snapshot groups for same scope', () {
      final t1 = Transaction(
        date: DateTime(2026, 4, 10, 12),
        description: 'Coffee shop',
        amount: -4,
        accountId: 'a',
      );
      final dashboard = DashboardService();
      final accounts = [
        const Account(id: 'a', name: 'A', type: AccountType.checking),
      ];
      final transactionsByAccount = {
        'a': [t1],
      };
      const scope = GlobalDashboardScope();
      final ref = DateTime(2026, 4, 15);
      final scopedTransactions = _transactionsForScope(
        dashboard: dashboard,
        scope: scope,
        transactionsByAccount: transactionsByAccount,
      );
      final snap = buildDashboardSnapshot(
        scope: scope,
        reference: ref,
        accounts: accounts,
        allTransactions: _allTransactions(transactionsByAccount),
        scopedTransactions: scopedTransactions,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
        scopedBalanceFromStatement: null,
      );
      final fromQueries = monthlyGroupsForDashboardScope(
        scope,
        scopedTransactions: scopedTransactions,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
      );
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
      final dashboard = DashboardService();
      final transactionsByAccount = {
        'b': [obscure],
      };
      final accounts = [
        const Account(id: 'b', name: 'B', type: AccountType.checking),
      ];
      const scope = GlobalDashboardScope();
      final scopedTransactions = _transactionsForScope(
        dashboard: dashboard,
        scope: scope,
        transactionsByAccount: transactionsByAccount,
      );
      final snap = buildDashboardSnapshot(
        scope: scope,
        reference: DateTime(2026, 4, 15),
        accounts: accounts,
        allTransactions: _allTransactions(transactionsByAccount),
        scopedTransactions: scopedTransactions,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: const {},
        scopedBalanceFromStatement: null,
      );
      expect(
        uncategorizedCountForDashboardScope(
          scope,
          scopedTransactions: scopedTransactions,
          categoryOverrides: const {},
          categoryDisplayRenamesLower: const {},
        ),
        snap.uncategorizedCount,
      );
      expect(
        uncategorizedTransactionsForDashboardScope(
          scope,
          scopedTransactions: scopedTransactions,
          categoryOverrides: const {},
          categoryDisplayRenamesLower: const {},
        ).length,
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
      final dashboard = DashboardService();
      final transactionsByAccount = {
        'b': [tx],
      };
      final accounts = [
        const Account(id: 'b', name: 'B', type: AccountType.checking),
      ];
      // Rename Uncategorized -> something else: should remove it from needs-attention.
      const categoryDisplayRenames = {'uncategorized': 'Needs manual'};

      const scope = GlobalDashboardScope();
      final scopedTransactions = _transactionsForScope(
        dashboard: dashboard,
        scope: scope,
        transactionsByAccount: transactionsByAccount,
      );
      final snap = buildDashboardSnapshot(
        scope: scope,
        reference: DateTime(2026, 4, 15),
        accounts: accounts,
        allTransactions: _allTransactions(transactionsByAccount),
        scopedTransactions: scopedTransactions,
        categoryOverrides: const {},
        categoryDisplayRenamesLower: categoryDisplayRenames,
        scopedBalanceFromStatement: null,
      );

      expect(
        uncategorizedCountForDashboardScope(
          scope,
          scopedTransactions: scopedTransactions,
          categoryOverrides: const {},
          categoryDisplayRenamesLower: categoryDisplayRenames,
        ),
        0,
      );
      expect(
        uncategorizedTransactionsForDashboardScope(
          scope,
          scopedTransactions: scopedTransactions,
          categoryOverrides: const {},
          categoryDisplayRenamesLower: categoryDisplayRenames,
        ),
        isEmpty,
      );
      expect(snap.uncategorizedCount, 0);
    });

    test('effectiveCategoryDisplayLabel matches spendGroupLabelForDisplay', () {
      final t = Transaction(
        date: DateTime(2026, 4, 1, 12),
        description: 'Test merchant unknown',
        amount: -1,
        accountId: 'x',
      );
      final transactionService = TransactionService();
      final categoryService = CategoryService();
      expect(
        transactionService.effectiveCategoryDisplayLabel(
          t,
          categoryService: categoryService,
          categoryDisplayRenames: const {},
          merchantCategoryMemory: const {},
          accounts: const [],
          allTransactionsContext: const [],
        ),
        spendGroupLabelForDisplay(
          t,
          categoryOverrides: categoryService.categoryOverrides,
          categoryDisplayRenamesLower: const {},
        ),
      );
    });
  });
}
