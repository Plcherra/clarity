import 'dart:io';

import 'package:clarity/app/app_state.dart';
import 'package:clarity/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs import so [AppState] emits kDebugMode CSV diagnostics to the console.
/// Run:
/// `CLARITY_RUN_DEBUG_CSV_TESTS=1 flutter test test/debug_csv_import_print_test.dart --reporter expanded`
void main() {
  final runDebugCsvTests =
      Platform.environment['CLARITY_RUN_DEBUG_CSV_TESTS'] == '1';

  test(
    'debug: print CSV import diagnostics (sample CSV)',
    () {
      const csv = '''
Date,Description,Amount
2025-01-01,Alpha,-1.00
2025-01-15,Beta,-2.00
2025-01-31,Gamma,-3.00
2026-12-31,Odd future row,-9.00
''';
      final state = AppState();
      state.accounts = [
        Account(id: 'debug', name: 'Debug', type: AccountType.checking),
      ];
      state.loadFromCsv(
        csv,
        accountId: 'debug',
        reference: DateTime(2025, 1, 15),
      );
    },
    skip: runDebugCsvTests ? false : 'Set CLARITY_RUN_DEBUG_CSV_TESTS=1.',
  );
}
