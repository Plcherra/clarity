import '../core/models/models.dart';
import '../core/supabase/supabase_repository.dart';
import '../core/supabase/supabase_service.dart';
import '../features/accounts/application/account_service.dart';
import '../features/accounts/application/account_workflow_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_service.dart';
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
import '../features/transactions/data/openai_proxy_client.dart';
import 'app_notifications.dart';
import 'app_startup_service.dart';
import 'dashboard_refresh_coordinator.dart';
import 'ui_dependencies.dart';

final class AppComposition {
  AppComposition({
    SupabaseService? supabaseService,
    bool initialAuthenticated = false,
  }) : supabaseService = supabaseService ?? const SupabaseService(),
       _initialAuthenticated = initialAuthenticated;

  final SupabaseService supabaseService;
  final bool _initialAuthenticated;

  late final SupabaseRepository supabaseRepository = SupabaseRepository(
    supabaseService: supabaseService,
  );

  late final TransactionService transactionService =
      supabaseRepository.transactions;
  final CategoryService categoryService = CategoryService();
  final CategoryCatalogService categoryCatalogService =
      CategoryCatalogService();
  final MerchantService merchantService = MerchantService();
  late final ProfileService profileService = supabaseRepository.profiles;
  late final BudgetService budgetService = supabaseRepository.budgets;
  late final AccountService accountService = supabaseRepository.accounts;
  final DashboardService dashboardService = DashboardService();
  final app_ai.AiCategorizationApplicationService aiCategorizationService =
      app_ai.AiCategorizationApplicationService();

  late final AuthService authService = AuthService(
    supabaseService: supabaseService,
  );

  late final AuthController authController = AuthController(
    authService: authService,
    initialAuthenticated: _initialAuthenticated,
  );

  late final ProfileController profileController = ProfileController(
    profileService: profileService,
    authService: authService,
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
    authService: authService,
    budgetService: budgetService,
    accountService: accountService,
    transactionService: transactionService,
    notifyDashboardAndBudgetsChanged: () =>
        notifications.dashboardAndBudgetsChanged(),
    notifyAccountsChanged: () => notifications.accountsChanged(),
    notifyTransactionDataChanged: () => notifications.transactionDataChanged(),
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
        importAiEngineConfigured: () =>
            openAiProxyClient.isConfigured && authController.isAuthenticated,
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
      importAiEngineConfigured: () =>
          openAiProxyClient.isConfigured && authController.isAuthenticated,
    ),
  );

  late final OpenAiProxyClient openAiProxyClient = SupabaseOpenAiProxyClient(
    supabaseService: supabaseService,
  );

  Future<void> _syncAfterProfileChanged() async {
    await merchantService.hydrateMerchantCategoryMemory(
      _userNamespaceForMerchantMemory(),
    );
    notifications.transactionDataChanged();
  }

  String _userNamespaceForMerchantMemory() {
    return authController.currentUser?.id ?? 'signed-out';
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
    startupService.dispose();
    ui.dispose();
    authController.dispose();
    profileController.dispose();
  }
}
