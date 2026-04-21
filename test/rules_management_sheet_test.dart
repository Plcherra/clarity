import 'package:clarity/app_state.dart';
import 'package:clarity/screens/rules_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('New Rule sheet opens, closes, and reopens without error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RulesManagementScreen(appState: AppState()),
      ),
    );
    await tester.tap(find.text('New Rule'));
    await tester.pumpAndSettle();
    expect(find.text('New rule'), findsOneWidget);

    final ctx = tester.element(find.text('New rule'));
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Rule'));
    await tester.pumpAndSettle();
    expect(find.text('New rule'), findsOneWidget);
  });
}
