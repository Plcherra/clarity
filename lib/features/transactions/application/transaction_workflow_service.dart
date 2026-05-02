import '../../../core/constants/constants.dart';
import '../../../core/models/models.dart';
import '../../accounts/application/account_service.dart';
import '../../categories/application/category_catalog_service.dart';
import '../../dashboard/application/dashboard_service.dart';
import '../data/ai_categorization_service.dart' as data_ai;
import 'ai_categorization_service.dart' as app_ai;
import 'category_service.dart';
import 'category_workflow_service.dart';
import 'merchant_service.dart';
import 'transaction_service.dart';

class TransactionWorkflowService {
  TransactionWorkflowService({
    required this.transactionService,
    required this.categoryService,
    required this.categoryCatalogService,
    required this.categoryWorkflowService,
    required this.merchantService,
    required this.accountService,
    required this.dashboardService,
    required this.aiCategorizationService,
    required this.refreshAllState,
    required this.recomputeDashboard,
    required this.notifyTransactionDataChanged,
    required this.notifyImportAiStatusChanged,
  });

  final TransactionService transactionService;
  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final CategoryWorkflowService categoryWorkflowService;
  final MerchantService merchantService;
  final AccountService accountService;
  final DashboardService dashboardService;
  final app_ai.AiCategorizationApplicationService aiCategorizationService;
  final void Function() refreshAllState;
  final TransactionDashboardRecompute recomputeDashboard;
  final void Function() notifyTransactionDataChanged;
  final void Function() notifyImportAiStatusChanged;

  void loadFromCsv(
    String utf8Text, {
    required String accountId,
    DateTime? reference,
  }) {
    final result = transactionService.loadFromCsv(
      utf8Text,
      accountId: accountId,
      reference: reference,
      accounts: accountService.accounts,
      categoryService: categoryService,
    );
    dashboardService.spendReference = result.spendReference;
    accountService.activeAccountId = result.activeAccountId;
    dashboardService.totalBalance = result.totalBalance;
    recomputeDashboard(
      activeAccountTransactions: transactionService.transactions,
      allTransactionsForMetrics: transactionService.allTransactions,
      transactionsForCsvDiagnostics: transactionService.transactions,
      diag: result.diagnostics,
    );
    notifyTransactionDataChanged();
    categoryCatalogService.persistCategoryCatalog();
  }

  Future<bool> deleteTransaction(Transaction transaction) async {
    final result = await transactionService.deleteTransaction(
      transaction,
      categoryService: categoryService,
    );
    if (!result.success) return false;
    refreshAllState();
    return true;
  }

  Future<int> clearTransactionsForAccount(String accountId) async {
    final result = await transactionService.clearTransactionsForAccount(
      accountId,
      categoryService: categoryService,
    );
    if (!result.success) return 0;
    refreshAllState();
    return result.removedCount;
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    final result = await transactionService.deleteTransactionsForImportBatch(
      accountId: accountId,
      importId: importId,
      categoryService: categoryService,
    );
    if (!result.success) return 0;
    refreshAllState();
    return result.removedCount;
  }

  bool needsImportAiAfterCsvUpload(String accountId) {
    return aiCategorizationService.needsImportAiAfterCsvUpload(
      accountId,
      uncategorizedImportedRowsForAccount: (accountId) {
        return transactionService.uncategorizedImportedRowsForAccount(
          accountId,
          categoryService: categoryService,
          categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
        );
      },
    );
  }

  Future<void> startBackgroundImportAiCategorization(String accountId) {
    return aiCategorizationService.startBackgroundImportAiCategorization(
      accountId,
      importAiEngineConfigured: Constants.openAIKey.isNotEmpty,
      uncategorizedImportedRowsForAccount: (accountId) {
        return transactionService.uncategorizedImportedRowsForAccount(
          accountId,
          categoryService: categoryService,
          categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
        );
      },
      merchantCategoryMemory: merchantService.merchantCategoryMemory,
      applyPrefilledMerchantChunks: (prefilled) {
        return merchantService.applyPrefilledMerchantChunks(
          prefilled,
          applyCategoriesWithMerchantLearning:
              categoryWorkflowService.applyCategoriesWithMerchantLearning,
        );
      },
      allowedCategoryPickerLabels:
          categoryCatalogService.allowedCategoryPickerLabels,
      applyCategoriesWithMerchantLearning:
          categoryWorkflowService.applyCategoriesWithMerchantLearning,
      notifyStatusChanged: notifyImportAiStatusChanged,
    );
  }

  Future<({int applied, int queuedForReview})>
  autoCategorizeGlobalUncategorized({
    required data_ai.AICategorizationService service,
    double autoApplyConfidenceThreshold = 0.90,
  }) {
    return aiCategorizationService.autoCategorizeGlobalUncategorized(
      service: service,
      allowedCategoryPickerLabels:
          categoryCatalogService.allowedCategoryPickerLabels,
      uncategorizedImportedRowsGlobal: transactionService
          .uncategorizedImportedRowsGlobal(
            accounts: accountService.accounts,
            categoryService: categoryService,
            categoryDisplayRenames:
                categoryCatalogService.categoryDisplayRenames,
          ),
      transactionCategoryAssignments:
          transactionService.transactionCategoryAssignments,
      aiCategorySuggestions: transactionService.aiCategorySuggestions,
      setAiCategorySuggestions: (next) {
        transactionService.aiCategorySuggestions = next;
      },
      persistAiCategorySuggestions:
          transactionService.persistAiCategorySuggestions,
      bulkSetCategoryOverrides:
          categoryWorkflowService.bulkSetCategoryOverrides,
      autoApplyConfidenceThreshold: autoApplyConfidenceThreshold,
    );
  }

  Future<int> undoLastAiAutoApply() async {
    final result = await aiCategorizationService.undoLastAiAutoApply(
      transactionCategoryAssignments:
          transactionService.transactionCategoryAssignments,
      categoryOverrides: categoryService.categoryOverrides,
      transactionsByAccount: transactionService.transactionsByAccount,
      activeAccountId: accountService.activeAccountId,
    );
    if (result.undone == 0) return 0;

    transactionService.applyAiAutoApplyUndoResult(
      result,
      categoryService: categoryService,
    );
    recomputeDashboard(
      activeAccountTransactions: transactionService.transactions,
      allTransactionsForMetrics: transactionService.allTransactions,
      transactionsForCsvDiagnostics: transactionService.transactions,
      diag: null,
    );
    notifyTransactionDataChanged();
    return result.undone;
  }
}
