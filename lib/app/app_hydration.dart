import 'app_state.dart';

/// Hydrates persisted app state in the order required by dependent services.
Future<void> hydrateAppStateForStartup(AppState appState) async {
  await appState.hydratePersistedBudgets();
  await appState.hydratePersistedCategoryCatalog();
  await appState.hydratePersistedAccounts();
  await appState.hydratePersistedTransactions();
  await appState.hydrateTransactionCategoryAssignments();
  await appState.hydrateAiCategorySuggestions();
  await appState.dedupePersistedTransactionsIfNeeded();
  await appState.hydrateLocalProfile();
  await appState.hydrateMerchantCategoryMemory();
}
