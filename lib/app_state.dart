import 'package:flutter/foundation.dart';

import 'account_storage.dart';
import 'balance_resolve.dart';
import 'bank_statement_monthly.dart';
import 'budget_keys.dart';
import 'budget_storage.dart';
import 'category_catalog_storage.dart';
import 'category_description_normalize.dart';
import 'category_rule.dart';
import 'category_rules_storage.dart';
import 'csv_parser.dart';
import 'dashboard_metrics.dart';
import 'financial_role.dart';
import 'models.dart';
import 'profile_storage.dart';
import 'spend_categories.dart';
import 'transaction_category_storage.dart';
import 'transaction_fingerprint.dart';
import 'transaction_storage.dart';
import 'uncategorized_for_ai.dart';

/// Holds parsed statement data and derived aggregates.
/// Monthly category budgets ([hydratePersistedBudgets] / [commitMonthlyBudgetDraft])
/// and description rules ([hydrateCategoryRules] / [addOrUpdateCategoryRuleByPattern])
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

  /// Newest calendar month first (from [monthlyGroupsFromTransactions]).
  List<MonthlyBankGroup> monthlyGroups = const [];

  /// Manual category by [transactionCategoryKey]; cleared when a new CSV is loaded.
  Map<String, String> categoryOverrides = const {};

  /// Persisted manual categories by [transactionCategoryKey]; survives restarts and re-import.
  Map<String, String> transactionCategoryAssignments = const {};

  /// User-created category names (shown in the assignment sheet alongside built-ins).
  List<String> customCategories = const [];

  /// Lowercase base label -> user display name (renamed built-ins / display tweaks).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Map<String, String> categoryDisplayRenames = const {};

  /// Lowercase canonical labels removed from the picker (deleted built-ins).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Set<String> categoriesHiddenFromPicker = {};

  /// Monthly budget amounts keyed by [budgetDisplayKey] of the **display** label
  /// (aligned with aggregate category names after renames).
  ///
  /// v1: no migration when display strings change — stale keys can remain until overwritten.
  /// [clear] / [loadFromCsv] do **not** clear this map.
  Map<String, double> categoryMonthlyBudgetsByDisplayLower = {};

  /// Description match rules (v1: contains, outflow-only). List order = first match wins.
  /// Not cleared by [loadFromCsv] or [clear] (user intent, like budgets).
  List<CategoryRule> categoryRules = const [];

  /// User-defined bank / card accounts (persisted separately from CSV rows).
  List<Account> accounts = const [];

  /// Reference month for "spent this month" / top categories (set in [loadFromCsv]).
  DateTime _spendReference = DateTime.now();

  /// Same instant used for monthly aggregates (defaults to import time / [loadFromCsv]).
  DateTime get spendReference => _spendReference;

  /// Loads persisted budgets from disk (call once before [runApp]).
  Future<void> hydratePersistedBudgets() async {
    try {
      categoryMonthlyBudgetsByDisplayLower = await loadBudgets();
    } on Object {
      categoryMonthlyBudgetsByDisplayLower = {};
    }
    notifyListeners();
  }

  /// Loads persisted category rules (call once before [runApp], after [AppState] exists).
  Future<void> hydrateCategoryRules() async {
    try {
      categoryRules = await loadCategoryRules();
    } on Object {
      categoryRules = const [];
    }
    notifyListeners();
  }

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
    notifyListeners();
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

  /// Single entry for effective spend grouping (saved categoryId → override map → rules → CSV / keywords).
  String effectiveSpendGroupLabel(Transaction t) {
    return spendGroupLabel(
      t,
      categoryOverrides: categoryOverrides,
      categoryRules: categoryRules,
    );
  }

  /// Built-in + custom categories shown in pickers (for AI allow-lists and review UI).
  List<String> get allowedCategoryPickerLabels => categoryPickerCanonicals(
        customCategories: customCategories,
        hiddenLower: categoriesHiddenFromPicker,
      );

  /// Uncategorized statement rows for [accountId] using the same rules as the dashboard.
  List<Transaction> uncategorizedImportedRowsForAccount(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final list = transactionsByAccount[id] ?? const [];
    return uncategorizedDataRowsForImport(
      accountTransactions: list,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      categoryRules: categoryRules,
    );
  }

  /// Normalized pattern must be at least 3 characters. Same pattern updates category.
  /// Persist-then-commit; returns false if validation or save fails.
  ///
  /// [sourceForNewRule] applies only when inserting a new rule; updates by same
  /// pattern preserve the existing rule’s [CategoryRule.source].
  Future<bool> addOrUpdateCategoryRuleByPattern(
    String patternRaw,
    String categoryCanonical, {
    CategoryRuleSource sourceForNewRule = CategoryRuleSource.learnedFromTransaction,
  }) async {
    final cat = categoryCanonical.trim();
    if (cat.isEmpty) return false;
    final p = normalizeDescriptionForMatching(patternRaw);
    if (p.length < 3) return false;

    final next = List<CategoryRule>.from(categoryRules);
    final i = next.indexWhere((r) => r.pattern == p);
    if (i >= 0) {
      next[i] = next[i].copyWith(categoryCanonical: cat);
    } else {
      next.add(
        CategoryRule(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          pattern: p,
          matchType: CategoryRule.matchTypeContains,
          categoryCanonical: cat,
          createdAt: DateTime.now().toUtc(),
          source: sourceForNewRule,
        ),
      );
    }
    try {
      await saveCategoryRules(next);
    } on Object {
      return false;
    }
    categoryRules = next;
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();
    return true;
  }

  /// Updates pattern and category for an existing rule by [id]. Sets
  /// [CategoryRuleSource.manualFromRules]. Fails if another rule already uses
  /// the normalized pattern.
  Future<bool> updateCategoryRuleById({
    required String id,
    required String patternRaw,
    required String categoryCanonical,
  }) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) return false;
    final cat = categoryCanonical.trim();
    if (cat.isEmpty) return false;
    final p = normalizeDescriptionForMatching(patternRaw);
    if (p.length < 3) return false;

    final next = List<CategoryRule>.from(categoryRules);
    final idx = next.indexWhere((r) => r.id == trimmedId);
    if (idx < 0) return false;

    final conflict = next.any(
      (r) => r.id != trimmedId && r.pattern == p,
    );
    if (conflict) return false;

    next[idx] = next[idx].copyWith(
      pattern: p,
      categoryCanonical: cat,
      source: CategoryRuleSource.manualFromRules,
    );
    try {
      await saveCategoryRules(next);
    } on Object {
      return false;
    }
    categoryRules = next;
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();
    return true;
  }

  /// Removes one rule by [id], persists, and recomputes aggregates.
  Future<bool> deleteCategoryRule(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    final next = categoryRules.where((r) => r.id != trimmed).toList();
    if (next.length == categoryRules.length) return false;
    try {
      await saveCategoryRules(next);
    } on Object {
      return false;
    }
    categoryRules = next;
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();
    return true;
  }

  double? monthlyBudgetForDisplayLabel(String displayLabel) =>
      categoryMonthlyBudgetsByDisplayLower[budgetDisplayKey(displayLabel)];

  /// Applies visible-row budget edits (persist-then-commit).
  ///
  /// [draftByNormalizedDisplayKey] keys must **already** be [budgetDisplayKey] outputs;
  /// this method does not re-normalize them. A `null` value removes that key.
  /// Non-finite or negative values in the draft remove the key.
  ///
  /// Merge rule: starts from a **full copy** of [categoryMonthlyBudgetsByDisplayLower],
  /// then applies only the draft entries. Orphan / hidden-category keys not in the
  /// draft stay untouched — never rebuild the stored map from visible rows only.
  Future<bool> commitMonthlyBudgetDraft(
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    final next = Map<String, double>.from(categoryMonthlyBudgetsByDisplayLower);
    for (final e in draftByNormalizedDisplayKey.entries) {
      final v = e.value;
      if (v == null || !v.isFinite || v < 0) {
        next.remove(e.key);
      } else {
        next[e.key] = v;
      }
    }
    try {
      await saveBudgets(next);
    } on Object {
      return false;
    }
    categoryMonthlyBudgetsByDisplayLower = next;
    notifyListeners();
    return true;
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
      final fp = t.fingerprint;
      if (fp != null && fp.isNotEmpty) existingFingerprints.add(fp);
    }

    final stampedNew = <Transaction>[];
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
      if (existingFingerprints.contains(fp)) continue;
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
    transactionCategoryAssignments = {
      ...transactionCategoryAssignments,
      key: cat,
    };
    final next = Map<String, String>.from(categoryOverrides);
    next[key] = cat;
    categoryOverrides = next;
    transactions = List.unmodifiable(
      transactions.map((x) {
        if (transactionCategoryKey(x) != key) return x;
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
  }

  /// Assigns categories for many [transactionCategoryKey]s at once (persists [categoryId] on each row).
  void bulkSetCategoryOverrides(Map<String, String> keyToCanonicalCategory) {
    if (keyToCanonicalCategory.isEmpty) return;
    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryOverrides);
    for (final e in keyToCanonicalCategory.entries) {
      final k = e.key.trim();
      final v = e.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      nextAssign[k] = v;
      nextOv[k] = v;
    }
    transactionCategoryAssignments = nextAssign;
    categoryOverrides = nextOv;

    Transaction applyCategory(Transaction x) {
      final k = transactionCategoryKey(x);
      final cat = keyToCanonicalCategory[k];
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

    final active = activeAccountId;
    if (active != null) {
      transactions =
          List.unmodifiable(transactionsByAccount[active] ?? const []);
    }

    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    _persistTransactionCategoryAssignments();
    _recomputeDerived(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      diag: null,
    );
    notifyListeners();
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
      categoryRules,
    );
    incomeThisMonth = totalIncomeInMonth(
      allTransactionsForMetrics,
      accounts,
      _spendReference,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      categoryRules: categoryRules,
    );
    availableThisMonth = incomeThisMonth - spentThisMonth;
    uncategorizedCount = uncategorizedTransactionCount(
      activeAccountTransactions,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      categoryRules: categoryRules,
    );
    biggestLeaksThisMonth = List.unmodifiable(
      biggestCategoryLeaks(
        allTransactionsForMetrics,
        accounts,
        _spendReference,
        limit: 3,
        categoryOverrides: categoryOverrides,
        categoryDisplayRenamesLower: categoryDisplayRenames,
        categoryRules: categoryRules,
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
        categoryRules,
      ),
    );
    final grouped = monthlyGroupsFromTransactions(
      activeAccountTransactions,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      categoryRules: categoryRules,
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
  List<CategoryRule> categoryRules,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final y = reference.year;
  final m = reference.month;
  var sum = 0.0;
  for (final t in txs) {
    final d = t.date;
    if (d.year != y || d.month != m || !t.isOutflow) continue;
    final base = spendGroupLabel(
      t,
      categoryOverrides: categoryOverrides,
      categoryRules: categoryRules,
    );
    if (isIgnoredCategoryLabel(base)) continue;
    final role = effectiveFinancialRole(
      t: t,
      effectiveCategoryLabel: base,
      accountsById: accountsById,
      allTransactions: txs,
    );
    if (role != FinancialRole.expense) continue;
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
  List<CategoryRule> categoryRules,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final map = <String, double>{};
  for (final t in txs) {
    if (t.amount >= 0) continue;
    if (!_inMonth(t.date, reference)) continue;
    final base = spendGroupLabel(
      t,
      categoryOverrides: categoryOverrides,
      categoryRules: categoryRules,
    );
    if (isIgnoredCategoryLabel(base)) continue;
    final role = effectiveFinancialRole(
      t: t,
      effectiveCategoryLabel: base,
      accountsById: accountsById,
      allTransactions: txs,
    );
    if (role != FinancialRole.expense) continue;
    final name = applyCategoryDisplayRenames(base, categoryDisplayRenamesLower);
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
