import 'package:clarity/app/app_state.dart';
import 'package:clarity/core/models/models.dart';
import 'package:clarity/core/storage/budgets/budget_keys.dart';
import 'package:clarity/features/dashboard/presentation/dashboard_screen.dart';
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
  testWidgets('dashboard shows budget insights and refreshes after delete', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 3000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.accounts = const [
      Account(id: 'a', name: 'A', type: AccountType.checking),
      Account(id: 'b', name: 'B', type: AccountType.checking),
    ];
    final ref = state.spendReference;
    final groceryA = _tx(
      date: ref,
      accountId: 'a',
      description: 'Groceries',
      amount: -30,
      categoryId: 'Grocery / Supermarket',
    );
    final shoppingA = _tx(
      date: ref,
      accountId: 'a',
      description: 'Shopping',
      amount: -60,
      categoryId: 'Shopping',
    );
    final groceryB = _tx(
      date: ref,
      accountId: 'b',
      description: 'Groceries',
      amount: -20,
      categoryId: 'Grocery / Supermarket',
    );
    state.transactionsByAccount = {
      'a': [groceryA, shoppingA],
      'b': [groceryB],
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

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(controller: state.ui.dashboard, isRoot: true),
      ),
    );
    await tester.pump();

    expect(find.text('Budget performance'), findsOneWidget);
    expect(find.text('1/2 categories on track'), findsOneWidget);
    expect(find.text('Total overspent \$10.00'), findsOneWidget);

    await state.deleteTransaction(shoppingA);
    await tester.pump();

    expect(find.text('2/2 categories on track'), findsOneWidget);
    expect(find.text('Total overspent \$0.00'), findsOneWidget);
  });
}
