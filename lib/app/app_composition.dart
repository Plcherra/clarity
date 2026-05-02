import '../core/models/models.dart';
import '../features/accounts/application/account_service.dart';
import '../features/accounts/application/account_workflow_service.dart';
import '../features/budgets/application/budget_service.dart';
import '../features/budgets/application/budget_workflow_service.dart';
import '../features/categories/application/category_catalog_service.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/application/profile_service.dart';
import '../features/transactions/application/ai_categorization_service.dart'
    as app_ai;
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/category_workflow_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/transactions/application/transaction_workflow_service.dart';
import '../features/transactions/data/csv_parser.dart';
import 'app_notifications.dart';
import 'app_startup_service.dart';
import 'dashboard_refresh_coordinator.dart';
import 'ui_dependencies.dart';

final class AppComposition {
  final TransactionService transactionService = TransactionService();
  final CategoryService categoryService = CategoryService();
  final CategoryCatalogService categoryCatalogService =
      CategoryCatalogService();
  final MerchantService merchantService = MerchantService();
  final ProfileService profileService = ProfileService();
  final BudgetService budgetService = BudgetService();
  final AccountService accountService = AccountService();
  final DashboardService dashboardService = DashboardService();
  final app_ai.AiCategorizationApplicationService aiCategorizationService =
      app_ai.AiCategorizationApplicationService();

  late final ProfileController profileController = ProfileController(
    profileService: profileService,
    syncAfterProfileChanged: _syncAfterProfileChanged,
  );

  late final AppNotifications notifications = AppNotifications(ui: ui);

  late final AccountWorkflowService accountWorkflowService =
      AccountWorkflowService(
        accountService: accountService,
        transactionService: transactionService,
        categoryService: categoryService,
        refreshAllState: dashboardRefreshCoordinator.refreshAllState,
        notifyAccountsChanged: () => notifications.accountsChanged(),
      );

  late final BudgetWorkflowService budgetWorkflowService =
      BudgetWorkflowService(
        budgetService: budgetService,
        notifyDashboardAndBudgetsChanged: () =>
            notifications.dashboardAndBudgetsChanged(),
        refreshAllState: dashboardRefreshCoordinator.refreshAllState,
      );

  late final AppStartupService startupService = AppStartupService(
    budgetService: budgetService,
    categoryCatalogService: categoryCatalogService,
    accountService: accountService,
    transactionService: transactionService,
    merchantService: merchantService,
    spendReference: () => dashboardService.spendReference,
    syncDashboardAfterTransactionHydration:
        _syncDashboardAfterTransactionWorkflow,
    hydrateLocalProfile: profileController.hydrateLocalProfile,
    userNamespaceForMerchantMemory:
        profileController.userNamespaceForMerchantMemory,
    notifyDashboardAndBudgetsChanged: () =>
        notifications.dashboardAndBudgetsChanged(),
    notifyCategoryCatalogChanged: () => notifications.categoryCatalogChanged(),
    notifyAccountsChanged: () => notifications.accountsChanged(),
    notifyTransactionDataChanged: () => notifications.transactionDataChanged(),
    notifyTransactionsChanged: () => ui.notifyTransactions(),
  );

  late final DashboardRefreshCoordinator dashboardRefreshCoordinator =
      DashboardRefreshCoordinator(
        dashboardService: dashboardService,
        transactionService: transactionService,
        accountService: accountService,
        categoryService: categoryService,
        categoryCatalogService: categoryCatalogService,
        merchantService: merchantService,
        notifyTransactionDataChanged: () =>
            notifications.transactionDataChanged(),
      );

  late final CategoryWorkflowService categoryWorkflowService =
      CategoryWorkflowService(
        categoryService: categoryService,
        categoryCatalogService: categoryCatalogService,
        transactionService: transactionService,
        merchantService: merchantService,
        accountService: accountService,
        profileService: profileService,
        refreshAllState: dashboardRefreshCoordinator.refreshAllState,
        recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
        notifyTransactionDataChanged: () =>
            notifications.transactionDataChanged(),
      );

  late final TransactionWorkflowService transactionWorkflowService =
      TransactionWorkflowService(
        transactionService: transactionService,
        categoryService: categoryService,
        categoryCatalogService: categoryCatalogService,
        categoryWorkflowService: categoryWorkflowService,
        merchantService: merchantService,
        accountService: accountService,
        dashboardService: dashboardService,
        aiCategorizationService: aiCategorizationService,
        refreshAllState: dashboardRefreshCoordinator.refreshAllState,
        recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
        notifyTransactionDataChanged: () =>
            notifications.transactionDataChanged(),
        notifyImportAiStatusChanged: () =>
            notifications.importAiStatusChanged(),
      );

  late final AppUiDependencies ui = AppUiDependencies(
    AppUiControllerBindings(
      dashboardService: dashboardService,
      transactionService: transactionService,
      categoryService: categoryService,
      categoryWorkflowService: categoryWorkflowService,
      transactionWorkflowService: transactionWorkflowService,
      categoryCatalogService: categoryCatalogService,
      merchantService: merchantService,
      accountService: accountService,
      budgetService: budgetService,
      budgetWorkflowService: budgetWorkflowService,
      aiCategorizationService: aiCategorizationService,
      accountWorkflowService: accountWorkflowService,
    ),
  );

  Future<void> _syncAfterProfileChanged() async {
    await merchantService.hydrateMerchantCategoryMemory(
      profileService.userNamespaceForMerchantMemory(),
    );
    notifications.transactionDataChanged();
  }

  void _syncDashboardAfterTransactionWorkflow({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diag,
  }) {
    dashboardRefreshCoordinator.syncAfterTransactionWorkflow(
      activeAccountTransactions: activeAccountTransactions,
      allTransactionsForMetrics: allTransactionsForMetrics,
      transactionsForCsvDiagnostics: transactionsForCsvDiagnostics,
      diagnostics: diag,
    );
  }

  void dispose() {
    ui.dispose();
    profileController.dispose();
  }
}
