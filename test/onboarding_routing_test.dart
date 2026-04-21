import 'package:clarity/app_state.dart';
import 'package:clarity/profile_storage.dart';
import 'package:clarity/screens/home_shell.dart';
import 'package:clarity/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Onboarding navigates to HomeShell after saving profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();

    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(appState: state)),
    );

    expect(find.text('Welcome to Clarity'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Test User');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(state.localProfile, isNotNull);
    expect(state.localProfile!.displayName, 'Test User');
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('HomeShell shows when profile already exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.setLocalProfile(
      LocalProfile(
        displayName: 'Already',
        createdAtUtcIso: DateTime.utc(2026).toIso8601String(),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HomeShell(appState: state)));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    // Dashboard tab is present.
    expect(find.text('Dashboard'), findsOneWidget);
  });
}

