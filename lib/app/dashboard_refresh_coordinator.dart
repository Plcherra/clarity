import '../core/models/models.dart';
import '../features/accounts/application/account_service.dart';
import '../features/categories/application/category_catalog_service.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/transactions/data/csv_parser.dart';
import '../features/transactions/domain/transaction_resolution.dart'
    as transaction_resolution;

typedef ResolveTransactionsForDashboard =
    List<transaction_resolution.ResolvedTransaction> Function(
      List<Transaction> txs, {
      required List<Transaction> allTransactionsContext,
    });

/// Coordinates dashboard recomputation from the app service graph.
class DashboardRefreshCoordinator {
  DashboardRefreshCoordinator({
    required this.dashboardService,
    required this.transactionService,
    required this.accountService,
    required this.categoryService,
    required this.categoryCatalogService,
    required this.resolveTransactions,
  });

  final DashboardService dashboardService;
  final TransactionService transactionService;
  final AccountService accountService;
  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final ResolveTransactionsForDashboard resolveTransactions;

  List<Transaction> refreshAllState() {
    final activeTx = dashboardService.refreshAllState(
      activeAccountId: accountService.activeAccountId,
      activeTransactionsForAccount:
          transactionService.activeTransactionsForAccount,
      allTransactionsForMetrics: transactionService.allTransactions,
      accounts: accountService.accounts,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
      resolveTransactions: resolveTransactions,
    );
    transactionService.transactions = activeTx;
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
      resolveTransactions: resolveTransactions,
    );
  }
}
