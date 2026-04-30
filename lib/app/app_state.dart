import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/constants.dart';
import '../core/storage/accounts/account_storage.dart';
import '../features/transactions/domain/bank_statement_monthly.dart';
import '../core/storage/categories/category_catalog_storage.dart';
import '../features/transactions/data/csv_parser.dart';
import '../features/dashboard/domain/dashboard_snapshot.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../core/models/models.dart';
import '../core/storage/profile/profile_storage.dart';
import '../features/transactions/domain/spend_categories.dart';
import '../core/storage/transactions/transaction_category_storage.dart';
import '../features/transactions/domain/transaction_resolution.dart'
    as transaction_resolution;
import '../core/storage/transactions/transaction_storage.dart';
import '../core/storage/ai/ai_suggestion_storage.dart';
import '../features/transactions/data/ai_categorization_service.dart';
import '../features/transactions/data/csv_import_service.dart';
import '../features/transactions/data/transaction_repository.dart';
import '../features/transactions/application/ai_categorization_service.dart'
    as app_ai;
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/budgets/data/budget_repository.dart';
import '../features/budgets/domain/budget_models.dart';

export '../features/transactions/data/csv_import_service.dart'
    show CsvImportBatchSummary;

/// Holds parsed statement data and derived aggregates.
/// Monthly category budgets ([hydratePersistedBudgets] / [commitMonthlyBudgetDraft])
/// are persisted separately from CSV data.
class AppState extends ChangeNotifier {
  LocalProfile? localProfile;

  /// Persisted budgets and active budget period (monthly / weekly / custom).
  final BudgetRepository budgets = BudgetRepository();

  final TransactionRepository transactionRepository = TransactionRepository();
  final CsvImportService csvImportService = CsvImportService();
  final CategoryService categoryService = CategoryService();
  final MerchantService merchantService = MerchantService();
  final app_ai.AiCategorizationApplicationService aiCategorizationService =
      app_ai.AiCategorizationApplicationService();

  final DashboardService _dashboard = DashboardService();

  /// The account currently being viewed/reviewed in UI flows.
  String? activeAccountId;

  Map<String, List<Transaction>> get transactionsByAccount =>
      transactionRepository.transactionsByAccount;
  set transactionsByAccount(Map<String, List<Transaction>> value) {
    transactionRepository.transactionsByAccount = value;
  }

  /// Convenience: flattened across accounts, used for global dashboard metrics.
  List<Transaction> get allTransactions =>
      transactionRepository.allTransactions;

  List<Transaction> transactions = const [];
  double totalBalance = 0;
  double spentThisMonth = 0;
  double incomeThisMonth = 0;
  double availableThisMonth = 0;
  int uncategorizedCount = 0;
  List<CategorySpend> topCategories = const [];
  List<CategoryLeakStat> biggestLeaksThisMonth = const [];
  int? burnRunwayDays;

  /// Newest calendar month first for the **active account only** (see [_recomputeDerived]).
  ///
  /// Do **not** use for global Overview / [GlobalDashboardScope] UI — use
  /// [monthlyGroupsForDashboardScope] or [buildDashboardSnapshot].monthlyGroups instead.
  List<MonthlyBankGroup> monthlyGroups = const [];

  Map<String, String> get categoryOverrides =>
      categoryService.categoryOverrides;
  set categoryOverrides(Map<String, String> value) {
    categoryService.categoryOverrides = value;
  }

  /// Persisted manual categories by [transactionCategoryKey]; survives restarts and re-import.
  Map<String, String> transactionCategoryAssignments = const {};

  Map<String, AiCategorySuggestion> aiCategorySuggestions = const {};

  Map<String, String> get merchantCategoryMemory =>
      merchantService.merchantCategoryMemory;
  set merchantCategoryMemory(Map<String, String> value) {
    merchantService.merchantCategoryMemory = value;
  }

  bool get importAiCategorizationRunning =>
      aiCategorizationService.importAiCategorizationRunning;
  set importAiCategorizationRunning(bool value) {
    aiCategorizationService.importAiCategorizationRunning = value;
  }

  int get importAiProgressCompleted =>
      aiCategorizationService.importAiProgressCompleted;
  set importAiProgressCompleted(int value) {
    aiCategorizationService.importAiProgressCompleted = value;
  }

  int get importAiProgressTotal =>
      aiCategorizationService.importAiProgressTotal;
  set importAiProgressTotal(int value) {
    aiCategorizationService.importAiProgressTotal = value;
  }

  String? get importAiSnackMessage =>
      aiCategorizationService.importAiSnackMessage;
  set importAiSnackMessage(String? value) {
    aiCategorizationService.importAiSnackMessage = value;
  }

  bool get importAiEngineConfigured => Constants.openAIKey.isNotEmpty;

  bool needsImportAiAfterCsvUpload(String accountId) {
    return aiCategorizationService.needsImportAiAfterCsvUpload(
      accountId,
      uncategorizedImportedRowsForAccount: uncategorizedImportedRowsForAccount,
    );
  }

  String? consumeImportAiSnackMessage() {
    return aiCategorizationService.consumeImportAiSnackMessage();
  }

  /// Runs after CSV import: merchant memory first, then GPT in batches (see [AICategorizationService]).
  Future<void> startBackgroundImportAiCategorization(String accountId) async {
    await aiCategorizationService.startBackgroundImportAiCategorization(
      accountId,
      importAiEngineConfigured: importAiEngineConfigured,
      uncategorizedImportedRowsForAccount: uncategorizedImportedRowsForAccount,
      merchantCategoryMemory: merchantCategoryMemory,
      applyPrefilledMerchantChunks: (prefilled) {
        return merchantService.applyPrefilledMerchantChunks(
          prefilled,
          applyCategoriesWithMerchantLearning:
              applyCategoriesWithMerchantLearning,
        );
      },
      allowedCategoryPickerLabels: allowedCategoryPickerLabels,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
      notifyListeners: notifyListeners,
    );
  }

  /// User-created category names (shown in the assignment sheet alongside built-ins).
  List<String> customCategories = const [];

  /// Lowercase base label -> user display name (renamed built-ins / display tweaks).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Map<String, String> categoryDisplayRenames = const {};

  /// Lowercase canonical labels removed from the picker (deleted built-ins).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Set<String> categoriesHiddenFromPicker = {};

  // Rules feature removed: no persisted categorization rules.

  /// User-defined bank / card accounts (persisted separately from CSV rows).
  List<Account> accounts = const [];

  /// Reference month for "spent this month" / top categories (set in [loadFromCsv]).
  DateTime _spendReference = DateTime.now();

  /// Same instant used for monthly aggregates (defaults to import time / [loadFromCsv]).
  DateTime get spendReference => _spendReference;

  /// Loads persisted budgets from disk (call once before [runApp]).
  Future<void> hydratePersistedBudgets() async {
    await budgets.hydrate(reference: _spendReference);
    notifyListeners();
  }

  // Rules feature removed.

  /// Loads custom category names and picker metadata from disk (call once before [runApp]).
  Future<void> hydratePersistedCategoryCatalog() async {
    try {
      final snap = await loadCategoryCatalog();
      customCategories = List<String>.from(snap.customCategories);
      categoryDisplayRenames = Map<String, String>.from(
        snap.categoryDisplayRenames,
      );
      categoriesHiddenFromPicker = Set<String>.from(
        snap.categoriesHiddenFromPicker,
      );
    } on Object {
      customCategories = const [];
      categoryDisplayRenames = const {};
      categoriesHiddenFromPicker = {};
    }
    notifyListeners();
  }

  /// Loads persisted accounts from disk (call once before [runApp]).
  Future<void> hydratePersistedAccounts() async {
    try {
      accounts = await loadAccounts();
    } on Object {
      accounts = const [];
    }
    notifyListeners();
  }

  /// Loads persisted transactions across all accounts (call once before [runApp]).
  Future<void> hydratePersistedTransactions() async {
    final result = await transactionRepository.hydratePersistedTransactions(
      activeAccountId: activeAccountId,
    );
    transactions = result.activeTransactions;
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    notifyListeners();
  }

  /// One-time migration: remove duplicated transactions caused by unstable v1 fingerprints.
  ///
  /// Keeps one row per stable identity key per account, preferring rows with:
  /// - persisted/manual categoryId
  /// - non-null running balance
  /// - earliest importId
  Future<void> dedupePersistedTransactionsIfNeeded() async {
    final result = await transactionRepository
        .dedupePersistedTransactionsIfNeeded(activeAccountId: activeAccountId);
    if (!result.changed) return;

    transactions = result.activeTransactions;
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    notifyListeners();
  }

  Future<void> hydrateLocalProfile() async {
    try {
      localProfile = await loadLocalProfile();
    } on Object {
      localProfile = null;
    }
    notifyListeners();
  }

  Future<void> setLocalProfile(LocalProfile profile) async {
    await saveLocalProfile(profile);
    localProfile = profile;
    // Switch merchant memory namespace to the new profile.
    await hydrateMerchantCategoryMemory();
    notifyListeners();
  }

  String _userNamespaceForMerchantMemory() {
    // LocalProfile is the best available per-user namespace in v1.
    // If absent (onboarding), keep memory in an anonymous namespace.
    final p = localProfile;
    final created = p?.createdAtUtcIso.trim();
    if (created != null && created.isNotEmpty) return created;
    return 'anon';
  }

  Future<void> hydrateMerchantCategoryMemory() async {
    await merchantService.hydrateMerchantCategoryMemory(
      _userNamespaceForMerchantMemory(),
    );
    notifyListeners();
  }

  /// Applies explicit category assignments, then learns merchant memory and backfills
  /// similar merchants. Returns the backfill batch for UI undo.
  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    return merchantService.applyCategoriesWithMerchantLearning(
      keyToCanonicalCategory,
      allTransactions: allTransactions,
      transactionCategoryAssignments: transactionCategoryAssignments,
      applyCategoryAssignments: _applyCategoryAssignments,
      userNamespace: _userNamespaceForMerchantMemory(),
    );
  }

  void _applyCategoryAssignments(Map<String, String> keyToCanonicalCategory) {
    final normalized = <String, String>{};
    for (final e in keyToCanonicalCategory.entries) {
      final k = e.key.trim();
      final v = e.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      normalized[k] = v;
    }
    if (normalized.isEmpty) return;

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryOverrides);
    for (final e in normalized.entries) {
      nextAssign[e.key] = e.value;
      nextOv[e.key] = e.value;
    }
    transactionCategoryAssignments = nextAssign;
    categoryOverrides = nextOv;

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
    _persistTransactionCategoryAssignments();
    refreshAllState();
  }

  Future<int> undoCategoryApplyBatch(
    List<AiAppliedCategoryChange> batch,
  ) async {
    if (batch.isEmpty) return 0;

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryOverrides);

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
    categoryOverrides = nextOv;

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
    _persistTransactionCategoryAssignments();
    refreshAllState();
    return undone;
  }

  /// Appends [account], persists, and notifies. Returns false if save fails.
  Future<bool> addAccount(Account account) async {
    final next = [...accounts, account];
    try {
      await saveAccounts(next);
    } on Object {
      return false;
    }
    accounts = next;
    notifyListeners();
    return true;
  }

  /// Deletes one account and all its transactions + related keyed metadata.
  Future<bool> deleteAccount(String accountId) async {
    final id = accountId.trim();
    if (id.isEmpty) return false;
    if (!accounts.any((a) => a.id == id)) return false;

    final removedTransactions =
        transactionsByAccount[id] ?? const <Transaction>[];
    final removedKeys = removedTransactions.map(transactionCategoryKey).toSet();

    final nextAccounts = accounts.where((a) => a.id != id).toList();
    final nextByAccount = <String, List<Transaction>>{
      for (final e in transactionsByAccount.entries)
        if (e.key != id) e.key: List.unmodifiable(e.value),
    };

    try {
      await saveAccounts(nextAccounts);
      await saveTransactionsByAccount(nextByAccount);
    } on Object {
      return false;
    }

    accounts = nextAccounts;
    transactionsByAccount = nextByAccount;
    _removeTransactionMetadataForKeys(removedKeys);

    if (activeAccountId == id) {
      activeAccountId = null;
    }

    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return true;
  }

  void _persistCategoryCatalog() {
    saveCategoryCatalog(
      customCategories: customCategories,
      categoryDisplayRenames: categoryDisplayRenames,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
    ).catchError((_) {});
  }

  void _persistTransactionCategoryAssignments() {
    saveTransactionCategoryAssignments(
      transactionCategoryAssignments,
    ).catchError((_) {});
  }

  /// Loads persisted per-transaction category picks (call once before [runApp]).
  Future<void> hydrateTransactionCategoryAssignments() async {
    try {
      transactionCategoryAssignments =
          await loadTransactionCategoryAssignments();
    } on Object {
      transactionCategoryAssignments = {};
    }
    notifyListeners();
  }

  Future<void> hydrateAiCategorySuggestions() async {
    try {
      aiCategorySuggestions = await loadAiCategorySuggestions();
    } on Object {
      aiCategorySuggestions = {};
    }
    notifyListeners();
  }

  Future<void> _persistAiCategorySuggestions() async {
    await saveAiCategorySuggestions(aiCategorySuggestions);
  }

  void _removeTransactionMetadataForKeys(Set<String> keys) {
    if (keys.isEmpty) return;

    final nextAssignments = Map<String, String>.from(
      transactionCategoryAssignments,
    )..removeWhere((k, _) => keys.contains(k));
    final nextOverrides = Map<String, String>.from(categoryOverrides)
      ..removeWhere((k, _) => keys.contains(k));
    final nextAiSuggestions = Map<String, AiCategorySuggestion>.from(
      aiCategorySuggestions,
    )..removeWhere((k, _) => keys.contains(k));

    transactionCategoryAssignments = nextAssignments;
    categoryOverrides = nextOverrides;
    aiCategorySuggestions = nextAiSuggestions;
  }

  /// Single source of truth for app-wide recomputation after any data mutation.
  ///
  /// This keeps Dashboard (global + account), monthly breakdowns, and dependent
  /// views in sync without requiring route-level/manual refresh hooks.
  void refreshAllState() {
    final active = activeAccountId;
    final List<Transaction> activeTx = active == null
        ? const <Transaction>[]
        : List.unmodifiable(
            transactionsByAccount[active] ?? const <Transaction>[],
          );
    transactions = activeTx;
    _recomputeDerived(
      activeAccountTransactions: activeTx,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: activeTx,
      diag: null,
    );
    notifyListeners();
  }

  /// Deletes a single transaction row and refreshes derived dashboard state.
  Future<bool> deleteTransaction(Transaction transaction) async {
    final result = await transactionRepository.deleteTransaction(transaction);
    if (!result.success) return false;

    _removeTransactionMetadataForKeys(result.removedKeys);
    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return true;
  }

  /// Deletes all transactions for one account and refreshes derived dashboard state.
  Future<int> clearTransactionsForAccount(String accountId) async {
    final result = await transactionRepository.clearTransactionsForAccount(
      accountId,
    );
    if (!result.success) return 0;

    _removeTransactionMetadataForKeys(result.removedKeys);
    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return result.removedCount;
  }

  List<CsvImportBatchSummary> csvImportBatchesForAccount(String accountId) {
    return csvImportService.csvImportBatchesForAccount(
      accountId,
      transactionsByAccount: transactionsByAccount,
    );
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    final result = await transactionRepository.deleteTransactionsForImportBatch(
      accountId: accountId,
      importId: importId,
    );
    if (!result.success) return 0;

    _removeTransactionMetadataForKeys(result.removedKeys);
    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return result.removedCount;
  }

  List<Transaction> uncategorizedImportedRowsGlobal() {
    return csvImportService.uncategorizedImportedRowsGlobal(
      accounts: accounts,
      allTransactions: allTransactions,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
    );
  }

  Future<({int applied, int queuedForReview})>
  autoCategorizeGlobalUncategorized({
    required AICategorizationService service,
    double autoApplyConfidenceThreshold = 0.90,
  }) async {
    return aiCategorizationService.autoCategorizeGlobalUncategorized(
      service: service,
      allowedCategoryPickerLabels: allowedCategoryPickerLabels,
      uncategorizedImportedRowsGlobal: uncategorizedImportedRowsGlobal(),
      transactionCategoryAssignments: transactionCategoryAssignments,
      aiCategorySuggestions: aiCategorySuggestions,
      setAiCategorySuggestions: (next) => aiCategorySuggestions = next,
      persistAiCategorySuggestions: _persistAiCategorySuggestions,
      bulkSetCategoryOverrides: bulkSetCategoryOverrides,
      autoApplyConfidenceThreshold: autoApplyConfidenceThreshold,
    );
  }

  Future<int> undoLastAiAutoApply() async {
    final result = await aiCategorizationService.undoLastAiAutoApply(
      transactionCategoryAssignments: transactionCategoryAssignments,
      categoryOverrides: categoryOverrides,
      transactionsByAccount: transactionsByAccount,
      activeAccountId: activeAccountId,
    );
    if (result.undone == 0) return 0;

    transactionCategoryAssignments = result.transactionCategoryAssignments;
    categoryOverrides = result.categoryOverrides;
    transactionsByAccount = result.transactionsByAccount;
    transactions = result.activeTransactions;
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    notifyListeners();

    return result.undone;
  }

  /// Single entry for effective spend grouping (saved categoryId → override map → rules → CSV / keywords).
  String effectiveSpendGroupLabel(Transaction t) {
    return resolveTransaction(
      t,
      allTransactionsContext: allTransactions,
    ).canonicalCategory;
  }

  /// Display label after renames — use for UI and "is Uncategorized?" checks on this app’s state.
  String effectiveCategoryDisplayLabel(Transaction t) {
    return resolveTransaction(
      t,
      allTransactionsContext: allTransactions,
    ).displayCategory;
  }

  transaction_resolution.ResolvedTransaction resolveTransaction(
    Transaction t, {
    required List<Transaction> allTransactionsContext,
  }) {
    final accountsById = {for (final a in accounts) a.id: a};
    return transaction_resolution.resolveTransaction(
      t: t,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accountsById: accountsById,
      allTransactions: allTransactionsContext,
    );
  }

  List<transaction_resolution.ResolvedTransaction> resolveTransactions(
    List<Transaction> txs, {
    required List<Transaction> allTransactionsContext,
  }) {
    final accountsById = {for (final a in accounts) a.id: a};
    return transaction_resolution.resolveTransactions(
      txs,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accountsById: accountsById,
      allTransactions: allTransactionsContext,
    );
  }

  /// Built-in + custom categories shown in pickers (for AI allow-lists and review UI).
  List<String> get allowedCategoryPickerLabels => categoryPickerCanonicals(
    customCategories: customCategories,
    hiddenLower: categoriesHiddenFromPicker,
  );

  /// Rows for [buildDashboardSnapshot] / Overview vs account-scoped views.
  List<Transaction> transactionsForDashboardScope(DashboardScope scope) {
    return _dashboard.transactionsForDashboardScope(
      scope: scope,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
    );
  }

  /// Uncategorized statement rows for [accountId] using the same rules as the dashboard.
  List<Transaction> uncategorizedImportedRowsForAccount(String accountId) {
    return csvImportService.uncategorizedImportedRowsForAccount(
      accountId,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
    );
  }

  // Rules feature removed.

  /// Active calendar month key derived from spend reference (budget UX).
  String get activeBudgetYearMonth =>
      budgets.budgetYearMonthKey(_spendReference);

  /// Weekly period key uses the exact user-selected start date (not normalized).
  String budgetWeekStartKey(DateTime date) => budgets.budgetWeekStartKey(date);

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) =>
      budgets.ensureCustomBudgetPeriod(start, end);

  void setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    budgets.setActivePeriod(type, key);
    notifyListeners();
  }

  double? monthlyBudgetForDisplayLabel(
    String displayLabel, {
    String? yearMonth,
  }) {
    final ym = yearMonth ?? activeBudgetYearMonth;
    return budgets.budgetForDisplayLabel(
      displayLabel: displayLabel,
      periodType: BudgetPeriodType.monthly,
      periodKey: ym,
    );
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    final ok = await budgets.commitBudgetDraft(
      periodType,
      periodKey,
      draftByNormalizedDisplayKey,
    );
    if (ok) refreshAllState();
    return ok;
  }

  Future<bool> commitMonthlyBudgetDraft(
    String yearMonth,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) {
    return commitBudgetDraft(
      BudgetPeriodType.monthly,
      yearMonth,
      draftByNormalizedDisplayKey,
    );
  }

  /// Actual spend totals for the selected month grouped by display category label.
  ///
  /// Values are positive spend amounts (outflows that count as spend).
  Map<String, double> spentByDisplayCategoryForScope(
    DashboardScope scope, {
    DateTime? reference,
  }) {
    return _dashboard.spentByDisplayCategoryForScope(
      scope: scope,
      reference: reference,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
    );
  }

  Map<String, double> spentByDisplayCategoryForScopeInRange(
    DashboardScope scope, {
    required DateTime start,
    required DateTime end,
  }) {
    return _dashboard.spentByDisplayCategoryForScopeInRange(
      scope: scope,
      start: start,
      end: end,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
    );
  }

  Map<String, double> spentThisMonthByDisplayCategory({DateTime? reference}) {
    return _dashboard.spentThisMonthByDisplayCategory(
      reference: reference,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
    );
  }

  /// Loads and aggregates using [reference] for "this month" (defaults to now, local).
  ///
  /// [accountId] must match a persisted [accounts] entry (set after [hydratePersistedAccounts]).
  void loadFromCsv(
    String utf8Text, {
    required String accountId,
    DateTime? reference,
  }) {
    final result = csvImportService.loadFromCsv(
      utf8Text,
      accountId: accountId,
      reference: reference,
      accounts: accounts,
      transactionCategoryAssignments: transactionCategoryAssignments,
      transactionRepository: transactionRepository,
    );
    _spendReference = result.spendReference;
    activeAccountId = result.activeAccountId;
    categoryOverrides = result.categoryOverrides;
    transactions = result.transactions;
    totalBalance = result.totalBalance;
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: result.diagnostics,
    );
    notifyListeners();
    _persistCategoryCatalog();
  }

  void _persistActiveAccountTransactionsIfAny() {
    transactionRepository.persistActiveAccountTransactionsIfAny(
      activeAccountId: activeAccountId,
      transactions: transactions,
    );
  }

  /// Assigns a category to a transaction and refreshes aggregates.
  void setCategoryOverride(Transaction t, String category) {
    categoryService.setCategoryOverride(
      t,
      category,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Assigns categories for many [transactionCategoryKey]s at once (persists [categoryId] on each row).
  void bulkSetCategoryOverrides(Map<String, String> keyToCanonicalCategory) {
    categoryService.bulkSetCategoryOverrides(
      keyToCanonicalCategory,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Adds a new category name (if needed), assigns [t], and notifies.
  void createCategoryAndAssign(Transaction t, String rawName) {
    categoryService.createCategoryAndAssign(
      t,
      rawName,
      customCategories: customCategories,
      setCustomCategories: (next) => customCategories = next,
      persistCategoryCatalog: _persistCategoryCatalog,
      setCategoryOverride: setCategoryOverride,
    );
  }

  /// Deletes a category from the picker and clears assignments using it (any label, built-in or custom).
  void deleteCategory(String canonicalLabel) {
    final result = categoryService.deleteCategory(
      canonicalLabel,
      customCategories: customCategories,
      categoryDisplayRenames: categoryDisplayRenames,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
      transactionCategoryAssignments: transactionCategoryAssignments,
      transactions: transactions,
    );
    if (result == null) return;

    customCategories = result.customCategories;
    categoryDisplayRenames = result.categoryDisplayRenames;
    categoriesHiddenFromPicker = result.categoriesHiddenFromPicker;
    transactionCategoryAssignments = result.transactionCategoryAssignments;
    transactions = result.transactions;
    if (result.shouldPersistActiveAccountTransactions) {
      _persistActiveAccountTransactionsIfAny();
    }
    _persistTransactionCategoryAssignments();
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    notifyListeners();
    _persistCategoryCatalog();
  }

  /// Renames a category. Built-ins: display-only map (overrides stay canonical). Custom: text + overrides.
  void renameCategory(String oldLabel, String newLabel) {
    final result = categoryService.renameCategory(
      oldLabel,
      newLabel,
      customCategories: customCategories,
      categoryDisplayRenames: categoryDisplayRenames,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
      transactionCategoryAssignments: transactionCategoryAssignments,
      transactions: transactions,
    );
    if (result == null) return;

    customCategories = result.customCategories;
    categoryDisplayRenames = result.categoryDisplayRenames;
    categoriesHiddenFromPicker = result.categoriesHiddenFromPicker;
    transactionCategoryAssignments = result.transactionCategoryAssignments;
    transactions = result.transactions;
    if (result.shouldPersistActiveAccountTransactions) {
      _persistActiveAccountTransactionsIfAny();
      _persistTransactionCategoryAssignments();
    }

    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    notifyListeners();
    _persistCategoryCatalog();
  }

  void _recomputeDerived({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diag,
  }) {
    final d = _dashboard.recomputeDerived(
      activeAccountTransactions: activeAccountTransactions,
      allTransactionsForMetrics: allTransactionsForMetrics,
      transactionsForCsvDiagnostics: transactionsForCsvDiagnostics,
      diag: diag,
      spendReference: _spendReference,
      totalBalance: totalBalance,
      accounts: accounts,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
      resolveTransactions: resolveTransactions,
    );
    spentThisMonth = d.spentThisMonth;
    incomeThisMonth = d.incomeThisMonth;
    availableThisMonth = d.availableThisMonth;
    uncategorizedCount = d.uncategorizedCount;
    biggestLeaksThisMonth = d.biggestLeaksThisMonth;
    burnRunwayDays = d.burnRunwayDays;
    topCategories = d.topCategories;
    monthlyGroups = d.monthlyGroups;
  }

  void clear() {
    transactions = const [];
    transactionsByAccount = const {};
    activeAccountId = null;
    totalBalance = 0;
    spentThisMonth = 0;
    incomeThisMonth = 0;
    availableThisMonth = 0;
    uncategorizedCount = 0;
    topCategories = const [];
    biggestLeaksThisMonth = const [];
    burnRunwayDays = null;
    monthlyGroups = const [];
    categoryOverrides = const {};
    customCategories = const [];
    categoryDisplayRenames = const {};
    categoriesHiddenFromPicker = <String>{};
    notifyListeners();
    _persistCategoryCatalog();
  }
}
