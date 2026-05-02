import '../../../core/models/models.dart';
import '../../accounts/application/account_service.dart';
import '../../categories/application/category_catalog_service.dart';
import '../../profile/application/profile_service.dart';
import 'category_service.dart';
import 'merchant_service.dart';
import 'transaction_service.dart';

class CategoryWorkflowService {
  CategoryWorkflowService({
    required this.categoryService,
    required this.categoryCatalogService,
    required this.transactionService,
    required this.merchantService,
    required this.accountService,
    required this.profileService,
    required this.refreshAllState,
    required this.recomputeDashboard,
    required this.notifyTransactionDataChanged,
  });

  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final TransactionService transactionService;
  final MerchantService merchantService;
  final AccountService accountService;
  final ProfileService profileService;
  final void Function() refreshAllState;
  final TransactionDashboardRecompute recomputeDashboard;
  final void Function() notifyTransactionDataChanged;

  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    return merchantService.applyCategoriesWithMerchantLearning(
      keyToCanonicalCategory,
      allTransactions: transactionService.allTransactions,
      transactionCategoryAssignments:
          transactionService.transactionCategoryAssignments,
      applyCategoryAssignments: _applyCategoryAssignments,
      userNamespace: profileService.userNamespaceForMerchantMemory(),
    );
  }

  void _applyCategoryAssignments(Map<String, String> keyToCanonicalCategory) {
    transactionService.applyCategoryAssignments(
      keyToCanonicalCategory,
      categoryService: categoryService,
    );
    refreshAllState();
  }

  Future<int> undoCategoryApplyBatch(
    List<AiAppliedCategoryChange> batch,
  ) async {
    final undone = await transactionService.undoCategoryApplyBatch(
      batch,
      categoryService: categoryService,
    );
    if (undone == 0) return 0;
    refreshAllState();
    return undone;
  }

  void setCategoryOverride(Transaction transaction, String category) {
    categoryService.setCategoryOverride(
      transaction,
      category,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  void bulkSetCategoryOverrides(Map<String, String> keyToCanonicalCategory) {
    categoryService.bulkSetCategoryOverrides(
      keyToCanonicalCategory,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  void createCategoryAndAssign(Transaction transaction, String rawName) {
    categoryService.createCategoryAndAssign(
      transaction,
      rawName,
      customCategories: categoryCatalogService.customCategories,
      setCustomCategories: (next) {
        categoryCatalogService.customCategories = next;
      },
      persistCategoryCatalog: categoryCatalogService.persistCategoryCatalog,
      setCategoryOverride: setCategoryOverride,
    );
  }

  void deleteCategory(String canonicalLabel) {
    final result = categoryService.deleteCategory(
      canonicalLabel,
      customCategories: categoryCatalogService.customCategories,
      categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
      categoriesHiddenFromPicker:
          categoryCatalogService.categoriesHiddenFromPicker,
      transactionCategoryAssignments:
          transactionService.transactionCategoryAssignments,
      transactions: transactionService.transactions,
    );
    if (result == null) return;

    _applyCategoryMutationResult(result);
    transactionService.persistTransactionCategoryAssignments();
    categoryCatalogService.persistCategoryCatalog();
  }

  void renameCategory(String oldLabel, String newLabel) {
    final result = categoryService.renameCategory(
      oldLabel,
      newLabel,
      customCategories: categoryCatalogService.customCategories,
      categoryDisplayRenames: categoryCatalogService.categoryDisplayRenames,
      categoriesHiddenFromPicker:
          categoryCatalogService.categoriesHiddenFromPicker,
      transactionCategoryAssignments:
          transactionService.transactionCategoryAssignments,
      transactions: transactionService.transactions,
    );
    if (result == null) return;

    _applyCategoryMutationResult(result);
    if (result.shouldPersistActiveAccountTransactions) {
      transactionService.persistTransactionCategoryAssignments();
    }
    categoryCatalogService.persistCategoryCatalog();
  }

  void _applyCategoryMutationResult(CategoryMutationResult result) {
    categoryCatalogService.customCategories = result.customCategories;
    categoryCatalogService.categoryDisplayRenames =
        result.categoryDisplayRenames;
    categoryCatalogService.categoriesHiddenFromPicker =
        result.categoriesHiddenFromPicker;
    transactionService.transactionCategoryAssignments =
        result.transactionCategoryAssignments;
    transactionService.transactions = result.transactions;
    if (result.shouldPersistActiveAccountTransactions) {
      transactionService.persistActiveAccountTransactionsIfAny(
        activeAccountId: accountService.activeAccountId,
        transactions: transactionService.transactions,
      );
    }

    recomputeDashboard(
      activeAccountTransactions: transactionService.transactions,
      allTransactionsForMetrics: transactionService.allTransactions,
      transactionsForCsvDiagnostics: transactionService.transactions,
      diag: null,
    );
    notifyTransactionDataChanged();
  }
}
