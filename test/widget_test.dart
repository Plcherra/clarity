import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_composition_test_fixture.dart';
import 'package:clarity/app/app.dart';
import 'package:clarity/core/storage/profile/profile_storage.dart';
import 'package:clarity/features/onboarding/presentation/onboarding_screen.dart';
import 'package:clarity/features/shell/presentation/home_shell.dart';

void main() {
  testWidgets('No session shows auth screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = createTestAppComposition();
    await tester.pumpWidget(
      ClarityApp(
        ui: app.ui,
        authController: app.authController,
        profileController: app.profileController,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Clarity'), findsOneWidget);
  });

  testWidgets('Signed-in user without profile sees onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = createTestAppComposition(initialAuthenticated: true);
    await tester.pumpWidget(
      ClarityApp(
        ui: app.ui,
        authController: app.authController,
        profileController: app.profileController,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Clarity'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('Signed-in user with profile sees HomeShell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = createTestAppComposition(initialAuthenticated: true);
    await app.profileController.setLocalProfile(
      LocalProfile(
        displayName: 'Test User',
        createdAtUtcIso: DateTime.utc(2026).toIso8601String(),
      ),
    );
    await tester.pumpWidget(
      ClarityApp(
        ui: app.ui,
        authController: app.authController,
        profileController: app.profileController,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
