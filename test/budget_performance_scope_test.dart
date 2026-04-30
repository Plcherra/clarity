import 'package:clarity/app/app_state.dart';
import 'package:clarity/features/budgets/application/budget_performance.dart';
import 'package:clarity/features/budgets/domain/budget_models.dart';
import 'package:clarity/core/models/models.dart';
import 'package:clarity/core/storage/budgets/budget_keys.dart';
import 'package:clarity/features/dashboard/domain/dashboard_snapshot.dart';
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
    state.budgets.categoryMonthlyBudgetsByYearMonth = {
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
    final weekStart = DateTime(2026, 4, 8); // Wednesday start, user-selected.
    state.transactionsByAccount = {
      'a': [
        _tx(
          accountId: 'a',
          description: 'Coffee',
          amount: -25,
          categoryId: 'Coffee / Quick Food',
          date: weekStart,
        ),
        _tx(
          accountId: 'a',
          description: 'Transport',
          amount: -40,
          categoryId: 'Transportation',
          date: weekStart.add(const Duration(days: 2)),
        ),
        // Must NOT be included in the selected weekly range when start date is exact.
        _tx(
          accountId: 'a',
          description: 'Before selected week',
          amount: -7,
          categoryId: 'Transportation',
          date: weekStart.subtract(const Duration(days: 1)),
        ),
      ],
    };
    final weekKey = state.budgetWeekStartKey(weekStart);
    state.budgets.categoryWeeklyBudgetsByWeekStart = {
      weekKey: {
        budgetDisplayKey('Coffee / Quick Food'): 30,
        budgetDisplayKey('Transportation'): 30,
      },
    };
    final customKey = state.ensureCustomBudgetPeriod(
      weekStart,
      weekStart.add(const Duration(days: 2)),
    );
    state.budgets.categoryCustomBudgetsByKey = {
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
