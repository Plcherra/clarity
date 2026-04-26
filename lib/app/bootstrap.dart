import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../app_state.dart';
import 'app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);

  final appState = AppState();
  await appState.hydratePersistedBudgets();
  await appState.hydrateCategoryRules();
  await appState.hydratePersistedCategoryCatalog();
  await appState.hydratePersistedAccounts();
  await appState.hydratePersistedTransactions();
  await appState.hydrateTransactionCategoryAssignments();
  await appState.hydrateAiCategorySuggestions();
  await appState.dedupePersistedTransactionsIfNeeded();
  await appState.hydrateLocalProfile();

  runApp(ClarityApp(appState: appState));
}

