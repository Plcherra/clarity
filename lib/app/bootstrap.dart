import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/storage/migrations/rules_wipe_migration.dart';
import 'app.dart';
import 'app_composition.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  await runRulesWipeMigrationIfNeeded();

  final composition = AppComposition();
  await composition.startupService.hydrateForStartup();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Clarity][FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
  };

  runApp(
    ClarityApp(
      ui: composition.ui,
      profileController: composition.profileController,
    ),
  );
}
