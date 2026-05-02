import '../features/accounts/application/account_service.dart';
import '../features/budgets/application/budget_service.dart';
import '../features/categories/application/category_catalog_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/transactions/data/csv_parser.dart';
import '../core/models/models.dart';

typedef StartupDashboardSync =
    void Function({
      required List<Transaction> activeAccountTransactions,
      required List<Transaction> allTransactionsForMetrics,
      required List<Transaction> transactionsForCsvDiagnostics,
      required CsvParseDiagnostics? diag,
    });

class AppStartupService {
  AppStartupService({
    required this.budgetService,
    required this.categoryCatalogService,
    required this.accountService,
    required this.transactionService,
    required this.merchantService,
    required this.spendReference,
    required this.syncDashboardAfterTransactionHydration,
    required this.hydrateLocalProfile,
    required this.userNamespaceForMerchantMemory,
    required this.notifyDashboardAndBudgetsChanged,
    required this.notifyCategoryCatalogChanged,
    required this.notifyAccountsChanged,
    required this.notifyTransactionDataChanged,
    required this.notifyTransactionsChanged,
  });

  final BudgetService budgetService;
  final CategoryCatalogService categoryCatalogService;
  final AccountService accountService;
  final TransactionService transactionService;
  final MerchantService merchantService;
  final DateTime Function() spendReference;
  final StartupDashboardSync syncDashboardAfterTransactionHydration;
  final Future<void> Function() hydrateLocalProfile;
  final String Function() userNamespaceForMerchantMemory;
  final void Function() notifyDashboardAndBudgetsChanged;
  final void Function() notifyCategoryCatalogChanged;
  final void Function() notifyAccountsChanged;
  final void Function() notifyTransactionDataChanged;
  final void Function() notifyTransactionsChanged;

  Future<void> hydrateForStartup() async {
    await hydratePersistedBudgets();
    await hydratePersistedCategoryCatalog();
    await hydratePersistedAccounts();
    await hydratePersistedTransactions();
    await hydrateTransactionCategoryAssignments();
    await hydrateAiCategorySuggestions();
    await dedupePersistedTransactionsIfNeeded();
    await hydrateLocalProfile();
    await hydrateMerchantCategoryMemory();
  }

  Future<void> hydratePersistedBudgets() async {
    await budgetService.hydratePersistedBudgets(reference: spendReference());
    notifyDashboardAndBudgetsChanged();
  }

  Future<void> hydratePersistedCategoryCatalog() async {
    await categoryCatalogService.hydratePersistedCategoryCatalog();
    notifyCategoryCatalogChanged();
  }

  Future<void> hydratePersistedAccounts() async {
    await accountService.hydratePersistedAccounts();
    notifyAccountsChanged();
  }

  Future<void> hydratePersistedTransactions() async {
    final result = await transactionService.hydratePersistedTransactions(
      activeAccountId: accountService.activeAccountId,
    );
    transactionService.transactions = result.activeTransactions;
    syncDashboardAfterTransactionHydration(
      activeAccountTransactions: transactionService.transactions,
      allTransactionsForMetrics: transactionService.allTransactions,
      transactionsForCsvDiagnostics: transactionService.transactions,
      diag: null,
    );
    notifyTransactionDataChanged();
  }

  Future<void> dedupePersistedTransactionsIfNeeded() async {
    final result = await transactionService.dedupePersistedTransactionsIfNeeded(
      activeAccountId: accountService.activeAccountId,
    );
    if (!result.changed) return;

    transactionService.transactions = result.activeTransactions;
    syncDashboardAfterTransactionHydration(
      activeAccountTransactions: transactionService.transactions,
      allTransactionsForMetrics: transactionService.allTransactions,
      transactionsForCsvDiagnostics: transactionService.transactions,
      diag: null,
    );
    notifyTransactionDataChanged();
  }

  Future<void> hydrateMerchantCategoryMemory() async {
    await merchantService.hydrateMerchantCategoryMemory(
      userNamespaceForMerchantMemory(),
    );
    notifyTransactionDataChanged();
  }

  Future<void> hydrateTransactionCategoryAssignments() async {
    await transactionService.hydrateTransactionCategoryAssignments();
    notifyTransactionDataChanged();
  }

  Future<void> hydrateAiCategorySuggestions() async {
    await transactionService.hydrateAiCategorySuggestions();
    notifyTransactionsChanged();
  }
}
