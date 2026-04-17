import 'dart:io';

import 'package:clarity/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Imports the real bank CSV from Downloads (same path used for local debugging).
/// Run: `flutter test test/debug_stmt_real_csv_test.dart --reporter expanded`
void main() {
  test('debug: import real stmt.csv from Downloads', () async {
    final path =
        Platform.environment['CLARITY_STMT_CSV'] ??
        '/Users/pedromartins/Downloads/stmt.csv';
    final file = File(path);
    if (!await file.exists()) {
      fail('Missing CSV at $path — set CLARITY_STMT_CSV or add stmt.csv');
    }
    final text = await file.readAsString();
    AppState().loadFromCsv(text, reference: DateTime(2025, 1, 15));
  });
}
