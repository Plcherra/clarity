import 'package:clarity/app/app.dart';
import 'package:clarity/app/app_composition.dart';
import 'package:clarity/core/supabase/supabase_records.dart';
import 'package:clarity/features/auth/presentation/auth_screen.dart';
import 'package:clarity/features/onboarding/presentation/onboarding_screen.dart';
import 'package:clarity/features/shell/presentation/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('signed out users see auth screen', (tester) async {
    final app = AppComposition();
    addTearDown(app.dispose);

    await tester.pumpWidget(
      ClarityApp(
        ui: app.ui,
        authController: app.authController,
        profileController: app.profileController,
      ),
    );

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('signed in users without profile see onboarding', (tester) async {
    final app = AppComposition(initialAuthenticated: true);
    addTearDown(app.dispose);

    await tester.pumpWidget(
      ClarityApp(
        ui: app.ui,
        authController: app.authController,
        profileController: app.profileController,
      ),
    );

    expect(find.byType(AuthScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('signed in users with complete profile see home shell', (
    tester,
  ) async {
    final app = AppComposition(initialAuthenticated: true);
    addTearDown(app.dispose);
    app.profileController.profile = ProfileRecord(
      id: 'user-1',
      email: 'test@example.com',
      fullName: 'Test User',
      avatarUrl: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    await tester.pumpWidget(
      ClarityApp(
        ui: app.ui,
        authController: app.authController,
        profileController: app.profileController,
      ),
    );

    expect(find.byType(AuthScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
