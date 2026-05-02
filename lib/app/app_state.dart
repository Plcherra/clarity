import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/constants.dart';
import '../features/transactions/domain/bank_statement_monthly.dart';
import '../features/transactions/data/csv_parser.dart';
import '../features/dashboard/domain/dashboard_snapshot.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/accounts/application/account_service.dart';
import '../core/models/models.dart';
import '../features/transactions/domain/transaction_resolution.dart'
    as transaction_resolution;
import '../features/transactions/data/ai_categorization_service.dart';
import '../features/transactions/data/csv_import_service.dart';
import '../features/transactions/data/transaction_repository.dart';
import '../features/transactions/application/ai_categorization_service.dart'
    as app_ai;
import '../features/categories/application/category_catalog_service.dart';
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/profile/application/profile_service.dart';
import '../features/budgets/application/budget_service.dart';
import '../features/budgets/domain/budget_models.dart';
import 'dashboard_refresh_coordinator.dart';
import 'ui_dependencies.dart';

export '../features/transactions/data/csv_import_service.dart'
    show CsvImportBatchSummary;

/// Composition root and compatibility facade for app-wide services.
///
/// Feature data and workflows live in services; this class wires them together,
/// preserves older public entry points, and coordinates scoped UI refreshes.
class AppState extends ChangeNotifier {
  LocalProfile? get localProfile => profileService.localProfile;
  set localProfile(LocalProfile? value) {
    profileService.localProfile = value;
  }

  final TransactionService transactionService = TransactionService();
  final CategoryService categoryService = CategoryService();
  final CategoryCatalogService categoryCatalogService =
      CategoryCatalogService();
  final MerchantService merchantService = MerchantService();
  final ProfileService profileService = ProfileService();
  final BudgetService budgetService = BudgetService();
  final AccountService accountService = AccountService();
  final app_ai.AiCategorizationApplicationService aiCategorizationService =
      app_ai.AiCategorizationApplicationService();

  final DashboardService _dashboard = DashboardService();
  late final DashboardRefreshCoordinator _dashboardRefresh =
      DashboardRefreshCoordinator(
        dashboardService: _dashboard,
        transactionService: transactionService,
        accountService: accountService,
        categoryService: categoryService,
        categoryCatalogService: categoryCatalogService,
        resolveTransactions: resolveTransactions,
      );
  late final AppUiDependencies ui = AppUiDependencies(
    AppUiControllerBindings(
      dashboardService: _dashboard,
      transactionService: transactionService,
      categoryService: categoryService,
      categoryCatalogService: categoryCatalogService,
      merchantService: merchantService,
      accountService: accountService,
      budgetService: budgetService,
      aiCategorizationService: aiCategorizationService,
      resolveTransaction: resolveTransaction,
      clearTransactionsForAccount: clearTransactionsForAccount,
      deleteTransaction: deleteTransaction,
      uncategorizedImportedRowsGlobal: uncategorizedImportedRowsGlobal,
      uncategorizedImportedRowsForAccount: uncategorizedImportedRowsForAccount,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
      undoCategoryApplyBatch: undoCategoryApplyBatch,
      undoLastAiAutoApply: undoLastAiAutoApply,
      setCategoryOverride: setCategoryOverride,
      createCategoryAndAssign: createCategoryAndAssign,
      deleteCategory: deleteCategory,
      renameCategory: renameCategory,
      addAccount: addAccount,
      deleteAccount: deleteAccount,
      loadFromCsv: loadFromCsv,
      needsImportAiAfterCsvUpload: needsImportAiAfterCsvUpload,
      importAiEngineConfigured: () => importAiEngineConfigured,
      startBackgroundImportAiCategorization:
          startBackgroundImportAiCategorization,
      csvImportBatchesForAccount: csvImportBatchesForAccount,
      deleteTransactionsForImportBatch: deleteTransactionsForImportBatch,
      setActiveBudgetPeriod: setActiveBudgetPeriod,
      commitBudgetDraft: commitBudgetDraft,
      budgetPerformanceForScope: budgetPerformanceForScope,
      spentByDisplayCategoryForScopeInRange:
          spentByDisplayCategoryForScopeInRange,
      consumeImportAiSnackMessage: consumeImportAiSnackMessage,
    ),
  );

  void _notifyProfileChanged() {
    notifyListeners();
  }

  void _notifyDashboardAndBudgetsChanged() {
    ui.notifyDashboard();
    ui.notifyBudgets();
  }

  void _notifyCategoryCatalogChanged() {
    ui.notifyTransactions();
    ui.notifyBudgets();
    ui.notifyDashboard();
  }

  void _notifyAccountsChanged() {
    ui.notifyAccounts();
    ui.notifyDashboard();
  }

  void _notifyTransactionDataChanged() {
    ui.notifyDataChanged();
  }

  void _notifyImportAiStatusChanged() {
    ui.notifyImportAiStatus();
  }

  @override
  void dispose() {
    ui.dispose();
    super.dispose();
  }

  /// The account currently being viewed/reviewed in UI flows.
  String? get activeAccountId => accountService.activeAccountId;
  set activeAccountId(String? value) {
    accountService.activeAccountId = value;
  }

  /// User-defined bank / card accounts (persisted separately from CSV rows).
  List<Account> get accounts => accountService.accounts;
  set accounts(List<Account> value) {
    accountService.accounts = value;
  }

  TransactionRepository get transactionRepository =>
      transactionService.transactionRepository;

  CsvImportService get csvImportService => transactionService.csvImportService;

  Map<String, List<Transaction>> get transactionsByAccount =>
      transactionService.transactionsByAccount;
  set transactionsByAccount(Map<String, List<Transaction>> value) {
    transactionService.transactionsByAccount = value;
  }

  /// Convenience: flattened across accounts, used for global dashboard metrics.
  List<Transaction> get allTransactions => transactionService.allTransactions;

  List<Transaction> get transactions => transactionService.transactions;
  set transactions(List<Transaction> value) {
    transactionService.transactions = value;
  }

  double get totalBalance => _dashboard.totalBalance;
  set totalBalance(double value) {
    _dashboard.totalBalance = value;
  }

  double get spentThisMonth => _dashboard.spentThisMonth;
  set spentThisMonth(double value) {
    _dashboard.spentThisMonth = value;
  }

  double get incomeThisMonth => _dashboard.incomeThisMonth;
  set incomeThisMonth(double value) {
    _dashboard.incomeThisMonth = value;
  }

  double get availableThisMonth => _dashboard.availableThisMonth;
  set availableThisMonth(double value) {
    _dashboard.availableThisMonth = value;
  }

  int get uncategorizedCount => _dashboard.uncategorizedCount;
  set uncategorizedCount(int value) {
    _dashboard.uncategorizedCount = value;
  }

  List<CategorySpend> get topCategories => _dashboard.topCategories;
  set topCategories(List<CategorySpend> value) {
    _dashboard.topCategories = value;
  }

  List<CategoryLeakStat> get biggestLeaksThisMonth =>
      _dashboard.biggestLeaksThisMonth;
  set biggestLeaksThisMonth(List<CategoryLeakStat> value) {
    _dashboard.biggestLeaksThisMonth = value;
  }

  int? get burnRunwayDays => _dashboard.burnRunwayDays;
  set burnRunwayDays(int? value) {
    _dashboard.burnRunwayDays = value;
  }

  /// Newest calendar month first for the **active account only**.
  ///
  /// Do **not** use for global Overview / [GlobalDashboardScope] UI — use
  /// [monthlyGroupsForDashboardScope] or [buildDashboardSnapshot].monthlyGroups instead.
  List<MonthlyBankGroup> get monthlyGroups => _dashboard.monthlyGroups;
  set monthlyGroups(List<MonthlyBankGroup> value) {
    _dashboard.monthlyGroups = value;
  }

  Map<String, String> get categoryOverrides =>
      categoryService.categoryOverrides;
  set categoryOverrides(Map<String, String> value) {
    categoryService.categoryOverrides = value;
  }

  /// Persisted manual categories by [transactionCategoryKey]; survives restarts and re-import.
  Map<String, String> get transactionCategoryAssignments =>
      transactionService.transactionCategoryAssignments;
  set transactionCategoryAssignments(Map<String, String> value) {
    transactionService.transactionCategoryAssignments = value;
  }

  Map<String, AiCategorySuggestion> get aiCategorySuggestions =>
      transactionService.aiCategorySuggestions;
  set aiCategorySuggestions(Map<String, AiCategorySuggestion> value) {
    transactionService.aiCategorySuggestions = value;
  }

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
    return transactionService.needsImportAiAfterCsvUploadWorkflow(
      accountId,
      aiCategorizationService: aiCategorizationService,
      uncategorizedImportedRowsForAccount: uncategorizedImportedRowsForAccount,
    );
  }

  String? consumeImportAiSnackMessage() {
    return aiCategorizationService.consumeImportAiSnackMessage();
  }

  /// Runs after CSV import: merchant memory first, then GPT in batches (see [AICategorizationService]).
  Future<void> startBackgroundImportAiCategorization(String accountId) async {
    await transactionService.startBackgroundImportAiCategorizationWorkflow(
      accountId,
      aiCategorizationService: aiCategorizationService,
      importAiEngineConfigured: importAiEngineConfigured,
      uncategorizedImportedRowsForAccount: uncategorizedImportedRowsForAccount,
      merchantService: merchantService,
      allowedCategoryPickerLabels: allowedCategoryPickerLabels,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
      notifyStatusChanged: _notifyImportAiStatusChanged,
    );
  }

  /// User-created category names (shown in the assignment sheet alongside built-ins).
  List<String> get customCategories => categoryCatalogService.customCategories;
  set customCategories(List<String> value) {
    categoryCatalogService.customCategories = value;
  }

  /// Lowercase base label -> user display name (renamed built-ins / display tweaks).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Map<String, String> get categoryDisplayRenames =>
      categoryCatalogService.categoryDisplayRenames;
  set categoryDisplayRenames(Map<String, String> value) {
    categoryCatalogService.categoryDisplayRenames = value;
  }

  /// Lowercase canonical labels removed from the picker (deleted built-ins).
  /// Not cleared by [loadFromCsv] (persisted with the category catalog).
  Set<String> get categoriesHiddenFromPicker =>
      categoryCatalogService.categoriesHiddenFromPicker;
  set categoriesHiddenFromPicker(Set<String> value) {
    categoryCatalogService.categoriesHiddenFromPicker = value;
  }

  /// Same instant used for monthly aggregates (defaults to import time / [loadFromCsv]).
  DateTime get spendReference => _dashboard.spendReference;

  /// Loads persisted budgets from disk (call once before [runApp]).
  Future<void> hydratePersistedBudgets() async {
    await budgetService.hydratePersistedBudgets(reference: spendReference);
    _notifyDashboardAndBudgetsChanged();
  }

  /// Loads custom category names and picker metadata from disk (call once before [runApp]).
  Future<void> hydratePersistedCategoryCatalog() async {
    await categoryCatalogService.hydratePersistedCategoryCatalog();
    _notifyCategoryCatalogChanged();
  }

  /// Loads persisted accounts from disk (call once before [runApp]).
  Future<void> hydratePersistedAccounts() async {
    await accountService.hydratePersistedAccounts();
    _notifyAccountsChanged();
  }

  /// Loads persisted transactions across all accounts (call once before [runApp]).
  Future<void> hydratePersistedTransactions() async {
    final result = await transactionService.hydratePersistedTransactions(
      activeAccountId: activeAccountId,
    );
    transactions = result.activeTransactions;
    _syncDashboardAfterTransactionWorkflow(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    _notifyTransactionDataChanged();
  }

  /// One-time migration: remove duplicated transactions caused by unstable v1 fingerprints.
  ///
  /// Keeps one row per stable identity key per account, preferring rows with:
  /// - persisted/manual categoryId
  /// - non-null running balance
  /// - earliest importId
  Future<void> dedupePersistedTransactionsIfNeeded() async {
    final result = await transactionService.dedupePersistedTransactionsIfNeeded(
      activeAccountId: activeAccountId,
    );
    if (!result.changed) return;

    transactions = result.activeTransactions;
    _syncDashboardAfterTransactionWorkflow(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: allTransactions,
      transactionsForCsvDiagnostics: transactions,
      diag: null,
    );
    _notifyTransactionDataChanged();
  }

  Future<void> hydrateLocalProfile() async {
    await profileService.hydrateLocalProfile();
    _notifyProfileChanged();
  }

  Future<void> setLocalProfile(LocalProfile profile) async {
    await profileService.setLocalProfile(profile);
    // Switch merchant memory namespace to the new profile.
    await hydrateMerchantCategoryMemory();
    _notifyProfileChanged();
  }

  String _userNamespaceForMerchantMemory() {
    return profileService.userNamespaceForMerchantMemory();
  }

  Future<void> hydrateMerchantCategoryMemory() async {
    await merchantService.hydrateMerchantCategoryMemory(
      _userNamespaceForMerchantMemory(),
    );
    _notifyTransactionDataChanged();
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

  /// Appends [account], persists, and refreshes account/dashboard UI.
  Future<bool> addAccount(Account account) async {
    final ok = await accountService.addAccount(account);
    if (ok) _notifyAccountsChanged();
    return ok;
  }

  /// Deletes one account and all its transactions + related keyed metadata.
  Future<bool> deleteAccount(String accountId) async {
    return accountService.deleteAccountWorkflow(
      accountId: accountId,
      transactionsByAccount: transactionsByAccount,
      transactionService: transactionService,
      categoryService: categoryService,
      refreshAllState: refreshAllState,
    );
  }

  void _persistCategoryCatalog() {
    categoryCatalogService.persistCategoryCatalog();
  }

  /// Loads persisted per-transaction category picks (call once before [runApp]).
  Future<void> hydrateTransactionCategoryAssignments() async {
    await transactionService.hydrateTransactionCategoryAssignments();
    _notifyTransactionDataChanged();
  }

  Future<void> hydrateAiCategorySuggestions() async {
    await transactionService.hydrateAiCategorySuggestions();
    ui.notifyTransactions();
  }

  Future<void> _persistAiCategorySuggestions() async {
    await transactionService.persistAiCategorySuggestions();
  }

  /// Compatibility refresh delegate used after mutations that affect many views.
  ///
  /// This keeps Dashboard (global + account), monthly breakdowns, and dependent
  /// views in sync without requiring route-level/manual refresh hooks.
  void refreshAllState() {
    _dashboardRefresh.refreshAllState();
    _notifyTransactionDataChanged();
  }

  void _syncDashboardAfterTransactionWorkflow({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diag,
  }) {
    _dashboardRefresh.syncAfterTransactionWorkflow(
      activeAccountTransactions: activeAccountTransactions,
      allTransactionsForMetrics: allTransactionsForMetrics,
      transactionsForCsvDiagnostics: transactionsForCsvDiagnostics,
      diagnostics: diag,
    );
  }

  /// Deletes a single transaction row and refreshes derived dashboard state.
  Future<bool> deleteTransaction(Transaction transaction) async {
    return transactionService.deleteTransactionWorkflow(
      transaction,
      categoryService: categoryService,
      refreshAllState: refreshAllState,
    );
  }

  /// Deletes all transactions for one account and refreshes derived dashboard state.
  Future<int> clearTransactionsForAccount(String accountId) async {
    return transactionService.clearTransactionsForAccountWorkflow(
      accountId,
      categoryService: categoryService,
      refreshAllState: refreshAllState,
    );
  }

  List<CsvImportBatchSummary> csvImportBatchesForAccount(String accountId) {
    return transactionService.csvImportBatchesForAccount(accountId);
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    return transactionService.deleteTransactionsForImportBatchWorkflow(
      accountId: accountId,
      importId: importId,
      categoryService: categoryService,
      refreshAllState: refreshAllState,
    );
  }

  List<Transaction> uncategorizedImportedRowsGlobal() {
    return transactionService.uncategorizedImportedRowsGlobal(
      accounts: accounts,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
    );
  }

  Future<({int applied, int queuedForReview})>
  autoCategorizeGlobalUncategorized({
    required AICategorizationService service,
    double autoApplyConfidenceThreshold = 0.90,
  }) async {
    return transactionService.autoCategorizeGlobalUncategorizedWorkflow(
      service: service,
      aiCategorizationService: aiCategorizationService,
      allowedCategoryPickerLabels: allowedCategoryPickerLabels,
      uncategorizedImportedRowsGlobal: uncategorizedImportedRowsGlobal(),
      persistAiCategorySuggestions: _persistAiCategorySuggestions,
      bulkSetCategoryOverrides: bulkSetCategoryOverrides,
      autoApplyConfidenceThreshold: autoApplyConfidenceThreshold,
    );
  }

  Future<int> undoLastAiAutoApply() async {
    return transactionService.undoLastAiAutoApplyWorkflow(
      aiCategorizationService: aiCategorizationService,
      categoryService: categoryService,
      activeAccountId: activeAccountId,
      recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
      notifyChanged: _notifyTransactionDataChanged,
    );
  }

  /// Compatibility entry for effective spend grouping.
  String effectiveSpendGroupLabel(Transaction t) {
    return transactionService.effectiveSpendGroupLabel(
      t,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
      allTransactionsContext: allTransactions,
    );
  }

  /// Display label after renames — use for UI and "is Uncategorized?" checks on this app’s state.
  String effectiveCategoryDisplayLabel(Transaction t) {
    return transactionService.effectiveCategoryDisplayLabel(
      t,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
      allTransactionsContext: allTransactions,
    );
  }

  transaction_resolution.ResolvedTransaction resolveTransaction(
    Transaction t, {
    required List<Transaction> allTransactionsContext,
  }) {
    return transactionService.resolveTransaction(
      t,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
      allTransactionsContext: allTransactionsContext,
    );
  }

  List<transaction_resolution.ResolvedTransaction> resolveTransactions(
    List<Transaction> txs, {
    required List<Transaction> allTransactionsContext,
  }) {
    return transactionService.resolveTransactions(
      txs,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
      allTransactionsContext: allTransactionsContext,
    );
  }

  /// Built-in + custom categories shown in pickers (for AI allow-lists and review UI).
  List<String> get allowedCategoryPickerLabels =>
      categoryCatalogService.allowedCategoryPickerLabels;

  /// Rows for [buildDashboardSnapshot] / Overview vs account-scoped views.
  List<Transaction> transactionsForDashboardScope(DashboardScope scope) {
    return _dashboard.transactionsForDashboardScope(
      scope: scope,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
    );
  }

  /// Uncategorized statement rows for [accountId] using dashboard category resolution.
  List<Transaction> uncategorizedImportedRowsForAccount(String accountId) {
    return transactionService.uncategorizedImportedRowsForAccount(
      accountId,
      categoryService: categoryService,
      categoryDisplayRenames: categoryDisplayRenames,
    );
  }

  /// Active calendar month key derived from spend reference (budget UX).
  String get activeBudgetYearMonth =>
      budgetService.activeBudgetYearMonth(spendReference);

  /// Weekly period key uses the exact user-selected start date (not normalized).
  String budgetWeekStartKey(DateTime date) =>
      budgetService.budgetWeekStartKey(date);

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) =>
      budgetService.ensureCustomBudgetPeriod(start, end);

  void setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    budgetService.setActiveBudgetPeriod(type: type, key: key);
    _notifyDashboardAndBudgetsChanged();
  }

  double? monthlyBudgetForDisplayLabel(
    String displayLabel, {
    String? yearMonth,
  }) {
    return budgetService.monthlyBudgetForDisplayLabel(
      displayLabel,
      yearMonth: yearMonth,
      spendReference: spendReference,
    );
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    final ok = await budgetService.commitBudgetDraft(
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

  BudgetPerformanceSnapshot budgetPerformanceForScope(
    DashboardScope scope, {
    BudgetPeriodType? periodType,
    String? periodKey,
  }) {
    return budgetService.budgetPerformanceForScope(
      scope,
      customCategories: customCategories,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
      categoryDisplayRenames: categoryDisplayRenames,
      spentByDisplayCategoryForScopeInRange:
          spentByDisplayCategoryForScopeInRange,
      periodType: periodType,
      periodKey: periodKey,
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
    transactionService.loadFromCsvWorkflow(
      utf8Text,
      accountId: accountId,
      reference: reference,
      accounts: accounts,
      categoryService: categoryService,
      setSpendReference: (reference) {
        _dashboard.spendReference = reference;
      },
      setActiveAccountId: (accountId) {
        activeAccountId = accountId;
      },
      setTotalBalance: (balance) {
        totalBalance = balance;
      },
      recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
      notifyChanged: _notifyTransactionDataChanged,
      persistCategoryCatalog: _persistCategoryCatalog,
    );
  }

  /// Assigns a category to a transaction and refreshes aggregates.
  void setCategoryOverride(Transaction t, String category) {
    categoryService.setCategoryOverrideWorkflow(
      t,
      category,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Assigns categories for many [transactionCategoryKey]s at once (persists [categoryId] on each row).
  void bulkSetCategoryOverrides(Map<String, String> keyToCanonicalCategory) {
    categoryService.bulkSetCategoryOverridesWorkflow(
      keyToCanonicalCategory,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Adds a new category name if needed, then assigns [t].
  void createCategoryAndAssign(Transaction t, String rawName) {
    categoryService.createCategoryAndAssignWorkflow(
      t,
      rawName,
      categoryCatalogService: categoryCatalogService,
      applyCategoriesWithMerchantLearning: applyCategoriesWithMerchantLearning,
    );
  }

  /// Deletes a category from the picker and clears assignments using it (any label, built-in or custom).
  void deleteCategory(String canonicalLabel) {
    categoryService.deleteCategoryWorkflow(
      canonicalLabel,
      categoryCatalogService: categoryCatalogService,
      transactionService: transactionService,
      activeAccountId: activeAccountId,
      recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
      notifyChanged: _notifyTransactionDataChanged,
    );
  }

  /// Renames a category. Built-ins: display-only map (overrides stay canonical). Custom: text + overrides.
  void renameCategory(String oldLabel, String newLabel) {
    categoryService.renameCategoryWorkflow(
      oldLabel,
      newLabel,
      categoryCatalogService: categoryCatalogService,
      transactionService: transactionService,
      activeAccountId: activeAccountId,
      recomputeDashboard: _syncDashboardAfterTransactionWorkflow,
      notifyChanged: _notifyTransactionDataChanged,
    );
  }

  void clear() {
    transactions = const [];
    transactionsByAccount = const {};
    activeAccountId = null;
    _dashboard.resetDerivedState();
    categoryOverrides = const {};
    customCategories = const [];
    categoryDisplayRenames = const {};
    categoriesHiddenFromPicker = <String>{};
    ui.notifyAll();
    _persistCategoryCatalog();
  }
}
