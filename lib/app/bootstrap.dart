import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../app_state.dart';
import '../core/storage/migrations/rules_wipe_migration.dart';
import 'app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  await runRulesWipeMigrationIfNeeded();

  final appState = AppState();
  await appState.hydratePersistedBudgets();
  await appState.hydratePersistedCategoryCatalog();
  await appState.hydratePersistedAccounts();
  await appState.hydratePersistedTransactions();
  await appState.hydrateTransactionCategoryAssignments();
  await appState.hydrateAiCategorySuggestions();
  await appState.dedupePersistedTransactionsIfNeeded();
  await appState.hydrateLocalProfile();
  await appState.hydrateMerchantCategoryMemory();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Clarity][FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
  };

  runApp(ClarityApp(appState: appState));
}

