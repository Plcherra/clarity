import 'package:clarity/app_state.dart';
import 'package:clarity/models.dart';
import 'package:clarity/screens/account_detail_screen.dart';
import 'package:clarity/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Account detail shows + Upload Transactions', (tester) async {
    final state = AppState()
      ..accounts = [
        const Account(
          id: 'a1',
          name: 'Bank of America Checking',
          type: AccountType.checking,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailScreen(appState: state, accountId: 'a1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ Upload Transactions'), findsOneWidget);
  });

  testWidgets('Global overview does not show + Upload Transactions', (
    tester,
  ) async {
    final state = AppState()
      ..accounts = [
        const Account(
          id: 'a1',
          name: 'Bank of America Checking',
          type: AccountType.checking,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(appState: state, isRoot: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ Upload Transactions'), findsNothing);
  });
}
