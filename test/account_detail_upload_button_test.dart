import 'helpers/app_composition_test_fixture.dart';
import 'package:clarity/core/models/models.dart';
import 'package:clarity/features/accounts/presentation/account_detail_screen.dart';
import 'package:clarity/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Account detail shows + Upload Transactions', (tester) async {
    final state = createTestAppComposition();
    state.accountService.accounts = [
      const Account(
        id: 'a1',
        name: 'Bank of America Checking',
        type: AccountType.checking,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailScreen(
          controller: state.ui.accounts,
          accountId: 'a1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ Upload Transactions'), findsOneWidget);
  });

  testWidgets('Global overview does not show + Upload Transactions', (
    tester,
  ) async {
    final state = createTestAppComposition();
    state.accountService.accounts = [
      const Account(
        id: 'a1',
        name: 'Bank of America Checking',
        type: AccountType.checking,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(controller: state.ui.dashboard, isRoot: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ Upload Transactions'), findsNothing);
  });
}
