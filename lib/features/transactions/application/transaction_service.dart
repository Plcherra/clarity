import '../../../core/models/models.dart';
import '../../../core/storage/ai/ai_suggestion_storage.dart';
import '../../../core/storage/transactions/transaction_category_storage.dart';
import '../../../core/storage/transactions/transaction_storage.dart';
import '../data/csv_import_service.dart';
import '../data/transaction_repository.dart';
import '../domain/spend_categories.dart';
import '../domain/transaction_resolution.dart' as transaction_resolution;
import 'ai_categorization_service.dart' as app_ai;
import 'category_service.dart';

class TransactionService {
  final TransactionRepository transactionRepository = TransactionRepository();
  final CsvImportService csvImportService = CsvImportService();

  /// Active account transactions shown by account-scoped views.
  List<Transaction> transactions = const [];

  /// Persisted manual categories by [transactionCategoryKey]; survives restarts and re-import.
  Map<String, String> transactionCategoryAssignments = const {};

  Map<String, AiCategorySuggestion> aiCategorySuggestions = const {};

  Map<String, List<Transaction>> get transactionsByAccount =>
      transactionRepository.transactionsByAccount;
  set transactionsByAccount(Map<String, List<Transaction>> value) {
    transactionRepository.transactionsByAccount = value;
  }

  /// Convenience: flattened across accounts, used for global dashboard metrics.
  List<Transaction> get allTransactions =>
      transactionRepository.allTransactions;

  List<Transaction> activeTransactionsForAccount(String? activeAccountId) {
    if (activeAccountId == null) return const <Transaction>[];
    return List<Transaction>.unmodifiable(
      transactionsByAccount[activeAccountId] ?? const <Transaction>[],
    );
  }

  Future<TransactionHydrationResult> hydratePersistedTransactions({
    required String? activeAccountId,
  }) {
    return transactionRepository.hydratePersistedTransactions(
      activeAccountId: activeAccountId,
    );
  }

  Future<TransactionDedupeResult> dedupePersistedTransactionsIfNeeded({
    required String? activeAccountId,
  }) {
    return transactionRepository.dedupePersistedTransactionsIfNeeded(
      activeAccountId: activeAccountId,
    );
  }

  /// Loads persisted per-transaction category picks.
  Future<void> hydrateTransactionCategoryAssignments() async {
    try {
      transactionCategoryAssignments =
          await loadTransactionCategoryAssignments();
    } on Object {
      transactionCategoryAssignments = {};
    }
  }

  Future<void> hydrateAiCategorySuggestions() async {
    try {
      aiCategorySuggestions = await loadAiCategorySuggestions();
    } on Object {
      aiCategorySuggestions = {};
    }
  }

  void persistTransactionCategoryAssignments() {
    saveTransactionCategoryAssignments(
      transactionCategoryAssignments,
    ).catchError((_) {});
  }

  Future<void> persistAiCategorySuggestions() async {
    await saveAiCategorySuggestions(aiCategorySuggestions);
  }

  void persistTransactionsByAccount() {
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
  }

  void removeTransactionMetadataForKeys(
    Set<String> keys, {
    required CategoryService categoryService,
  }) {
    if (keys.isEmpty) return;

    final nextAssignments = Map<String, String>.from(
      transactionCategoryAssignments,
    )..removeWhere((k, _) => keys.contains(k));
    final nextOverrides = Map<String, String>.from(
      categoryService.categoryOverrides,
    )..removeWhere((k, _) => keys.contains(k));
    final nextAiSuggestions = Map<String, AiCategorySuggestion>.from(
      aiCategorySuggestions,
    )..removeWhere((k, _) => keys.contains(k));

    transactionCategoryAssignments = nextAssignments;
    categoryService.categoryOverrides = nextOverrides;
    aiCategorySuggestions = nextAiSuggestions;
  }

  void applyCategoryAssignments(
    Map<String, String> keyToCanonicalCategory, {
    required CategoryService categoryService,
  }) {
    final normalized = <String, String>{};
    for (final e in keyToCanonicalCategory.entries) {
      final k = e.key.trim();
      final v = e.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      normalized[k] = v;
    }
    if (normalized.isEmpty) return;

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryService.categoryOverrides);
    for (final e in normalized.entries) {
      nextAssign[e.key] = e.value;
      nextOv[e.key] = e.value;
    }
    transactionCategoryAssignments = nextAssign;
    categoryService.categoryOverrides = nextOv;

    Transaction applyCategory(Transaction x) {
      final k = transactionCategoryKey(x);
      final cat = normalized[k];
      if (cat == null) return x;
      final c = cat.trim();
      if (c.isEmpty) return x;
      return Transaction(
        date: x.date,
        description: x.description,
        amount: x.amount,
        accountId: x.accountId,
        category: x.category,
        balanceAfter: x.balanceAfter,
        categoryId: c,
        importId: x.importId,
        fingerprint: x.fingerprint,
        financialRole: x.financialRole,
      );
    }

    final nextByAccount = <String, List<Transaction>>{};
    for (final e in transactionsByAccount.entries) {
      nextByAccount[e.key] = List.unmodifiable(
        e.value.map(applyCategory).toList(),
      );
    }
    transactionsByAccount = nextByAccount;

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    persistTransactionCategoryAssignments();
  }

  Future<int> undoCategoryApplyBatch(
    List<AiAppliedCategoryChange> batch, {
    required CategoryService categoryService,
  }) async {
    if (batch.isEmpty) return 0;

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryService.categoryOverrides);

    var undone = 0;
    for (final c in batch) {
      final current = nextAssign[c.key]?.trim();
      if (current == null || current.isEmpty) continue;
      if (current != c.newCategoryId) continue;

      if (c.previousCategoryId == null ||
          c.previousCategoryId!.trim().isEmpty) {
        nextAssign.remove(c.key);
        nextOv.remove(c.key);
      } else {
        nextAssign[c.key] = c.previousCategoryId!.trim();
        nextOv[c.key] = c.previousCategoryId!.trim();
      }
      undone += 1;
    }

    transactionCategoryAssignments = nextAssign;
    categoryService.categoryOverrides = nextOv;

    Transaction applyCategory(Transaction x) {
      final k = transactionCategoryKey(x);
      final cat = nextAssign[k];
      return Transaction(
        date: x.date,
        description: x.description,
        amount: x.amount,
        accountId: x.accountId,
        category: x.category,
        balanceAfter: x.balanceAfter,
        categoryId: cat,
        importId: x.importId,
        fingerprint: x.fingerprint,
        financialRole: x.financialRole,
      );
    }

    final nextByAccount = <String, List<Transaction>>{};
    for (final e in transactionsByAccount.entries) {
      nextByAccount[e.key] = List.unmodifiable(
        e.value.map(applyCategory).toList(),
      );
    }
    transactionsByAccount = nextByAccount;

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    persistTransactionCategoryAssignments();
    return undone;
  }

  List<Transaction> applyAiAutoApplyUndoResult(
    app_ai.AiAutoApplyUndoResult result, {
    required CategoryService categoryService,
  }) {
    transactionCategoryAssignments = result.transactionCategoryAssignments;
    categoryService.categoryOverrides = result.categoryOverrides;
    transactionsByAccount = result.transactionsByAccount;
    transactions = result.activeTransactions;
    persistTransactionsByAccount();
    persistTransactionCategoryAssignments();
    return transactions;
  }

  Future<TransactionMutationResult> deleteTransaction(
    Transaction transaction, {
    required CategoryService categoryService,
  }) async {
    final result = await transactionRepository.deleteTransaction(transaction);
    if (!result.success) return result;

    removeTransactionMetadataForKeys(
      result.removedKeys,
      categoryService: categoryService,
    );
    persistTransactionCategoryAssignments();
    persistAiCategorySuggestions().catchError((_) {});
    return result;
  }

  Future<TransactionMutationResult> clearTransactionsForAccount(
    String accountId, {
    required CategoryService categoryService,
  }) async {
    final result = await transactionRepository.clearTransactionsForAccount(
      accountId,
    );
    if (!result.success) return result;

    removeTransactionMetadataForKeys(
      result.removedKeys,
      categoryService: categoryService,
    );
    persistTransactionCategoryAssignments();
    persistAiCategorySuggestions().catchError((_) {});
    return result;
  }

  Future<TransactionMutationResult> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
    required CategoryService categoryService,
  }) async {
    final result = await transactionRepository.deleteTransactionsForImportBatch(
      accountId: accountId,
      importId: importId,
    );
    if (!result.success) return result;

    removeTransactionMetadataForKeys(
      result.removedKeys,
      categoryService: categoryService,
    );
    persistTransactionCategoryAssignments();
    persistAiCategorySuggestions().catchError((_) {});
    return result;
  }

  List<CsvImportBatchSummary> csvImportBatchesForAccount(String accountId) {
    return csvImportService.csvImportBatchesForAccount(
      accountId,
      transactionsByAccount: transactionsByAccount,
    );
  }

  List<Transaction> uncategorizedImportedRowsGlobal({
    required List<Account> accounts,
    required CategoryService categoryService,
    required Map<String, String> categoryDisplayRenames,
  }) {
    return csvImportService.uncategorizedImportedRowsGlobal(
      accounts: accounts,
      allTransactions: allTransactions,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
    );
  }

  List<Transaction> uncategorizedImportedRowsForAccount(
    String accountId, {
    required CategoryService categoryService,
    required Map<String, String> categoryDisplayRenames,
  }) {
    return csvImportService.uncategorizedImportedRowsForAccount(
      accountId,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
    );
  }

  CsvImportResult loadFromCsv(
    String utf8Text, {
    required String accountId,
    required DateTime? reference,
    required List<Account> accounts,
    required CategoryService categoryService,
  }) {
    final result = csvImportService.loadFromCsv(
      utf8Text,
      accountId: accountId,
      reference: reference,
      accounts: accounts,
      transactionCategoryAssignments: transactionCategoryAssignments,
      transactionRepository: transactionRepository,
    );
    categoryService.categoryOverrides = result.categoryOverrides;
    transactions = result.transactions;
    return result;
  }

  void persistActiveAccountTransactionsIfAny({
    required String? activeAccountId,
    required List<Transaction> transactions,
  }) {
    transactionRepository.persistActiveAccountTransactionsIfAny(
      activeAccountId: activeAccountId,
      transactions: transactions,
    );
  }

  String effectiveSpendGroupLabel(
    Transaction t, {
    required CategoryService categoryService,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
    required List<Transaction> allTransactionsContext,
  }) {
    return resolveTransaction(
      t,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
      allTransactionsContext: allTransactionsContext,
    ).canonicalCategory;
  }

  String effectiveCategoryDisplayLabel(
    Transaction t, {
    required CategoryService categoryService,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
    required List<Transaction> allTransactionsContext,
  }) {
    return resolveTransaction(
      t,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
      allTransactionsContext: allTransactionsContext,
    ).displayCategory;
  }

  transaction_resolution.ResolvedTransaction resolveTransaction(
    Transaction t, {
    required CategoryService categoryService,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
    required List<Transaction> allTransactionsContext,
  }) {
    final accountsById = {for (final a in accounts) a.id: a};
    return transaction_resolution.resolveTransaction(
      t: t,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accountsById: accountsById,
      allTransactions: allTransactionsContext,
    );
  }

  List<transaction_resolution.ResolvedTransaction> resolveTransactions(
    List<Transaction> txs, {
    required CategoryService categoryService,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
    required List<Transaction> allTransactionsContext,
  }) {
    final accountsById = {for (final a in accounts) a.id: a};
    return transaction_resolution.resolveTransactions(
      txs,
      categoryOverrides: categoryService.categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accountsById: accountsById,
      allTransactions: allTransactionsContext,
    );
  }
}
