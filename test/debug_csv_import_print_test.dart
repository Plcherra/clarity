import 'package:clarity/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs import so [AppState] emits kDebugMode CSV diagnostics to the console.
/// Run: `flutter test test/debug_csv_import_print_test.dart --reporter expanded`
void main() {
  test('debug: print CSV import diagnostics (sample CSV)', () {
    const csv = '''
Date,Description,Amount
2025-01-01,Alpha,-1.00
2025-01-15,Beta,-2.00
2025-01-31,Gamma,-3.00
2026-12-31,Odd future row,-9.00
''';
    AppState().loadFromCsv(csv, reference: DateTime(2025, 1, 15));
  });
}
