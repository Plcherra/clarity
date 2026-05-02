import 'dart:io';

import 'package:clarity/app/app_state.dart';
import 'package:clarity/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Imports the real bank CSV from Downloads (same path used for local debugging).
/// Run:
/// `CLARITY_RUN_DEBUG_CSV_TESTS=1 flutter test test/debug_stmt_real_csv_test.dart --reporter expanded`
void main() {
  final runDebugCsvTests =
      Platform.environment['CLARITY_RUN_DEBUG_CSV_TESTS'] == '1';

  test(
    'debug: import real stmt.csv from Downloads',
    () async {
      final path =
          Platform.environment['CLARITY_STMT_CSV'] ??
          '/Users/pedromartins/Downloads/stmt.csv';
      final file = File(path);
      if (!await file.exists()) {
        fail('Missing CSV at $path — set CLARITY_STMT_CSV or add stmt.csv');
      }
      final text = await file.readAsString();
      final state = AppState();
      state.accounts = [
        Account(id: 'debug', name: 'Debug', type: AccountType.checking),
      ];
      state.loadFromCsv(
        text,
        accountId: 'debug',
        reference: DateTime(2025, 1, 15),
      );
    },
    skip: runDebugCsvTests ? false : 'Set CLARITY_RUN_DEBUG_CSV_TESTS=1.',
  );
}
