import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_composition_test_fixture.dart';
import 'package:clarity/app/app.dart';

void main() {
  testWidgets('First run shows onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = createTestAppComposition();
    await tester.pumpWidget(
      ClarityApp(ui: app.ui, profileController: app.profileController),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Clarity'), findsOneWidget);
  });
}
