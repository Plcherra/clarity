import 'package:clarity/app/app_state.dart';
import 'package:clarity/core/models/models.dart';
import 'package:clarity/core/storage/budgets/budget_keys.dart';
import 'package:clarity/features/budgets/presentation/budgets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Transaction _tx({
  required DateTime date,
  required String accountId,
  required String description,
  required double amount,
  required String categoryId,
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
  testWidgets(
    'Budgets screen shows remaining and overspent from actual transactions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      state.accounts = const [
        Account(id: 'a', name: 'A', type: AccountType.checking),
      ];
      final ref = state.spendReference;
      final grocery = _tx(
        date: ref,
        accountId: 'a',
        description: 'Market',
        amount: -30,
        categoryId: 'Grocery / Supermarket',
      );
      final shopping = _tx(
        date: ref,
        accountId: 'a',
        description: 'Mall',
        amount: -60,
        categoryId: 'Shopping',
      );
      state.transactionsByAccount = {
        'a': [grocery, shopping],
      };
      state.activeAccountId = 'a';
      final month = state.activeBudgetYearMonth;
      state.budgetService.repository.categoryMonthlyBudgetsByYearMonth = {
        month: {
          budgetDisplayKey('Grocery / Supermarket'): 100,
          budgetDisplayKey('Shopping'): 50,
        },
      };
      state.refreshAllState();

      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(800, 3000));

      await tester.pumpWidget(
        MaterialApp(home: BudgetsScreen(controller: state.ui.budgets)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spent \$30.00 · Left \$70.00'), findsOneWidget);
      expect(find.text('Spent \$60.00 · Over \$10.00'), findsOneWidget);
    },
  );

  testWidgets('Budgets screen updates after transaction and account deletes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.accounts = const [
      Account(id: 'a', name: 'A', type: AccountType.checking),
    ];
    final ref = state.spendReference;
    final grocery = _tx(
      date: ref,
      accountId: 'a',
      description: 'Market',
      amount: -30,
      categoryId: 'Grocery / Supermarket',
    );
    state.transactionsByAccount = {
      'a': [grocery],
    };
    state.activeAccountId = 'a';
    final month = state.activeBudgetYearMonth;
    state.budgetService.repository.categoryMonthlyBudgetsByYearMonth = {
      month: {budgetDisplayKey('Grocery / Supermarket'): 100},
    };
    state.refreshAllState();

    await tester.pumpWidget(
      MaterialApp(home: BudgetsScreen(controller: state.ui.budgets)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spent \$30.00 · Left \$70.00'), findsOneWidget);

    await state.deleteTransaction(grocery);
    await tester.pumpAndSettle();
    expect(find.text('Spent \$0.00 · Left \$100.00'), findsOneWidget);

    state.transactionsByAccount = {
      'a': [grocery],
    };
    state.refreshAllState();
    await tester.pump();
    expect(find.text('Spent \$30.00 · Left \$70.00'), findsOneWidget);

    await state.deleteAccount('a');
    await tester.pump();
    expect(find.text('Spent \$0.00 · Left \$100.00'), findsOneWidget);
  });
}
