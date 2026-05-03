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
    required this.notifyTransactionDataChanged,
  });

  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final TransactionService transactionService;
  final MerchantService merchantService;
  final AccountService accountService;
  final ProfileService profileService;
  final Future<void> Function() refreshAllState;
  final void Function() notifyTransactionDataChanged;

  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    return const [];
  }

  Future<int> undoCategoryApplyBatch(
    List<AiAppliedCategoryChange> batch,
  ) async {
    return 0;
  }

  Future<void> setCategoryOverride(
    Transaction transaction,
    String category,
  ) async {
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> bulkSetCategoryOverrides(
    Map<String, String> keyToCanonicalCategory,
  ) async {
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> createCategoryAndAssign(
    Transaction transaction,
    String rawName,
  ) async {
    final name = rawName.trim();
    if (name.isEmpty || name.toLowerCase() == 'uncategorized') return;
    if (!categoryCatalogService.customCategories.contains(name)) {
      categoryCatalogService.customCategories = [
        ...categoryCatalogService.customCategories,
        name,
      ];
      categoryCatalogService.persistCategoryCatalog();
    }
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> deleteCategory(String canonicalLabel) async {
    final key = canonicalLabel.trim().toLowerCase();
    if (key.isEmpty) return;
    categoryCatalogService.customCategories = categoryCatalogService
        .customCategories
        .where((category) => category.trim().toLowerCase() != key)
        .toList();
    categoryCatalogService.categoryDisplayRenames = {
      ...categoryCatalogService.categoryDisplayRenames,
    }..remove(key);
    categoryCatalogService.categoriesHiddenFromPicker = {
      ...categoryCatalogService.categoriesHiddenFromPicker,
      key,
    };
    categoryCatalogService.persistCategoryCatalog();
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> renameCategory(String oldLabel, String newLabel) async {
    final oldKey = oldLabel.trim().toLowerCase();
    final next = newLabel.trim();
    if (oldKey.isEmpty || next.isEmpty) return;
    categoryCatalogService.customCategories = [
      for (final category in categoryCatalogService.customCategories)
        if (category.trim().toLowerCase() == oldKey) next else category,
    ];
    categoryCatalogService.categoryDisplayRenames = {
      ...categoryCatalogService.categoryDisplayRenames,
      oldKey: next,
    };
    categoryCatalogService.persistCategoryCatalog();
    await refreshAllState();
    notifyTransactionDataChanged();
  }
}
