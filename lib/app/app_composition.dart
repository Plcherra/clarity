import '../core/models/models.dart';
import '../core/supabase/supabase_repository.dart';
import '../core/supabase/supabase_service.dart';
import '../features/accounts/application/account_workflow_service.dart';
import '../features/accounts/data/account_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_service.dart';
import '../features/budgets/application/budget_workflow_service.dart';
import '../features/budgets/data/budget_service.dart';
import '../features/categories/application/category_read_model.dart';
import '../features/categories/data/category_service.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/application/profile_service.dart';
import '../features/transactions/application/category_workflow_service.dart';
import '../features/transactions/application/import_job_status_service.dart';
import '../features/transactions/application/transaction_workflow_service.dart';
import '../features/transactions/data/csv_import_service.dart';
import '../features/transactions/data/csv_parser.dart';
import '../features/transactions/data/openai_proxy_client.dart';
import '../features/transactions/data/transaction_service.dart';
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

  // Supabase-backed table services. AppComposition no longer constructs
  // local storage category, merchant-memory, or transaction override services.
  late final TransactionService transactionService =
      supabaseRepository.transactions;
  late final CategoryService categoryService = supabaseRepository.categories;

  // Synchronous UI category state derived from the Supabase categories table.
  // This preserves existing picker/controller APIs without local persistence.
  late final CategoryReadModel categoryReadModel = CategoryReadModel(
    categoryService: categoryService,
  );
  late final ProfileService profileService = supabaseRepository.profiles;
  late final BudgetService budgetService = supabaseRepository.budgets;
  late final AccountService accountService = supabaseRepository.accounts;
  final DashboardService dashboardService = DashboardService();
  final ImportJobStatusService importJobStatusService =
      ImportJobStatusService();

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
    syncAfterProfileChanged: () async {
      // No local profile or merchant-memory hydration remains after auth/profile
      // changes; scoped UI controllers only need to refresh their Supabase data.
      notifications.transactionDataChanged();
    },
  );

  late final AppNotifications notifications = AppNotifications(ui: ui);

  late final AccountWorkflowService accountWorkflowService =
      AccountWorkflowService(
        accountService: accountService,
        transactionService: transactionService,
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
    categoryService: categoryService,
    categoryReadModel: categoryReadModel,
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
        categoryReadModel: categoryReadModel,
        notifyTransactionDataChanged: () =>
            notifications.transactionDataChanged(),
      );

  late final CategoryWorkflowService categoryWorkflowService =
      CategoryWorkflowService(
        categoryService: categoryService,
        categoryReadModel: categoryReadModel,
        transactionService: transactionService,
        accountService: accountService,
        profileService: profileService,
        refreshAllState: dashboardRefreshCoordinator.refreshAllState,
        notifyTransactionDataChanged: () =>
            notifications.transactionDataChanged(),
      );

  late final TransactionWorkflowService transactionWorkflowService =
      TransactionWorkflowService(
        transactionService: transactionService,
        csvImportService: csvImportService,
        dashboardService: dashboardService,
        importJobStatusService: importJobStatusService,
        refreshCategories: categoryReadModel.refresh,
        refreshAllState: dashboardRefreshCoordinator.refreshAllState,
        recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
        notifyTransactionDataChanged: () =>
            notifications.transactionDataChanged(),
        notifyImportJobStatusChanged: () =>
            notifications.importJobStatusChanged(),
      );

  late final AppUiDependencies ui = AppUiDependencies(
    AppUiControllerBindings(
      dashboardService: dashboardService,
      transactionService: transactionService,
      categoryService: categoryService,
      categoryWorkflowService: categoryWorkflowService,
      transactionWorkflowService: transactionWorkflowService,
      categoryReadModel: categoryReadModel,
      accountService: accountService,
      budgetService: budgetService,
      budgetWorkflowService: budgetWorkflowService,
      importJobStatusService: importJobStatusService,
      accountWorkflowService: accountWorkflowService,
    ),
  );

  late final OpenAiProxyClient openAiProxyClient = SupabaseOpenAiProxyClient(
    supabaseService: supabaseService,
  );

  late final CsvImportService csvImportService = CsvImportService(
    accountService: accountService,
    transactionService: transactionService,
    categoryService: categoryService,
    openAiClient: openAiProxyClient,
  );

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
    categoryReadModel.dispose();
    ui.dispose();
    authController.dispose();
    profileController.dispose();
  }
}
