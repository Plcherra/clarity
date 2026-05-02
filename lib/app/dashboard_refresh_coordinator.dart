import '../core/models/models.dart';
import '../features/accounts/application/account_service.dart';
import '../features/categories/application/category_catalog_service.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/transactions/data/csv_parser.dart';
import '../features/transactions/domain/transaction_resolution.dart' as tx_res;

/// Coordinates dashboard recomputation from the app service graph.
class DashboardRefreshCoordinator {
  DashboardRefreshCoordinator({
    required this.dashboardService,
    required this.transactionService,
    required this.accountService,
    required this.categoryService,
    required this.categoryCatalogService,
    required this.merchantService,
    required this.notifyTransactionDataChanged,
  });

  final DashboardService dashboardService;
  final TransactionService transactionService;
  final AccountService accountService;
  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final MerchantService merchantService;
  final void Function() notifyTransactionDataChanged;

  List<tx_res.ResolvedTransaction> _resolveTransactions(
    List<Transaction> txs, {
    required List<Transaction> allTransactionsContext,
  }) {
    return transactionService.resolveTransactions(
      txs,
      categoryService: categoryService,
      categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
      merchantCategoryMemory: merchantService.merchantCategoryMemory,
      accounts: accountService.accounts,
      allTransactionsContext: allTransactionsContext,
    );
  }

  List<Transaction> refreshAllState() {
    final activeTx = dashboardService.refreshAllState(
      activeAccountId: accountService.activeAccountId,
      activeTransactionsForAccount:
          transactionService.activeTransactionsForAccount,
      allTransactionsForMetrics: transactionService.allTransactions,
      accounts: accountService.accounts,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
      resolveTransactions: _resolveTransactions,
    );
    transactionService.transactions = activeTx;
    notifyTransactionDataChanged();
    return activeTx;
  }

  void syncAfterTransactionWorkflow({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diagnostics,
  }) {
    dashboardService.recomputeDerivedState(
      activeAccountTransactions: activeAccountTransactions,
      allTransactionsForMetrics: allTransactionsForMetrics,
      transactionsForCsvDiagnostics: transactionsForCsvDiagnostics,
      diag: diagnostics,
      accounts: accountService.accounts,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
      resolveTransactions: _resolveTransactions,
    );
  }
}
