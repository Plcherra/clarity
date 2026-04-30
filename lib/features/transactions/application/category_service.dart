import '../../../core/models/models.dart';
import '../../categories/application/category_catalog_service.dart';
import '../domain/spend_categories.dart';
import 'transaction_service.dart';

class CategoryMutationResult {
  const CategoryMutationResult({
    required this.customCategories,
    required this.categoryDisplayRenames,
    required this.categoriesHiddenFromPicker,
    required this.transactionCategoryAssignments,
    required this.transactions,
    required this.shouldPersistActiveAccountTransactions,
  });

  final List<String> customCategories;
  final Map<String, String> categoryDisplayRenames;
  final Set<String> categoriesHiddenFromPicker;
  final Map<String, String> transactionCategoryAssignments;
  final List<Transaction> transactions;
  final bool shouldPersistActiveAccountTransactions;
}

class CategoryService {
  /// Manual category by [transactionCategoryKey]; cleared when a new CSV is loaded.
  Map<String, String> categoryOverrides = const {};

  /// Assigns a category to a transaction and refreshes aggregates.
  void setCategoryOverride(
    Transaction t,
    String category, {
    required void Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
  }) {
    final key = transactionCategoryKey(t);
    final cat = category.trim();
    applyCategoriesWithMerchantLearning({key: cat});
  }

  void setCategoryOverrideWorkflow(
    Transaction t,
    String category, {
    required void Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
  }) {
    setCategoryOverride(
      t,
      category,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Assigns categories for many [transactionCategoryKey]s at once.
  void bulkSetCategoryOverrides(
    Map<String, String> keyToCanonicalCategory, {
    required void Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
  }) {
    applyCategoriesWithMerchantLearning(keyToCanonicalCategory);
  }

  void bulkSetCategoryOverridesWorkflow(
    Map<String, String> keyToCanonicalCategory, {
    required void Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
  }) {
    bulkSetCategoryOverrides(
      keyToCanonicalCategory,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Adds a new category name (if needed), assigns [t], and persists catalog changes.
  void createCategoryAndAssign(
    Transaction t,
    String rawName, {
    required List<String> customCategories,
    required void Function(List<String>) setCustomCategories,
    required void Function() persistCategoryCatalog,
    required void Function(Transaction, String) setCategoryOverride,
  }) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    if (name.toLowerCase() == 'uncategorized') return;
    if (isIgnoredCategoryLabel(name)) return;
    if (!isBuiltInSpendCategory(name) && !customCategories.contains(name)) {
      setCustomCategories([...customCategories, name]);
      persistCategoryCatalog();
    }
    setCategoryOverride(t, name);
  }

  void createCategoryAndAssignWorkflow(
    Transaction t,
    String rawName, {
    required CategoryCatalogService categoryCatalogService,
    required void Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
  }) {
    createCategoryAndAssign(
      t,
      rawName,
      customCategories: categoryCatalogService.customCategories,
      setCustomCategories: (next) {
        categoryCatalogService.customCategories = next;
      },
      persistCategoryCatalog: categoryCatalogService.persistCategoryCatalog,
      setCategoryOverride: (transaction, category) {
        setCategoryOverrideWorkflow(
          transaction,
          category,
          applyCategoriesWithMerchantLearning:
              applyCategoriesWithMerchantLearning,
        );
      },
    );
  }

  /// Deletes a category from the picker and clears assignments using it.
  CategoryMutationResult? deleteCategory(
    String canonicalLabel, {
    required List<String> customCategories,
    required Map<String, String> categoryDisplayRenames,
    required Set<String> categoriesHiddenFromPicker,
    required Map<String, String> transactionCategoryAssignments,
    required List<Transaction> transactions,
  }) {
    final k = canonicalLabel.trim().toLowerCase();
    if (k.isEmpty) return null;

    final nextCustomCategories = customCategories
        .where((c) => c.trim().toLowerCase() != k)
        .toList();

    var nextHidden = categoriesHiddenFromPicker;
    if (kSelectableSpendCategories.any((c) => c.toLowerCase() == k)) {
      nextHidden = {...categoriesHiddenFromPicker, k};
    }

    final nextRenames = Map<String, String>.from(categoryDisplayRenames);
    nextRenames.remove(k);

    final nextOverrides = <String, String>{};
    for (final e in categoryOverrides.entries) {
      if (e.value.trim().toLowerCase() != k) {
        nextOverrides[e.key] = e.value;
      }
    }
    categoryOverrides = nextOverrides;

    final nextAssignments = <String, String>{};
    for (final e in transactionCategoryAssignments.entries) {
      if (e.value.trim().toLowerCase() != k) {
        nextAssignments[e.key] = e.value;
      }
    }

    final nextTransactions = List<Transaction>.unmodifiable(
      transactions.map((x) {
        final cid = x.categoryId?.trim();
        if (cid != null && cid.toLowerCase() == k) {
          return Transaction(
            date: x.date,
            description: x.description,
            amount: x.amount,
            accountId: x.accountId,
            category: x.category,
            balanceAfter: x.balanceAfter,
            categoryId: null,
            importId: x.importId,
            fingerprint: x.fingerprint,
            financialRole: x.financialRole,
          );
        }
        return x;
      }).toList(),
    );

    return CategoryMutationResult(
      customCategories: nextCustomCategories,
      categoryDisplayRenames: nextRenames,
      categoriesHiddenFromPicker: nextHidden,
      transactionCategoryAssignments: nextAssignments,
      transactions: nextTransactions,
      shouldPersistActiveAccountTransactions: true,
    );
  }

  void deleteCategoryWorkflow(
    String canonicalLabel, {
    required CategoryCatalogService categoryCatalogService,
    required TransactionService transactionService,
    required String? activeAccountId,
    required TransactionDashboardRecompute recomputeDashboard,
    required void Function() notifyListeners,
  }) {
    final result = deleteCategory(
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

    _applyCategoryMutationResult(
      result,
      categoryCatalogService: categoryCatalogService,
      transactionService: transactionService,
      activeAccountId: activeAccountId,
      recomputeDashboard: recomputeDashboard,
      notifyListeners: notifyListeners,
    );
    transactionService.persistTransactionCategoryAssignments();
    categoryCatalogService.persistCategoryCatalog();
  }

  /// Renames a category. Built-ins are display-only; custom categories update assignments.
  CategoryMutationResult? renameCategory(
    String oldLabel,
    String newLabel, {
    required List<String> customCategories,
    required Map<String, String> categoryDisplayRenames,
    required Set<String> categoriesHiddenFromPicker,
    required Map<String, String> transactionCategoryAssignments,
    required List<Transaction> transactions,
  }) {
    final oldK = oldLabel.trim().toLowerCase();
    final newN = newLabel.trim();
    if (newN.isEmpty || oldK == newN.toLowerCase()) return null;

    final isBuiltIn = kSelectableSpendCategories.any(
      (c) => c.toLowerCase() == oldK,
    );
    if (isBuiltIn) {
      return CategoryMutationResult(
        customCategories: customCategories,
        categoryDisplayRenames: {...categoryDisplayRenames, oldK: newN},
        categoriesHiddenFromPicker: categoriesHiddenFromPicker,
        transactionCategoryAssignments: transactionCategoryAssignments,
        transactions: transactions,
        shouldPersistActiveAccountTransactions: false,
      );
    }

    final nextOverrides = <String, String>{};
    for (final e in categoryOverrides.entries) {
      if (e.value.trim().toLowerCase() == oldK) {
        nextOverrides[e.key] = newN;
      } else {
        nextOverrides[e.key] = e.value;
      }
    }
    categoryOverrides = nextOverrides;

    final nextAssignments = <String, String>{};
    for (final e in transactionCategoryAssignments.entries) {
      if (e.value.trim().toLowerCase() == oldK) {
        nextAssignments[e.key] = newN;
      } else {
        nextAssignments[e.key] = e.value;
      }
    }

    final nextCustomCategories = customCategories
        .map((c) => c.trim().toLowerCase() == oldK ? newN : c)
        .toList();

    final nextTransactions = List<Transaction>.unmodifiable(
      transactions.map((x) {
        final cid = x.categoryId?.trim();
        if (cid != null && cid.toLowerCase() == oldK) {
          return Transaction(
            date: x.date,
            description: x.description,
            amount: x.amount,
            accountId: x.accountId,
            category: x.category,
            balanceAfter: x.balanceAfter,
            categoryId: newN,
            importId: x.importId,
            fingerprint: x.fingerprint,
            financialRole: x.financialRole,
          );
        }
        return x;
      }).toList(),
    );

    return CategoryMutationResult(
      customCategories: nextCustomCategories,
      categoryDisplayRenames: categoryDisplayRenames,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
      transactionCategoryAssignments: nextAssignments,
      transactions: nextTransactions,
      shouldPersistActiveAccountTransactions: true,
    );
  }

  void renameCategoryWorkflow(
    String oldLabel,
    String newLabel, {
    required CategoryCatalogService categoryCatalogService,
    required TransactionService transactionService,
    required String? activeAccountId,
    required TransactionDashboardRecompute recomputeDashboard,
    required void Function() notifyListeners,
  }) {
    final result = renameCategory(
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

    _applyCategoryMutationResult(
      result,
      categoryCatalogService: categoryCatalogService,
      transactionService: transactionService,
      activeAccountId: activeAccountId,
      recomputeDashboard: recomputeDashboard,
      notifyListeners: notifyListeners,
    );
    if (result.shouldPersistActiveAccountTransactions) {
      transactionService.persistTransactionCategoryAssignments();
    }
    categoryCatalogService.persistCategoryCatalog();
  }

  void _applyCategoryMutationResult(
    CategoryMutationResult result, {
    required CategoryCatalogService categoryCatalogService,
    required TransactionService transactionService,
    required String? activeAccountId,
    required TransactionDashboardRecompute recomputeDashboard,
    required void Function() notifyListeners,
  }) {
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
        activeAccountId: activeAccountId,
        transactions: transactionService.transactions,
      );
    }

    recomputeDashboard(
      activeAccountTransactions: transactionService.transactions,
      allTransactionsForMetrics: transactionService.allTransactions,
      transactionsForCsvDiagnostics: transactionService.transactions,
      diag: null,
    );
    notifyListeners();
  }
}
