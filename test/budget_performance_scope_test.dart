import 'package:clarity/app_state.dart';
import 'package:clarity/budget_keys.dart';
import 'package:clarity/dashboard_snapshot.dart';
import 'package:clarity/models.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx({
  required String accountId,
  required String description,
  required double amount,
  required String categoryId,
  required DateTime date,
}) {
  return Transaction(
    date: DateTime(date.year, date.month, date.day, 12),
    description: description,
    amount: amount,
    accountId: accountId,
    categoryId: categoryId,
  );
}

void main() {
  test('budget performance is correct for global and account scopes', () async {
    final state = AppState();
    state.accounts = const [
      Account(id: 'a', name: 'A', type: AccountType.checking),
      Account(id: 'b', name: 'B', type: AccountType.checking),
    ];
    final ref = state.spendReference;
    state.transactionsByAccount = {
      'a': [
        _tx(
          accountId: 'a',
          description: 'Groceries',
          amount: -30,
          categoryId: 'Grocery / Supermarket',
          date: ref,
        ),
        _tx(
          accountId: 'a',
          description: 'Shopping',
          amount: -60,
          categoryId: 'Shopping',
          date: ref,
        ),
      ],
      'b': [
        _tx(
          accountId: 'b',
          description: 'Groceries',
          amount: -20,
          categoryId: 'Grocery / Supermarket',
          date: ref,
        ),
      ],
    };
    final month = state.activeBudgetYearMonth;
    state.categoryMonthlyBudgetsByYearMonth = {
      month: {
        budgetDisplayKey('Grocery / Supermarket'): 100,
        budgetDisplayKey('Shopping'): 50,
      },
    };
    state.refreshAllState();

    final global = state.budgetPerformanceForScope(const GlobalDashboardScope());
    expect(global.budgetedCategoryCount, 2);
    expect(global.onTrackCategoryCount, 1);
    expect(global.totalBudgeted, 150);
    expect(global.totalSpent, 110);
    expect(global.totalOverspent, 10);
    expect(global.topOverspendingCategories.length, 1);
    expect(global.topOverspendingCategories.first.displayLabel, 'Shopping');

    final accountB = state.budgetPerformanceForScope(
      const AccountDashboardScope('b'),
    );
    expect(accountB.budgetedCategoryCount, 2);
    expect(accountB.onTrackCategoryCount, 2);
    expect(accountB.totalBudgeted, 150);
    expect(accountB.totalSpent, 20);
    expect(accountB.totalOverspent, 0);
  });

  test('budget performance supports weekly and custom periods', () async {
    final state = AppState();
    state.accounts = const [
      Account(id: 'a', name: 'A', type: AccountType.checking),
    ];
    final monday = DateTime(2026, 4, 6);
    state.transactionsByAccount = {
      'a': [
        _tx(
          accountId: 'a',
          description: 'Coffee',
          amount: -25,
          categoryId: 'Coffee / Quick Food',
          date: monday,
        ),
        _tx(
          accountId: 'a',
          description: 'Transport',
          amount: -40,
          categoryId: 'Transportation',
          date: monday.add(const Duration(days: 2)),
        ),
      ],
    };
    final weekKey = state.budgetWeekStartKey(monday);
    state.categoryWeeklyBudgetsByWeekStart = {
      weekKey: {
        budgetDisplayKey('Coffee / Quick Food'): 30,
        budgetDisplayKey('Transportation'): 30,
      },
    };
    final customKey = state.ensureCustomBudgetPeriod(
      monday,
      monday.add(const Duration(days: 2)),
    );
    state.categoryCustomBudgetsByKey = {
      customKey: {
        budgetDisplayKey('Coffee / Quick Food'): 20,
      },
    };
    state.refreshAllState();

    final weekly = state.budgetPerformanceForScope(
      const GlobalDashboardScope(),
      periodType: BudgetPeriodType.weekly,
      periodKey: weekKey,
    );
    expect(weekly.totalBudgeted, 60);
    expect(weekly.totalSpent, 65);
    expect(weekly.totalOverspent, 10);

    final custom = state.budgetPerformanceForScope(
      const GlobalDashboardScope(),
      periodType: BudgetPeriodType.custom,
      periodKey: customKey,
    );
    expect(custom.totalBudgeted, 20);
    expect(custom.totalSpent, 25);
    expect(custom.totalOverspent, 5);
  });
}
