import 'helpers/app_composition_test_fixture.dart';
import 'package:clarity/core/storage/profile/profile_storage.dart';
import 'package:clarity/features/onboarding/presentation/onboarding_screen.dart';
import 'package:clarity/features/shell/presentation/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Onboarding navigates to HomeShell after saving profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = createTestAppComposition();

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          saveLocalProfile: state.profileController.setLocalProfile,
          ui: state.ui,
        ),
      ),
    );

    expect(find.text('Welcome to Clarity'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Test User');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(state.profileController.localProfile, isNotNull);
    expect(state.profileController.localProfile!.displayName, 'Test User');
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('HomeShell shows when profile already exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = createTestAppComposition();
    await state.profileController.setLocalProfile(
      LocalProfile(
        displayName: 'Already',
        createdAtUtcIso: DateTime.utc(2026).toIso8601String(),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HomeShell(ui: state.ui)));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    // Dashboard tab is present.
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
