import 'package:flutter_test/flutter_test.dart';

import 'package:clarity/app_state.dart';
import 'package:clarity/main.dart';

void main() {
  testWidgets('Upload screen shows import button', (tester) async {
    await tester.pumpWidget(ClarityApp(appState: AppState()));
    expect(find.text('Import Bank Statement (CSV only)'), findsOneWidget);
  });
}
