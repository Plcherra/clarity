import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clarity/app_state.dart';
import 'package:clarity/main.dart';

void main() {
  testWidgets('First run shows onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ClarityApp(appState: AppState()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Clarity'), findsOneWidget);
  });
}
