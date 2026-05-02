import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/storage/migrations/rules_wipe_migration.dart';
import 'app.dart';
import 'app_hydration.dart';
import 'app_state.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  await runRulesWipeMigrationIfNeeded();

  final appState = AppState();
  await hydrateAppStateForStartup(appState);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Clarity][FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
  };

  runApp(ClarityApp(appState: appState));
}
