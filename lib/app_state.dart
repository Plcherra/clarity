import 'dart:async';

import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'core/storage/accounts/account_storage.dart';
import 'balance_resolve.dart';
import 'bank_statement_monthly.dart';
import 'core/storage/budgets/budget_keys.dart';
import 'core/storage/budgets/budget_storage.dart';
import 'core/storage/categories/category_catalog_storage.dart';
import 'csv_parser.dart';
import 'dashboard_metrics.dart';
import 'dashboard_snapshot.dart';
import 'formatting.dart';
import 'core/models/models.dart';
import 'core/storage/profile/profile_storage.dart';
import 'spend_categories.dart';
import 'core/storage/transactions/transaction_category_storage.dart';
import 'core/storage/transactions/merchant_category_memory_storage.dart';
import 'transaction_fingerprint.dart';
import 'transaction_resolution.dart' as transaction_resolution;
import 'core/storage/transactions/transaction_storage.dart';
import 'uncategorized_for_ai.dart';
import 'core/storage/ai/ai_suggestion_storage.dart';
import 'ai_categorization_service.dart';

class CsvImportBatchSummary {
  const CsvImportBatchSummary({
    required this.importId,
    required this.transactionCount,
    required this.importedAtUtc,
  });

  final String importId;
  final int transactionCount;
  final DateTime? importedAtUtc;
}

class BudgetCategoryPerformance {
  const BudgetCategoryPerformance({
    required this.displayLabel,
    required this.budgeted,
    required this.spent,
  });

  final String displayLabel;
  final double budgeted;
  final double spent;

  double get remaining => budgeted - spent;
  double get overspent => remaining < 0 ? -remaining : 0;
  bool get onTrack => remaining >= 0;
}

class BudgetPerformanceSnapshot {
  const BudgetPerformanceSnapshot({
    required this.periodType,
    required this.periodKey,
    required this.periodLabel,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.budgetedCategoryCount,
    required this.onTrackCategoryCount,
    required this.totalOverspent,
    required this.topOverspendingCategories,
  });

  final BudgetPeriodType periodType;
  final String periodKey;
  final String periodLabel;
  final double totalBudgeted;
  final double totalSpent;
  final int budgetedCategoryCount;
  final int onTrackCategoryCount;
  final double totalOverspent;
  final List<BudgetCategoryPerformance> topOverspendingCategories;
}

enum BudgetPeriodType { monthly, weekly, custom }

class BudgetPeriodRange {
  const BudgetPeriodRange({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}

/// Holds parsed statement data and derived aggregates.
/// Monthly category budgets ([hydratePersistedBudgets] / [commitMonthlyBudgetDraft])
/// are persisted separately from CSV data.
class AppState extends ChangeNotifier {
  LocalProfile? localProfile;

  /// The account currently being viewed/reviewed in UI flows.
  String? activeAccountId;

  /// All persisted transactions keyed by accountId (append-only by import).
  Map<String, List<Transaction>> transactionsByAccount = const {};

  /// Convenience: flattened across accounts, used for global dashboard metrics.
  List<Transaction> get allTransactions {
    if (transactionsByAccount.isEmpty) return const [];
    final out = <Transaction>[];
    for (final e in transactionsByAccount.entries) {
      out.addAll(e.value);
    }
    return out;
  }

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

  /// Manual category by [transactionCategoryKey]; cleared when a new CSV is loaded.
  Map<String, String> categoryOverrides = const {};

  /// Persisted manual categories by [transactionCategoryKey]; survives restarts and re-import.
  Map<String, String> transactionCategoryAssignments = const {};

  Map<String, AiCategorySuggestion> aiCategorySuggestions = const {};

  /// Per-user merchant -> canonical category “silent memory” (keys are lowercase merchant keys).
  Map<String, String> merchantCategoryMemory = const {};

  /// CSV import background AI job (see [startBackgroundImportAiCategorization]).
  bool importAiCategorizationRunning = false;
  int importAiProgressCompleted = 0;
  int importAiProgressTotal = 0;

  /// One-shot snack text for [ImportAiStatusHost]; cleared via [consumeImportAiSnackMessage].
  String? importAiSnackMessage;

  bool get importAiEngineConfigured => Constants.openAIKey.isNotEmpty;

  bool needsImportAiAfterCsvUpload(String accountId) {
    return uncategorizedImportedRowsForAccount(accountId.trim()).isNotEmpty;
  }

  String? consumeImportAiSnackMessage() {
    final m = importAiSnackMessage;
    importAiSnackMessage = null;
    return m;
  }

  Future<void> _yieldUi() => Future<void>.delayed(Duration.zero);

  Future<void> _applyPrefilledMerchantChunks(Map<String, String> prefilled) async {
    if (prefilled.isEmpty) return;
    final entries = prefilled.entries.toList();
    const chunkSize = 80;
    for (var i = 0; i < entries.length; i += chunkSize) {
      final slice = Map<String, String>.fromEntries(
        entries.skip(i).take(chunkSize),
      );
      applyCategoriesWithMerchantLearning(slice);
      await _yieldUi();
    }
  }

  /// Runs after CSV import: merchant memory first, then GPT in batches (see [AICategorizationService]).
  Future<void> startBackgroundImportAiCategorization(String accountId) async {
    await _yieldUi();
    final id = accountId.trim();
    if (id.isEmpty) return;
    if (importAiCategorizationRunning) return;

    var unc = uncategorizedImportedRowsForAccount(id);
    final prefilled = <String, String>{};
    for (final t in unc) {
      final k = transactionCategoryKey(t);
      final mk = transactionMerchantKeyLower(t).trim().toLowerCase();
      if (mk.isEmpty) continue;
      final memo = merchantCategoryMemory[mk];
      if (memo != null && memo.trim().isNotEmpty) {
        prefilled[k] = memo.trim();
      }
    }
    await _applyPrefilledMerchantChunks(prefilled);

    unc = uncategorizedImportedRowsForAccount(id);
    if (unc.isEmpty) {
      importAiSnackMessage = 'Transactions categorized successfully';
      notifyListeners();
      return;
    }

    if (!importAiEngineConfigured) {
      return;
    }

    importAiCategorizationRunning = true;
    importAiProgressCompleted = 0;
    importAiProgressTotal = unc.length;
    notifyListeners();

    final service = AICategorizationService();
    try {
      await service.suggestCategories(
        transactions: unc,
        allowedCategoryIds: allowedCategoryPickerLabels,
        onBatchProgress: (completed, total) {
          importAiProgressCompleted = completed;
          importAiProgressTotal = total;
          notifyListeners();
        },
        onPartialBatch: (partial) async {
          final toApply = <String, String>{};
          for (final e in partial.entries) {
            final v = e.value?.trim();
            if (v != null && v.isNotEmpty) {
              toApply[e.key] = v;
            }
          }
          if (toApply.isNotEmpty) {
            applyCategoriesWithMerchantLearning(toApply);
          }
          await _yieldUi();
        },
      );
      importAiSnackMessage = 'Transactions categorized successfully';
    } on MissingOpenAiApiKeyException {
      importAiSnackMessage =
          'Add OPENAI_API_KEY to your .env file to use AI categorization.';
    } catch (e) {
      importAiSnackMessage = 'Could not categorize transactions: $e';
    } finally {
      service.close();
      importAiCategorizationRunning = false;
      notifyListeners();
    }
  }

  // Bump to invalidate cached "empty" suggestions from earlier prompt iterations.
  static const int _aiPromptVersion = 2;

  /// User-created category names (shown in the assignment sheet alongside built-ins).
  List<String> customCategories = const [];

  /// Lowercase base label -> user display name (renamed built-ins / display tweaks).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Map<String, String> categoryDisplayRenames = const {};

  /// Lowercase canonical labels removed from the picker (deleted built-ins).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Set<String> categoriesHiddenFromPicker = {};

  /// Month-aware budget amounts:
  /// `YYYY-MM` -> ([budgetDisplayKey] of display label -> amount).
  ///
  /// [clear] / [loadFromCsv] do **not** clear this map.
  Map<String, Map<String, double>> categoryMonthlyBudgetsByYearMonth = {};

  /// Week-aware budget amounts:
  /// `YYYY-MM-DD` (week start Monday) -> ([budgetDisplayKey] -> amount).
  Map<String, Map<String, double>> categoryWeeklyBudgetsByWeekStart = {};

  /// Custom-range budget amounts:
  /// `customKey` -> ([budgetDisplayKey] -> amount).
  Map<String, Map<String, double>> categoryCustomBudgetsByKey = {};

  /// Custom-range key -> explicit date range.
  Map<String, BudgetPeriodRange> customBudgetRangesByKey = {};

  BudgetPeriodType activeBudgetPeriodType = BudgetPeriodType.monthly;
  String? activeBudgetPeriodKey;

  // Rules feature removed: no persisted categorization rules.

  /// User-defined bank / card accounts (persisted separately from CSV rows).
  List<Account> accounts = const [];

  /// Reference month for "spent this month" / top categories (set in [loadFromCsv]).
  DateTime _spendReference = DateTime.now();

  /// Same instant used for monthly aggregates (defaults to import time / [loadFromCsv]).
  DateTime get spendReference => _spendReference;

  /// Loads persisted budgets from disk (call once before [runApp]).
  Future<void> hydratePersistedBudgets() async {
    try {
      final snapshot = await loadBudgetSnapshot(
        reference: _spendReference,
      );
      categoryMonthlyBudgetsByYearMonth = snapshot.monthly;
      categoryWeeklyBudgetsByWeekStart = snapshot.weekly;
      categoryCustomBudgetsByKey = snapshot.custom;
      customBudgetRangesByKey = {
        for (final e in snapshot.customRanges.entries)
          e.key: BudgetPeriodRange(
            start: e.value.start,
            end: e.value.end,
          ),
      };
    } on Object {
      categoryMonthlyBudgetsByYearMonth = {};
      categoryWeeklyBudgetsByWeekStart = {};
      categoryCustomBudgetsByKey = {};
      customBudgetRangesByKey = {};
    }
    activeBudgetPeriodType = BudgetPeriodType.monthly;
    activeBudgetPeriodKey = budgetYearMonthKey(DateTime.now());
    notifyListeners();
  }

  // Rules feature removed.

  /// Loads custom category names and picker metadata from disk (call once before [runApp]).
  Future<void> hydratePersistedCategoryCatalog() async {
    try {
      final snap = await loadCategoryCatalog();
      customCategories = List<String>.from(snap.customCategories);
      categoryDisplayRenames = Map<String, String>.from(snap.categoryDisplayRenames);
      categoriesHiddenFromPicker = Set<String>.from(snap.categoriesHiddenFromPicker);
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
    try {
      transactionsByAccount = await loadTransactionsByAccount();
    } on Object {
      transactionsByAccount = {};
    }
    // Keep current active account selection, but refresh derived metrics.
    final active = activeAccountId;
    if (active != null) {
      transactions = List.unmodifiable(transactionsByAccount[active] ?? const []);
    }
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
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
    final done = await getTransactionsDedupeMigrationDone();
    if (done) return;

    Transaction pickBetter(Transaction a, Transaction b) {
      int score(Transaction t) {
        var s = 0;
        final cid = t.categoryId;
        if (cid != null && cid.trim().isNotEmpty) s += 1000;
        if (t.balanceAfter != null) s += 10;
        return s;
      }

      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa > sb ? a : b;

      final ia = int.tryParse(a.importId ?? '');
      final ib = int.tryParse(b.importId ?? '');
      if (ia != null && ib != null && ia != ib) {
        return ia < ib ? a : b;
      }

      return a;
    }

    var changed = false;
    final next = <String, List<Transaction>>{};
    for (final e in transactionsByAccount.entries) {
      final accountId = e.key;
      final list = e.value;
      final byKey = <String, Transaction>{};
      for (final t in list) {
        final k = transactionFingerprint(t);
        final existing = byKey[k];
        if (existing == null) {
          byKey[k] = t;
        } else {
          byKey[k] = pickBetter(existing, t);
          changed = true;
        }
      }
      next[accountId] = byKey.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (next[accountId]!.length != list.length) changed = true;
    }

    if (changed) {
      transactionsByAccount = next;
      await saveTransactionsByAccount(transactionsByAccount);

      final active = activeAccountId;
      if (active != null) {
        transactions = List.unmodifiable(transactionsByAccount[active] ?? const []);
      }
      _recomputeDerived(
        activeAccountTransactions: transactions,
        allTransactionsForMetrics: allTransactions,
        diag: null,
      );
      notifyListeners();
    }

    await setTransactionsDedupeMigrationDone();
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
    try {
      merchantCategoryMemory =
          await loadMerchantCategoryMemory(_userNamespaceForMerchantMemory());
    } on Object {
      merchantCategoryMemory = {};
    }
    notifyListeners();
  }

  void _persistMerchantCategoryMemory() {
    saveMerchantCategoryMemory(
      _userNamespaceForMerchantMemory(),
      merchantCategoryMemory,
    ).catchError((_) {});
  }

  /// Applies explicit category assignments, then learns merchant memory and backfills
  /// similar merchants. Returns the backfill batch for UI undo.
  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    _applyCategoryAssignments(keyToCanonicalCategory);
    return _learnAndBackfillMerchantMemory(keyToCanonicalCategory);
  }

  /// Learns merchant memory from explicit user picks, and backfills matching rows.
  ///
  /// Returns a batch of category changes that can be undone.
  List<AiAppliedCategoryChange> _learnAndBackfillMerchantMemory(
    Map<String, String> keyToCanonicalCategory,
  ) {
    if (keyToCanonicalCategory.isEmpty) return const [];

    // Map merchantKeyLower -> chosen category (last write wins within this save).
    final merchantUpdates = <String, String>{};
    final txByKey = <String, Transaction>{};
    for (final t in allTransactions) {
      txByKey[transactionCategoryKey(t)] = t;
    }
    for (final e in keyToCanonicalCategory.entries) {
      final t = txByKey[e.key];
      if (t == null) continue;
      final mk = transactionMerchantKeyLower(t).trim().toLowerCase();
      if (mk.isEmpty) continue;
      merchantUpdates[mk] = e.value.trim();
    }
    if (merchantUpdates.isEmpty) return const [];

    // Persist merchant memory.
    final nextMemory = Map<String, String>.from(merchantCategoryMemory);
    for (final e in merchantUpdates.entries) {
      final k = e.key.trim().toLowerCase();
      final v = e.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      nextMemory[k] = v;
    }
    merchantCategoryMemory = nextMemory;
    _persistMerchantCategoryMemory();

    // Backfill: apply to all matching transactions (with undo info).
    final toApply = <String, String>{};
    final undo = <AiAppliedCategoryChange>[];
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final t in allTransactions) {
      final mk = transactionMerchantKeyLower(t).trim().toLowerCase();
      final target = merchantUpdates[mk];
      if (target == null || target.isEmpty) continue;

      final key = transactionCategoryKey(t);
      if (keyToCanonicalCategory.containsKey(key)) continue; // already set explicitly in this save

      final current = transactionCategoryAssignments[key]?.trim();
      if (current != null && current == target) continue;

      toApply[key] = target;
      undo.add(
        AiAppliedCategoryChange(
          key: key,
          previousCategoryId: current,
          newCategoryId: target,
          appliedAtIso: nowIso,
        ),
      );
    }

    if (toApply.isEmpty) return const [];
    _applyCategoryAssignments(toApply);
    return undo;
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
      nextByAccount[e.key] =
          List.unmodifiable(e.value.map(applyCategory).toList());
    }
    transactionsByAccount = nextByAccount;

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    refreshAllState();
  }

  Future<int> undoCategoryApplyBatch(List<AiAppliedCategoryChange> batch) async {
    if (batch.isEmpty) return 0;

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryOverrides);

    var undone = 0;
    for (final c in batch) {
      final current = nextAssign[c.key]?.trim();
      if (current == null || current.isEmpty) continue;
      if (current != c.newCategoryId) continue;

      if (c.previousCategoryId == null || c.previousCategoryId!.trim().isEmpty) {
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
      nextByAccount[e.key] =
          List.unmodifiable(e.value.map(applyCategory).toList());
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

    final removedTransactions = transactionsByAccount[id] ?? const <Transaction>[];
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
    saveTransactionCategoryAssignments(transactionCategoryAssignments)
        .catchError((_) {});
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

    final nextAssignments = Map<String, String>.from(transactionCategoryAssignments)
      ..removeWhere((k, _) => keys.contains(k));
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
      diag: null,
    );
    notifyListeners();
  }

  /// Deletes a single transaction row and refreshes derived dashboard state.
  Future<bool> deleteTransaction(Transaction transaction) async {
    final key = transactionCategoryKey(transaction);
    if (key.trim().isEmpty) return false;

    final nextByAccount = <String, List<Transaction>>{};
    var removed = false;
    for (final e in transactionsByAccount.entries) {
      final nextList = <Transaction>[];
      for (final t in e.value) {
        if (transactionCategoryKey(t) == key) {
          removed = true;
          continue;
        }
        nextList.add(t);
      }
      nextByAccount[e.key] = List.unmodifiable(nextList);
    }
    if (!removed) return false;

    transactionsByAccount = nextByAccount;
    _removeTransactionMetadataForKeys({key});

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return true;
  }

  /// Deletes all transactions for one account and refreshes derived dashboard state.
  Future<int> clearTransactionsForAccount(String accountId) async {
    final id = accountId.trim();
    if (id.isEmpty) return 0;
    final existing = transactionsByAccount[id] ?? const [];
    if (existing.isEmpty) return 0;

    final removedKeys = existing.map(transactionCategoryKey).toSet();
    final nextByAccount = <String, List<Transaction>>{
      for (final e in transactionsByAccount.entries)
        e.key: e.key == id ? const <Transaction>[] : List.unmodifiable(e.value),
    };

    transactionsByAccount = nextByAccount;
    _removeTransactionMetadataForKeys(removedKeys);

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return removedKeys.length;
  }

  List<CsvImportBatchSummary> csvImportBatchesForAccount(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final accountTxs = transactionsByAccount[id] ?? const <Transaction>[];
    if (accountTxs.isEmpty) return const [];

    final counts = <String, int>{};
    for (final t in accountTxs) {
      final importId = t.importId?.trim();
      if (importId == null || importId.isEmpty) continue;
      counts[importId] = (counts[importId] ?? 0) + 1;
    }
    final out = <CsvImportBatchSummary>[];
    for (final e in counts.entries) {
      final micros = int.tryParse(e.key);
      final importedAtUtc = micros == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
      out.add(
        CsvImportBatchSummary(
          importId: e.key,
          transactionCount: e.value,
          importedAtUtc: importedAtUtc,
        ),
      );
    }
    out.sort((a, b) {
      final ai = a.importedAtUtc?.microsecondsSinceEpoch;
      final bi = b.importedAtUtc?.microsecondsSinceEpoch;
      if (ai != null && bi != null && ai != bi) return bi.compareTo(ai);
      return b.importId.compareTo(a.importId);
    });
    return out;
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    final id = accountId.trim();
    final targetImportId = importId.trim();
    if (id.isEmpty || targetImportId.isEmpty) return 0;

    final existing = transactionsByAccount[id] ?? const <Transaction>[];
    if (existing.isEmpty) return 0;

    final kept = <Transaction>[];
    final removed = <Transaction>[];
    for (final t in existing) {
      if ((t.importId?.trim() ?? '') == targetImportId) {
        removed.add(t);
      } else {
        kept.add(t);
      }
    }
    if (removed.isEmpty) return 0;

    final removedKeys = removed.map(transactionCategoryKey).toSet();
    final nextByAccount = <String, List<Transaction>>{
      for (final e in transactionsByAccount.entries)
        e.key: e.key == id ? List.unmodifiable(kept) : List.unmodifiable(e.value),
    };

    transactionsByAccount = nextByAccount;
    _removeTransactionMetadataForKeys(removedKeys);

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    _persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return removed.length;
  }

  List<Transaction> uncategorizedImportedRowsGlobal() {
    final accountsById = {for (final a in accounts) a.id: a};
    final all = allTransactions;
    final kept = all.where(isBankStatementDataRow).toList();
    final resolved = transaction_resolution.resolveTransactions(
      kept,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      accountsById: accountsById,
      allTransactions: all,
    );
    return resolved
        .where((r) => r.needsCategorization)
        .map((r) => r.transaction)
        .toList();
  }

  Future<({int applied, int queuedForReview})> autoCategorizeGlobalUncategorized({
    required AICategorizationService service,
    double autoApplyConfidenceThreshold = 0.90,
  }) async {
    final allowed = allowedCategoryPickerLabels;
    final unc = uncategorizedImportedRowsGlobal();
    if (unc.isEmpty) return (applied: 0, queuedForReview: 0);

    final expectedKeys = unc.map(transactionCategoryKey).toSet();

    // Never override manual choices.
    final toFetch = <Transaction>[];
    for (final t in unc) {
      final k = transactionCategoryKey(t);
      final alreadyAssigned = transactionCategoryAssignments[k]?.trim();
      if (alreadyAssigned != null && alreadyAssigned.isNotEmpty) continue;

      final cached = aiCategorySuggestions[k];
      if (cached != null && cached.promptVersion == _aiPromptVersion) {
        final cat = cached.suggestedCanonical?.trim();
        final hasUsefulSuggestion = cat != null && cat.isNotEmpty && cached.confidence > 0.0;
        if (hasUsefulSuggestion) continue;
      }
      toFetch.add(t);
    }

    if (kDebugMode) {
      debugPrint(
        '[Clarity][AI] uncategorized=${unc.length} toFetch=${toFetch.length} '
        'allowed=${allowed.length} promptV=$_aiPromptVersion',
      );
    }

    if (toFetch.isNotEmpty) {
      final fetched = await service.suggestCategoriesWithConfidence(
        transactions: toFetch,
        allowedCategoryIds: allowed,
        promptVersion: _aiPromptVersion,
      );
      if (fetched.isNotEmpty) {
        aiCategorySuggestions = {...aiCategorySuggestions, ...fetched};
        await _persistAiCategorySuggestions();
      }
      if (kDebugMode) {
        debugPrint('[Clarity][AI] fetched=${fetched.length}');
      }
    }

    final apply = <String, String>{};
    final batch = <AiAppliedCategoryChange>[];
    var review = 0;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final k in expectedKeys) {
      final alreadyAssigned = transactionCategoryAssignments[k]?.trim();
      if (alreadyAssigned != null && alreadyAssigned.isNotEmpty) continue;

      final s = aiCategorySuggestions[k];
      if (s == null || s.promptVersion != _aiPromptVersion) continue;
      final cat = s.suggestedCanonical?.trim();
      if (cat == null || cat.isEmpty) continue;
      if (!allowed.contains(cat)) continue;

      if (s.confidence >= autoApplyConfidenceThreshold) {
        apply[k] = cat;
        batch.add(
          AiAppliedCategoryChange(
            key: k,
            previousCategoryId: null,
            newCategoryId: cat,
            appliedAtIso: nowIso,
          ),
        );
      } else {
        review += 1;
      }
    }

    if (apply.isNotEmpty) {
      bulkSetCategoryOverrides(apply);
      await saveLastAiApplyBatch(batch);
    }

    return (applied: apply.length, queuedForReview: review);
  }

  Future<int> undoLastAiAutoApply() async {
    final batch = await loadLastAiApplyBatch();
    if (batch.isEmpty) return 0;

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryOverrides);

    var undone = 0;
    for (final c in batch) {
      final current = nextAssign[c.key]?.trim();
      if (current == null || current.isEmpty) continue;
      if (current != c.newCategoryId) continue;

      if (c.previousCategoryId == null || c.previousCategoryId!.trim().isEmpty) {
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
      nextByAccount[e.key] =
          List.unmodifiable(e.value.map(applyCategory).toList());
    }
    transactionsByAccount = nextByAccount;

    final active = activeAccountId;
    if (active != null) {
      transactions = List.unmodifiable(transactionsByAccount[active] ?? const []);
    }

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();

    await saveLastAiApplyBatch(const []);
    return undone;
  }

  /// Single entry for effective spend grouping (saved categoryId → override map → rules → CSV / keywords).
  String effectiveSpendGroupLabel(Transaction t) {
    return resolveTransaction(t, allTransactionsContext: allTransactions)
        .canonicalCategory;
  }

  /// Display label after renames — use for UI and "is Uncategorized?" checks on this app’s state.
  String effectiveCategoryDisplayLabel(Transaction t) {
    return resolveTransaction(t, allTransactionsContext: allTransactions)
        .displayCategory;
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
    return switch (scope) {
      GlobalDashboardScope() => allTransactions,
      AccountDashboardScope(:final accountId) => List<Transaction>.from(
          transactionsByAccount[accountId] ?? const [],
        ),
    };
  }

  /// Uncategorized statement rows for [accountId] using the same rules as the dashboard.
  List<Transaction> uncategorizedImportedRowsForAccount(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final list = transactionsByAccount[id] ?? const [];
    return uncategorizedDataRowsForImport(
      accountTransactions: list,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
  }

  // Rules feature removed.

  String _dateKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDateKey(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  String budgetYearMonthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  /// Weekly period key uses the exact user-selected start date (not normalized).
  String budgetWeekStartKey(DateTime date) => _dateKey(date);

  String get activeBudgetYearMonth => budgetYearMonthKey(_spendReference);

  BudgetPeriodType get resolvedActiveBudgetPeriodType => activeBudgetPeriodType;

  String get resolvedActiveBudgetPeriodKey {
    final key = activeBudgetPeriodKey?.trim();
    if (key != null && key.isNotEmpty) return key;
    return switch (resolvedActiveBudgetPeriodType) {
      BudgetPeriodType.monthly => budgetYearMonthKey(DateTime.now()),
      BudgetPeriodType.weekly => budgetWeekStartKey(DateTime.now()),
      BudgetPeriodType.custom => '',
    };
  }

  void setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    activeBudgetPeriodType = type;
    activeBudgetPeriodKey = key;
    notifyListeners();
  }

  List<String> defaultBudgetYearMonths({DateTime? start}) {
    final base = start ?? DateTime.now();
    final out = <String>[];
    for (var i = 0; i < 12; i++) {
      final d = DateTime(base.year, base.month + i, 1);
      out.add(budgetYearMonthKey(d));
    }
    return out;
  }

  List<String> defaultBudgetWeeks({DateTime? start}) {
    final seed = start ?? DateTime.now();
    final base = DateTime(seed.year, seed.month, seed.day);
    final out = <String>[];
    for (var i = 0; i < 12; i++) {
      out.add(_dateKey(base.add(Duration(days: i * 7))));
    }
    return out;
  }

  List<String> budgetMonthsForPicker({DateTime? start}) {
    final defaults = defaultBudgetYearMonths(start: start);
    final extras = categoryMonthlyBudgetsByYearMonth.keys
        .where((k) => !defaults.contains(k))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return [...defaults, ...extras];
  }

  List<String> budgetWeeksForPicker({DateTime? start}) {
    final defaults = defaultBudgetWeeks(start: start);
    final extras = categoryWeeklyBudgetsByWeekStart.keys
        .where((k) => !defaults.contains(k))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return [...defaults, ...extras];
  }

  List<String> customBudgetKeysForPicker() {
    final keys = customBudgetRangesByKey.keys.toList();
    keys.sort((a, b) {
      final ra = customBudgetRangesByKey[a];
      final rb = customBudgetRangesByKey[b];
      if (ra == null && rb == null) return a.compareTo(b);
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.start.compareTo(ra.start);
    });
    return keys;
  }

  String customBudgetKeyForRange(DateTime start, DateTime end) {
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    final lo = a.isBefore(b) ? a : b;
    final hi = a.isBefore(b) ? b : a;
    return '${_dateKey(lo)}_${_dateKey(hi)}';
  }

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) {
    final key = customBudgetKeyForRange(start, end);
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    final lo = a.isBefore(b) ? a : b;
    final hi = a.isBefore(b) ? b : a;
    customBudgetRangesByKey = {
      ...customBudgetRangesByKey,
      key: BudgetPeriodRange(start: lo, end: hi),
    };
    return key;
  }

  Map<String, double> monthlyBudgetsForYearMonth(String yearMonth) {
    return Map<String, double>.from(
      categoryMonthlyBudgetsByYearMonth[yearMonth] ?? const {},
    );
  }

  Map<String, double> budgetsForPeriod({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    final raw = switch (periodType) {
      BudgetPeriodType.monthly =>
        categoryMonthlyBudgetsByYearMonth[periodKey] ?? const {},
      BudgetPeriodType.weekly =>
        categoryWeeklyBudgetsByWeekStart[periodKey] ?? const {},
      BudgetPeriodType.custom => categoryCustomBudgetsByKey[periodKey] ?? const {},
    };
    return Map<String, double>.from(raw);
  }

  double? budgetForDisplayLabel({
    required String displayLabel,
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return budgetsForPeriod(periodType: periodType, periodKey: periodKey)[
      budgetDisplayKey(displayLabel)
    ];
  }

  double? monthlyBudgetForDisplayLabel(
    String displayLabel, {
    String? yearMonth,
  }) {
    final ym = yearMonth ?? activeBudgetYearMonth;
    return budgetForDisplayLabel(
      displayLabel: displayLabel,
      periodType: BudgetPeriodType.monthly,
      periodKey: ym,
    );
  }

  BudgetPeriodRange? budgetPeriodRangeFor({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return switch (periodType) {
      BudgetPeriodType.monthly => _monthRangeFromKey(periodKey),
      BudgetPeriodType.weekly => _weekRangeFromKey(periodKey),
      BudgetPeriodType.custom => customBudgetRangesByKey[periodKey],
    };
  }

  String budgetPeriodLabel({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    final range = budgetPeriodRangeFor(
      periodType: periodType,
      periodKey: periodKey,
    );
    if (range == null) return periodKey;
    return switch (periodType) {
      BudgetPeriodType.monthly => formatYearMonthLabel(budgetYearMonthKey(range.start)),
      BudgetPeriodType.weekly =>
        '${formatShortDate(range.start)} – ${formatShortDate(range.end)}',
      BudgetPeriodType.custom =>
        '${formatShortDate(range.start)} – ${formatShortDate(range.end)}',
    };
  }

  BudgetPeriodRange? _monthRangeFromKey(String yearMonth) {
    final parts = yearMonth.split('-');
    final y = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final m = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (y == null || m == null || m < 1 || m > 12) return null;
    final start = DateTime(y, m, 1);
    final end = DateTime(y, m + 1, 0);
    return BudgetPeriodRange(start: start, end: end);
  }

  BudgetPeriodRange? _weekRangeFromKey(String weekStartKey) {
    final start = _parseDateKey(weekStartKey);
    if (start == null) return null;
    final end = start.add(const Duration(days: 6));
    return BudgetPeriodRange(start: start, end: end);
  }

  bool _inRangeInclusive(DateTime d, DateTime start, DateTime end) {
    final x = DateTime(d.year, d.month, d.day);
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    return (x.isAtSameMomentAs(a) || x.isAfter(a)) &&
        (x.isAtSameMomentAs(b) || x.isBefore(b));
  }

  /// Actual spend totals for the selected month grouped by display category label.
  ///
  /// Values are positive spend amounts (outflows that count as spend).
  Map<String, double> spentByDisplayCategoryForScope(
    DashboardScope scope, {
    DateTime? reference,
  }) {
    final ref = reference ?? DateTime.now();
    final start = DateTime(ref.year, ref.month, 1);
    final end = DateTime(ref.year, ref.month + 1, 0);
    return spentByDisplayCategoryForScopeInRange(
      scope,
      start: start,
      end: end,
    );
  }

  Map<String, double> spentByDisplayCategoryForScopeInRange(
    DashboardScope scope, {
    required DateTime start,
    required DateTime end,
  }) {
    final scoped = transactionsForDashboardScope(scope);
    final all = allTransactions;
    final resolved = resolveTransactions(
      scoped,
      allTransactionsContext: all,
    );
    final out = <String, double>{};
    for (final r in resolved) {
      final t = r.transaction;
      if (!_inRangeInclusive(t.date, start, end)) continue;
      if (!r.countsAsSpend) continue;
      final display = r.displayCategory;
      if (isIgnoredCategoryLabel(display) || isIncomeCategoryLabel(display)) {
        continue;
      }
      out[display] = (out[display] ?? 0) + (-t.amount);
    }
    return out;
  }

  Map<String, double> spentThisMonthByDisplayCategory({DateTime? reference}) {
    return spentByDisplayCategoryForScope(
      const GlobalDashboardScope(),
      reference: reference,
    );
  }

  BudgetPerformanceSnapshot budgetPerformanceForScope(
    DashboardScope scope, {
    BudgetPeriodType? periodType,
    String? periodKey,
  }) {
    final type = periodType ?? resolvedActiveBudgetPeriodType;
    final key = (periodKey ?? resolvedActiveBudgetPeriodKey).trim();
    final fallbackType = BudgetPeriodType.monthly;
    final fallbackKey = budgetYearMonthKey(DateTime.now());
    final effectiveType = key.isEmpty ? fallbackType : type;
    final effectiveKey = key.isEmpty ? fallbackKey : key;
    final range = budgetPeriodRangeFor(
          periodType: effectiveType,
          periodKey: effectiveKey,
        ) ??
        _monthRangeFromKey(fallbackKey)!;
    final budgets = budgetsForPeriod(
      periodType: effectiveType,
      periodKey: effectiveKey,
    );
    final displayByBudgetKey = <String, String>{};
    final canonicals = categoryPickerCanonicals(
      customCategories: customCategories,
      hiddenLower: categoriesHiddenFromPicker,
    );
    for (final canonical in canonicals) {
      final display = applyCategoryDisplayRenames(
        canonical,
        categoryDisplayRenames,
      );
      displayByBudgetKey[budgetDisplayKey(display)] = display;
    }
    final spentByDisplay = spentByDisplayCategoryForScopeInRange(
      scope,
      start: range.start,
      end: range.end,
    );
    final spentByBudgetKey = <String, double>{};
    for (final e in spentByDisplay.entries) {
      spentByBudgetKey[budgetDisplayKey(e.key)] = e.value;
    }

    var totalBudgeted = 0.0;
    var totalSpent = 0.0;
    var onTrackCount = 0;
    final overspending = <BudgetCategoryPerformance>[];
    for (final e in budgets.entries) {
      final budgeted = e.value;
      final budgetKey = e.key;
      final display = displayByBudgetKey[budgetKey] ?? budgetKey;
      final spent = spentByBudgetKey[budgetKey] ?? 0.0;
      totalBudgeted += budgeted;
      totalSpent += spent;
      final stat = BudgetCategoryPerformance(
        displayLabel: display,
        budgeted: budgeted,
        spent: spent,
      );
      if (stat.onTrack) {
        onTrackCount += 1;
      } else {
        overspending.add(stat);
      }
    }
    overspending.sort((a, b) => b.overspent.compareTo(a.overspent));
    final totalOverspent = overspending.fold<double>(
      0,
      (sum, row) => sum + row.overspent,
    );
    return BudgetPerformanceSnapshot(
      periodType: effectiveType,
      periodKey: effectiveKey,
      periodLabel: budgetPeriodLabel(
        periodType: effectiveType,
        periodKey: effectiveKey,
      ),
      totalBudgeted: totalBudgeted,
      totalSpent: totalSpent,
      budgetedCategoryCount: budgets.length,
      onTrackCategoryCount: onTrackCount,
      totalOverspent: totalOverspent,
      topOverspendingCategories: overspending.take(2).toList(),
    );
  }

  /// Applies visible-row budget edits for one period (persist-then-commit).
  ///
  /// [draftByNormalizedDisplayKey] keys must already be [budgetDisplayKey] outputs.
  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    final nextByMonth = <String, Map<String, double>>{
      for (final e in categoryMonthlyBudgetsByYearMonth.entries)
        e.key: Map<String, double>.from(e.value),
    };
    final nextByWeek = <String, Map<String, double>>{
      for (final e in categoryWeeklyBudgetsByWeekStart.entries)
        e.key: Map<String, double>.from(e.value),
    };
    final nextByCustom = <String, Map<String, double>>{
      for (final e in categoryCustomBudgetsByKey.entries)
        e.key: Map<String, double>.from(e.value),
    };
    final nextCustomRanges = <String, BudgetPeriodRange>{
      ...customBudgetRangesByKey,
    };

    final target = switch (periodType) {
      BudgetPeriodType.monthly =>
        Map<String, double>.from(nextByMonth[periodKey] ?? const {}),
      BudgetPeriodType.weekly =>
        Map<String, double>.from(nextByWeek[periodKey] ?? const {}),
      BudgetPeriodType.custom =>
        Map<String, double>.from(nextByCustom[periodKey] ?? const {}),
    };
    for (final e in draftByNormalizedDisplayKey.entries) {
      final value = e.value;
      if (value == null || !value.isFinite || value < 0) {
        target.remove(e.key);
      } else {
        target[e.key] = value;
      }
    }

    switch (periodType) {
      case BudgetPeriodType.monthly:
        if (target.isEmpty) {
          nextByMonth.remove(periodKey);
        } else {
          nextByMonth[periodKey] = target;
        }
        break;
      case BudgetPeriodType.weekly:
        if (target.isEmpty) {
          nextByWeek.remove(periodKey);
        } else {
          nextByWeek[periodKey] = target;
        }
        break;
      case BudgetPeriodType.custom:
        if (target.isEmpty) {
          nextByCustom.remove(periodKey);
        } else {
          nextByCustom[periodKey] = target;
        }
        nextCustomRanges[periodKey] ??=
            budgetPeriodRangeFor(
              periodType: BudgetPeriodType.custom,
              periodKey: periodKey,
            ) ??
            BudgetPeriodRange(start: DateTime.now(), end: DateTime.now());
        break;
    }
    try {
      final storageRanges = <String, BudgetStorageRange>{};
      for (final e in nextCustomRanges.entries) {
        storageRanges[e.key] = BudgetStorageRange(
          start: e.value.start,
          end: e.value.end,
        );
      }
      await saveBudgetSnapshot(
        BudgetStorageSnapshot(
          monthly: nextByMonth,
          weekly: nextByWeek,
          custom: nextByCustom,
          customRanges: storageRanges,
        ),
      );
    } on Object {
      return false;
    }
    categoryMonthlyBudgetsByYearMonth = nextByMonth;
    categoryWeeklyBudgetsByWeekStart = nextByWeek;
    categoryCustomBudgetsByKey = nextByCustom;
    customBudgetRangesByKey = nextCustomRanges;
    activeBudgetPeriodType = periodType;
    activeBudgetPeriodKey = periodKey;
    refreshAllState();
    return true;
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

  /// Loads and aggregates using [reference] for "this month" (defaults to now, local).
  ///
  /// [accountId] must match a persisted [accounts] entry (set after [hydratePersistedAccounts]).
  void loadFromCsv(
    String utf8Text, {
    required String accountId,
    DateTime? reference,
  }) {
    final id = accountId.trim();
    if (id.isEmpty) {
      throw const FormatException('An account must be selected.');
    }
    if (!accounts.any((a) => a.id == id)) {
      throw const FormatException('Unknown account.');
    }
    final ref = reference ?? DateTime.now();
    _spendReference = ref;
    activeAccountId = id;
    categoryOverrides = const {};
    // Keep [categoryDisplayRenames] and [categoriesHiddenFromPicker] across imports
    // so built-in display renames and picker preferences persist (same as budgets/rules).
    final result = parseBankCsv(utf8Text);
    final importId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();

    final existing = List<Transaction>.from(transactionsByAccount[id] ?? const []);
    final existingFingerprints = <String>{};
    for (final t in existing) {
      // Always use the current stable identity key for dedupe, regardless of
      // what might have been stored historically in [fingerprint].
      existingFingerprints.add(transactionFingerprint(t));
    }

    final stampedNew = <Transaction>[];
    var skipped = 0;
    for (final t in result.transactions) {
      final base = Transaction(
        date: t.date,
        description: t.description,
        amount: t.amount,
        accountId: id,
        category: t.category,
        balanceAfter: t.balanceAfter,
        categoryId: null,
        importId: importId,
      );
      final key = transactionCategoryKey(base);
      final persisted = transactionCategoryAssignments[key]?.trim();
      final cid = (persisted != null && persisted.isNotEmpty) ? persisted : null;
      final withCid = Transaction(
        date: base.date,
        description: base.description,
        amount: base.amount,
        accountId: base.accountId,
        category: base.category,
        balanceAfter: base.balanceAfter,
        categoryId: cid,
        importId: base.importId,
      );
      final fp = transactionFingerprint(withCid);
      if (existingFingerprints.contains(fp)) {
        skipped += 1;
        continue;
      }
      existingFingerprints.add(fp);
      stampedNew.add(
        Transaction(
          date: withCid.date,
          description: withCid.description,
          amount: withCid.amount,
          accountId: withCid.accountId,
          category: withCid.category,
          balanceAfter: withCid.balanceAfter,
          categoryId: withCid.categoryId,
          importId: withCid.importId,
          fingerprint: fp,
        ),
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[Clarity][Import dedupe] existing=${existing.length}, '
        'parsed=${result.transactions.length}, '
        'added=${stampedNew.length}, '
        'skipped=$skipped',
      );
    }

    final merged = [...existing, ...stampedNew];
    transactionsByAccount = {...transactionsByAccount, id: List.unmodifiable(merged)};
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});

    transactions = List.unmodifiable(merged);
    totalBalance = resolveTotalBalance(transactions, result.totalBalance);
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: result.diagnostics,
    );
    notifyListeners();
    _persistCategoryCatalog();
  }

  void _persistActiveAccountTransactionsIfAny() {
    final id = activeAccountId;
    if (id == null || id.trim().isEmpty) return;
    if (!transactionsByAccount.containsKey(id)) return;
    transactionsByAccount = {...transactionsByAccount, id: transactions};
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
  }

  /// Assigns a category to a transaction and refreshes aggregates.
  void setCategoryOverride(Transaction t, String category) {
    final key = transactionCategoryKey(t);
    final cat = category.trim();
    applyCategoriesWithMerchantLearning({key: cat});
  }

  /// Assigns categories for many [transactionCategoryKey]s at once (persists [categoryId] on each row).
  void bulkSetCategoryOverrides(Map<String, String> keyToCanonicalCategory) {
    applyCategoriesWithMerchantLearning(keyToCanonicalCategory);
  }

  /// Adds a new category name (if needed), assigns [t], and notifies.
  void createCategoryAndAssign(Transaction t, String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    if (name.toLowerCase() == 'uncategorized') return;
    if (isIgnoredCategoryLabel(name)) return;
    if (!isBuiltInSpendCategory(name) && !customCategories.contains(name)) {
      customCategories = [...customCategories, name];
      _persistCategoryCatalog();
    }
    setCategoryOverride(t, name);
  }

  /// Deletes a category from the picker and clears assignments using it (any label, built-in or custom).
  void deleteCategory(String canonicalLabel) {
    final k = canonicalLabel.trim().toLowerCase();
    if (k.isEmpty) return;

    customCategories = customCategories
        .where((c) => c.trim().toLowerCase() != k)
        .toList();

    if (kSelectableSpendCategories.any((c) => c.toLowerCase() == k)) {
      categoriesHiddenFromPicker = {...categoriesHiddenFromPicker, k};
    }

    final nextRenames = Map<String, String>.from(categoryDisplayRenames);
    nextRenames.remove(k);
    categoryDisplayRenames = nextRenames;

    final next = <String, String>{};
    for (final e in categoryOverrides.entries) {
      if (e.value.trim().toLowerCase() != k) {
        next[e.key] = e.value;
      }
    }
    categoryOverrides = next;

    final nextAssign = <String, String>{};
    for (final e in transactionCategoryAssignments.entries) {
      if (e.value.trim().toLowerCase() != k) {
        nextAssign[e.key] = e.value;
      }
    }
    transactionCategoryAssignments = nextAssign;
    transactions = List.unmodifiable(
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
    _persistActiveAccountTransactionsIfAny();
    _persistTransactionCategoryAssignments();
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();
    _persistCategoryCatalog();
  }

  /// Renames a category. Built-ins: display-only map (overrides stay canonical). Custom: text + overrides.
  void renameCategory(String oldLabel, String newLabel) {
    final oldK = oldLabel.trim().toLowerCase();
    final newN = newLabel.trim();
    if (newN.isEmpty || oldK == newN.toLowerCase()) return;

    final isBuiltIn = kSelectableSpendCategories.any(
      (c) => c.toLowerCase() == oldK,
    );
    if (isBuiltIn) {
      categoryDisplayRenames = {...categoryDisplayRenames, oldK: newN};
    } else {
      final nextOv = <String, String>{};
      for (final e in categoryOverrides.entries) {
        if (e.value.trim().toLowerCase() == oldK) {
          nextOv[e.key] = newN;
        } else {
          nextOv[e.key] = e.value;
        }
      }
      categoryOverrides = nextOv;

      final nextAssign = <String, String>{};
      for (final e in transactionCategoryAssignments.entries) {
        if (e.value.trim().toLowerCase() == oldK) {
          nextAssign[e.key] = newN;
        } else {
          nextAssign[e.key] = e.value;
        }
      }
      transactionCategoryAssignments = nextAssign;

      customCategories = customCategories
          .map((c) => c.trim().toLowerCase() == oldK ? newN : c)
          .toList();

      transactions = List.unmodifiable(
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
      _persistActiveAccountTransactionsIfAny();
      _persistTransactionCategoryAssignments();
    }

    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();
    _persistCategoryCatalog();
  }

  void _recomputeDerived({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required CsvParseDiagnostics? diag,
  }) {
    spentThisMonth = _spentThisMonth(
      allTransactionsForMetrics,
      accounts,
      _spendReference,
      categoryOverrides,
    );
    incomeThisMonth = totalIncomeInMonth(
      allTransactionsForMetrics,
      accounts,
      _spendReference,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
    availableThisMonth = incomeThisMonth - spentThisMonth;
    uncategorizedCount = resolveTransactions(
      allTransactionsForMetrics,
      allTransactionsContext: allTransactionsForMetrics,
    ).where((r) => r.needsCategorization).length;
    biggestLeaksThisMonth = List.unmodifiable(
      biggestCategoryLeaks(
        allTransactionsForMetrics,
        accounts,
        _spendReference,
        limit: 3,
        categoryOverrides: categoryOverrides,
        categoryDisplayRenamesLower: categoryDisplayRenames,
      ),
    );
    burnRunwayDays = runwayDaysFromBurnRate(
      totalBalance: totalBalance,
      spentThisMonth: spentThisMonth,
      referenceInMonth: _spendReference,
    );
    topCategories = List.unmodifiable(
      _topCategoriesThisMonth(
        allTransactionsForMetrics,
        accounts,
        _spendReference,
        5,
        categoryOverrides,
        categoryDisplayRenames,
      ),
    );
    final grouped = monthlyGroupsFromTransactions(
      activeAccountTransactions,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
    monthlyGroups = List.unmodifiable(grouped.reversed.toList());
    if (kDebugMode && diag != null) {
      _debugPrintCsvImportDiagnostics(transactions, grouped, diag);
    }
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

/// Outflows in the calendar month of [reference] in the local timezone.
///
/// Omits rows whose effective spend group is [kIgnoredCategoryLabel].
double _spentThisMonth(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime reference,
  Map<String, String> categoryOverrides,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final resolved = transaction_resolution.resolveTransactions(
    txs,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: const {},
    accountsById: accountsById,
    allTransactions: txs,
  );
  final y = reference.year;
  final m = reference.month;
  var sum = 0.0;
  for (final r in resolved) {
    final t = r.transaction;
    final d = t.date;
    if (d.year != y || d.month != m || !t.isOutflow) continue;
    if (!r.countsAsSpend) continue;
    sum += -t.amount;
  }
  return sum;
}

bool _inMonth(DateTime d, DateTime reference) {
  return d.year == reference.year && d.month == reference.month;
}

List<CategorySpend> _topCategoriesThisMonth(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime reference,
  int limit,
  Map<String, String> categoryOverrides,
  Map<String, String> categoryDisplayRenamesLower,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final resolved = transaction_resolution.resolveTransactions(
    txs,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
    accountsById: accountsById,
    allTransactions: txs,
  );
  final map = <String, double>{};
  for (final r in resolved) {
    final t = r.transaction;
    if (!_inMonth(t.date, reference)) continue;
    if (!r.countsAsSpend) continue;
    final name = r.displayCategory;
    if (isIgnoredCategoryLabel(name)) continue;
    map[name] = (map[name] ?? 0) + (-t.amount);
  }
  final list =
      map.entries
          .map((e) => CategorySpend(name: e.key, amount: e.value))
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
  if (list.length <= limit) return list;
  return list.sublist(0, limit);
}

String _yearMonthKeyForDebug(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Temporary diagnostics for wrong month counts / stray months (remove when fixed).
void _debugPrintCsvImportDiagnostics(
  List<Transaction> txs,
  List<MonthlyBankGroup> groupsChronological,
  CsvParseDiagnostics diag,
) {
  debugPrint(
    '[Clarity][CSV import] Column layout: '
    '${diag.layoutInferred ? "INFERRED (no header match)" : "HEADER_MATCH"} '
    '| header row index (0-based): ${diag.headerRowIndex}',
  );
  debugPrint(
    '[Clarity][CSV import] Date column: index=${diag.dateColumnIndex} '
    'header="${diag.dateColumnHeader}"',
  );
  debugPrint(
    '[Clarity][CSV import] Amount column: index=${diag.amountColumnIndex} '
    'header="${diag.amountColumnHeader}"',
  );
  if (diag.balanceColumnIndex != null) {
    debugPrint(
      '[Clarity][CSV import] Balance column: index=${diag.balanceColumnIndex} '
      'header="${diag.balanceColumnHeader}"',
    );
  }
  debugPrint('[Clarity][CSV import] ${diag.ambiguousSlashPolicy}');
  if (diag.firstParsedDateRawCell != null) {
    debugPrint(
      '[Clarity][CSV import] First data row raw date cell: '
      '"${diag.firstParsedDateRawCell}" => ${diag.firstCellParsingRule}',
    );
  }
  if (diag.lastParsedDateRawCell != null) {
    debugPrint(
      '[Clarity][CSV import] Last data row raw date cell: '
      '"${diag.lastParsedDateRawCell}" => ${diag.lastCellParsingRule}',
    );
  }

  final jan2025Parsed = txs
      .where((t) => t.date.year == 2025 && t.date.month == 1)
      .length;
  debugPrint(
    '[Clarity][CSV import] Rows with parsed calendar date in January 2025: '
    '$jan2025Parsed (total parsed transaction rows: ${txs.length})',
  );

  MonthlyBankGroup? janGroup;
  for (final g in groupsChronological) {
    if (g.yearMonth == '2025-01') {
      janGroup = g;
      break;
    }
  }
  final inJanGroupAfterFilter = janGroup?.transactions.length ?? 0;
  debugPrint(
    '[Clarity][CSV import] Rows in monthly bucket 2025-01 after line filters '
    '(summary/balance skipped): $inJanGroupAfterFilter',
  );

  if (txs.isNotEmpty) {
    final f = txs.first;
    final l = txs.last;
    debugPrint(
      '[Clarity][CSV import] First row (file order): parsed date=${f.date} '
      '-> yearMonth key ${_yearMonthKeyForDebug(f.date)} | ${f.description}',
    );
    debugPrint(
      '[Clarity][CSV import] Last row (file order): parsed date=${l.date} '
      '-> yearMonth key ${_yearMonthKeyForDebug(l.date)} | ${l.description}',
    );
  }

  final dec2026Parsed = txs
      .where((t) => t.date.year == 2026 && t.date.month == 12)
      .length;
  debugPrint(
    '[Clarity][CSV import] Rows with parsed date in December 2026: '
    '$dec2026Parsed',
  );
}
