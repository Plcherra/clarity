import 'package:flutter/foundation.dart';

import '../core/models/models.dart';
import '../features/accounts/application/account_service.dart';
import '../features/budgets/application/budget_service.dart';
import '../features/budgets/domain/budget_models.dart';
import '../features/categories/application/category_catalog_service.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/dashboard/domain/dashboard_queries.dart';
import '../features/dashboard/domain/dashboard_snapshot.dart';
import '../features/transactions/application/ai_categorization_service.dart'
    as app_ai;
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/transactions/data/csv_import_service.dart';
import '../features/transactions/domain/bank_statement_monthly.dart';
import '../features/transactions/domain/spend_categories.dart';
import '../features/transactions/domain/transaction_resolution.dart'
    as transaction_resolution;

typedef LoadFromCsv =
    void Function(String utf8Text, {required String accountId});

typedef DeleteTransactionsForImportBatch =
    Future<int> Function({required String accountId, required String importId});

typedef ResolveTransaction =
    transaction_resolution.ResolvedTransaction Function(
      Transaction transaction, {
      required List<Transaction> allTransactionsContext,
    });

typedef ApplyCategoriesWithMerchantLearning =
    List<AiAppliedCategoryChange> Function(
      Map<String, String> keyToCanonicalCategory,
    );

typedef SetActiveBudgetPeriod =
    void Function({required BudgetPeriodType type, required String key});

typedef CommitBudgetDraft =
    Future<bool> Function(
      BudgetPeriodType periodType,
      String periodKey,
      Map<String, double?> draftByNormalizedDisplayKey,
    );

typedef BudgetPerformanceForScope =
    BudgetPerformanceSnapshot Function(
      DashboardScope scope, {
      BudgetPeriodType? periodType,
      String? periodKey,
    });

typedef SpentByDisplayCategoryForScopeInRange =
    Map<String, double> Function(
      DashboardScope scope, {
      required DateTime start,
      required DateTime end,
    });

final class AppUiControllerBindings {
  const AppUiControllerBindings({
    required this.dashboardService,
    required this.transactionService,
    required this.categoryService,
    required this.categoryCatalogService,
    required this.merchantService,
    required this.accountService,
    required this.budgetService,
    required this.aiCategorizationService,
    required this.resolveTransaction,
    required this.clearTransactionsForAccount,
    required this.deleteTransaction,
    required this.uncategorizedImportedRowsGlobal,
    required this.uncategorizedImportedRowsForAccount,
    required this.applyCategoriesWithMerchantLearning,
    required this.undoCategoryApplyBatch,
    required this.undoLastAiAutoApply,
    required this.setCategoryOverride,
    required this.createCategoryAndAssign,
    required this.deleteCategory,
    required this.renameCategory,
    required this.addAccount,
    required this.deleteAccount,
    required this.loadFromCsv,
    required this.needsImportAiAfterCsvUpload,
    required this.importAiEngineConfigured,
    required this.startBackgroundImportAiCategorization,
    required this.csvImportBatchesForAccount,
    required this.deleteTransactionsForImportBatch,
    required this.setActiveBudgetPeriod,
    required this.commitBudgetDraft,
    required this.budgetPerformanceForScope,
    required this.spentByDisplayCategoryForScopeInRange,
    required this.consumeImportAiSnackMessage,
  });

  final DashboardService dashboardService;
  final TransactionService transactionService;
  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final MerchantService merchantService;
  final AccountService accountService;
  final BudgetService budgetService;
  final app_ai.AiCategorizationApplicationService aiCategorizationService;

  final ResolveTransaction resolveTransaction;
  final Future<int> Function(String accountId) clearTransactionsForAccount;
  final Future<bool> Function(Transaction transaction) deleteTransaction;

  final List<Transaction> Function() uncategorizedImportedRowsGlobal;
  final List<Transaction> Function(String accountId)
  uncategorizedImportedRowsForAccount;
  final ApplyCategoriesWithMerchantLearning applyCategoriesWithMerchantLearning;
  final Future<int> Function(List<AiAppliedCategoryChange> batch)
  undoCategoryApplyBatch;
  final Future<int> Function() undoLastAiAutoApply;
  final void Function(Transaction transaction, String category)
  setCategoryOverride;
  final void Function(Transaction transaction, String rawName)
  createCategoryAndAssign;
  final void Function(String canonicalLabel) deleteCategory;
  final void Function(String oldLabel, String newLabel) renameCategory;

  final Future<bool> Function(Account account) addAccount;
  final Future<bool> Function(String accountId) deleteAccount;
  final LoadFromCsv loadFromCsv;
  final bool Function(String accountId) needsImportAiAfterCsvUpload;
  final bool Function() importAiEngineConfigured;
  final Future<void> Function(String accountId)
  startBackgroundImportAiCategorization;
  final List<CsvImportBatchSummary> Function(String accountId)
  csvImportBatchesForAccount;
  final DeleteTransactionsForImportBatch deleteTransactionsForImportBatch;

  final SetActiveBudgetPeriod setActiveBudgetPeriod;
  final CommitBudgetDraft commitBudgetDraft;
  final BudgetPerformanceForScope budgetPerformanceForScope;
  final SpentByDisplayCategoryForScopeInRange
  spentByDisplayCategoryForScopeInRange;

  final String? Function() consumeImportAiSnackMessage;
}

final class AppUiDependencies {
  AppUiDependencies(AppUiControllerBindings bindings)
    : dashboard = DashboardUiController._(bindings),
      transactions = TransactionUiController._(bindings),
      accounts = AccountUiController._(bindings),
      budgets = BudgetUiController._(bindings),
      importAiStatus = ImportAiStatusController._(bindings) {
    dashboard._ui = this;
    transactions._ui = this;
    accounts._ui = this;
  }

  final DashboardUiController dashboard;
  final TransactionUiController transactions;
  final AccountUiController accounts;
  final BudgetUiController budgets;
  final ImportAiStatusController importAiStatus;

  void notifyDashboard() => dashboard.notifyChanged();
  void notifyTransactions() => transactions.notifyChanged();
  void notifyAccounts() => accounts.notifyChanged();
  void notifyBudgets() => budgets.notifyChanged();
  void notifyImportAiStatus() => importAiStatus.notifyChanged();

  void notifyDataChanged() {
    notifyDashboard();
    notifyTransactions();
    notifyAccounts();
    notifyBudgets();
  }

  void notifyAll() {
    notifyDataChanged();
    notifyImportAiStatus();
  }

  void dispose() {
    dashboard.dispose();
    transactions.dispose();
    accounts.dispose();
    budgets.dispose();
    importAiStatus.dispose();
  }
}

base class _UiController extends ChangeNotifier {
  _UiController(this.bindings);

  final AppUiControllerBindings bindings;

  void notifyChanged() => notifyListeners();
}

final class DashboardUiController extends _UiController {
  DashboardUiController._(super.bindings);

  late final AppUiDependencies _ui;

  AppUiDependencies get ui => _ui;

  DashboardSnapshot buildSnapshot(DashboardScope scope) {
    final scopedTransactions = transactionsForDashboardScope(scope);
    return buildDashboardSnapshot(
      scope: scope,
      reference: bindings.dashboardService.spendReference,
      accounts: bindings.accountService.accounts,
      allTransactions: bindings.transactionService.allTransactions,
      scopedTransactions: scopedTransactions,
      categoryOverrides: bindings.categoryService.categoryOverrides,
      categoryDisplayRenamesLower:
          bindings.categoryCatalogService.categoryDisplayRenames,
      scopedBalanceFromStatement: null,
    );
  }

  BudgetPerformanceSnapshot budgetPerformanceForScope(DashboardScope scope) {
    return bindings.budgetPerformanceForScope(scope);
  }

  List<Transaction> transactionsForDashboardScope(DashboardScope scope) {
    return bindings.dashboardService.transactionsForDashboardScope(
      scope: scope,
      allTransactions: bindings.transactionService.allTransactions,
      transactionsByAccount: bindings.transactionService.transactionsByAccount,
    );
  }

  List<BankStatementLine> uncategorizedQueue(DashboardScope scope) {
    return uncategorizedTransactionsForDashboardScope(
      scope,
      scopedTransactions: transactionsForDashboardScope(scope),
      categoryOverrides: bindings.categoryService.categoryOverrides,
      categoryDisplayRenamesLower:
          bindings.categoryCatalogService.categoryDisplayRenames,
    );
  }

  List<BankStatementLine> refreshedLinesForMonth(MonthlyBankGroup group) {
    final scopedAccountIds = group.transactions
        .map((e) => e.transaction.accountId)
        .toSet();
    final hasScopedStorageEntry = scopedAccountIds.any(
      bindings.transactionService.transactionsByAccount.containsKey,
    );
    if (!hasScopedStorageEntry) return group.transactions;

    final byKey = <String, Transaction>{
      for (final t in bindings.transactionService.allTransactions)
        transactionCategoryKey(t): t,
    };
    final lines = <BankStatementLine>[];
    for (final line in group.transactions) {
      final key = transactionCategoryKey(line.transaction);
      final current = byKey[key];
      if (current == null) continue;
      final resolved = bindings.resolveTransaction(
        current,
        allTransactionsContext: bindings.transactionService.allTransactions,
      );
      lines.add(
        BankStatementLine(
          transaction: current,
          suggestedCategory: resolved.displayCategory,
        ),
      );
    }
    return lines;
  }

  Future<int> clearTransactionsForAccount(String accountId) {
    return bindings.clearTransactionsForAccount(accountId);
  }

  Future<bool> deleteTransaction(Transaction transaction) {
    return bindings.deleteTransaction(transaction);
  }
}

final class TransactionUiController extends _UiController {
  TransactionUiController._(super.bindings);

  late final AppUiDependencies _ui;

  List<String> get allowedCategoryPickerLabels =>
      bindings.categoryCatalogService.allowedCategoryPickerLabels;

  List<String> get customCategories =>
      bindings.categoryCatalogService.customCategories;

  Map<String, String> get categoryDisplayRenames =>
      bindings.categoryCatalogService.categoryDisplayRenames;

  Set<String> get categoriesHiddenFromPicker =>
      bindings.categoryCatalogService.categoriesHiddenFromPicker;

  Map<String, String> get transactionCategoryAssignments =>
      bindings.transactionService.transactionCategoryAssignments;

  Map<String, AiCategorySuggestion> get aiCategorySuggestions =>
      bindings.transactionService.aiCategorySuggestions;

  Map<String, String> get merchantCategoryMemory =>
      bindings.merchantService.merchantCategoryMemory;

  List<BankStatementLine> uncategorizedQueue(DashboardScope scope) {
    return _ui.dashboard.uncategorizedQueue(scope);
  }

  List<Transaction> uncategorizedImportedRowsGlobal() {
    return bindings.uncategorizedImportedRowsGlobal();
  }

  List<Transaction> uncategorizedImportedRowsForAccount(String accountId) {
    return bindings.uncategorizedImportedRowsForAccount(accountId);
  }

  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    return bindings.applyCategoriesWithMerchantLearning(keyToCanonicalCategory);
  }

  Future<int> undoCategoryApplyBatch(List<AiAppliedCategoryChange> batch) {
    return bindings.undoCategoryApplyBatch(batch);
  }

  Future<int> undoLastAiAutoApply() {
    return bindings.undoLastAiAutoApply();
  }

  void setCategoryOverride(Transaction transaction, String category) {
    bindings.setCategoryOverride(transaction, category);
  }

  void createCategoryAndAssign(Transaction transaction, String rawName) {
    bindings.createCategoryAndAssign(transaction, rawName);
  }

  void deleteCategory(String canonicalLabel) {
    bindings.deleteCategory(canonicalLabel);
  }

  void renameCategory(String oldLabel, String newLabel) {
    bindings.renameCategory(oldLabel, newLabel);
  }

  Future<bool> deleteTransaction(Transaction transaction) {
    return bindings.deleteTransaction(transaction);
  }
}

final class AccountUiController extends _UiController {
  AccountUiController._(super.bindings);

  late final AppUiDependencies _ui;

  AppUiDependencies get ui => _ui;

  List<Account> get accounts => bindings.accountService.accounts;

  Future<bool> addAccount(Account account) => bindings.addAccount(account);

  Future<bool> deleteAccount(String accountId) =>
      bindings.deleteAccount(accountId);

  void loadFromCsv(String utf8Text, {required String accountId}) {
    bindings.loadFromCsv(utf8Text, accountId: accountId);
  }

  bool needsImportAiAfterCsvUpload(String accountId) {
    return bindings.needsImportAiAfterCsvUpload(accountId);
  }

  bool get importAiEngineConfigured => bindings.importAiEngineConfigured();

  Future<void> startBackgroundImportAiCategorization(String accountId) {
    return bindings.startBackgroundImportAiCategorization(accountId);
  }

  List<CsvImportBatchSummary> csvImportBatchesForAccount(String accountId) {
    return bindings.csvImportBatchesForAccount(accountId);
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) {
    return bindings.deleteTransactionsForImportBatch(
      accountId: accountId,
      importId: importId,
    );
  }

  DashboardSnapshot buildSnapshotForAccount(String accountId) {
    final transactions = List<Transaction>.unmodifiable(
      bindings.transactionService.transactionsByAccount[accountId] ?? const [],
    );
    return buildDashboardSnapshot(
      scope: AccountDashboardScope(accountId),
      reference: bindings.dashboardService.spendReference,
      accounts: bindings.accountService.accounts,
      allTransactions: bindings.transactionService.allTransactions,
      scopedTransactions: transactions,
      categoryOverrides: bindings.categoryService.categoryOverrides,
      categoryDisplayRenamesLower:
          bindings.categoryCatalogService.categoryDisplayRenames,
      scopedBalanceFromStatement: null,
    );
  }
}

final class BudgetUiController extends _UiController {
  BudgetUiController._(super.bindings);

  BudgetService get budgetService => bindings.budgetService;

  DateTime get spendReference => bindings.dashboardService.spendReference;

  List<String> get customCategories =>
      bindings.categoryCatalogService.customCategories;

  Map<String, String> get categoryDisplayRenames =>
      bindings.categoryCatalogService.categoryDisplayRenames;

  Set<String> get categoriesHiddenFromPicker =>
      bindings.categoryCatalogService.categoriesHiddenFromPicker;

  String budgetWeekStartKey(DateTime date) {
    return bindings.budgetService.budgetWeekStartKey(date);
  }

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) {
    return bindings.budgetService.ensureCustomBudgetPeriod(start, end);
  }

  void setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    bindings.setActiveBudgetPeriod(type: type, key: key);
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) {
    return bindings.commitBudgetDraft(
      periodType,
      periodKey,
      draftByNormalizedDisplayKey,
    );
  }

  BudgetPerformanceSnapshot budgetPerformanceForScope(
    DashboardScope scope, {
    BudgetPeriodType? periodType,
    String? periodKey,
  }) {
    return bindings.budgetPerformanceForScope(
      scope,
      periodType: periodType,
      periodKey: periodKey,
    );
  }

  Map<String, double> spentByDisplayCategoryForScopeInRange(
    DashboardScope scope, {
    required DateTime start,
    required DateTime end,
  }) {
    return bindings.spentByDisplayCategoryForScopeInRange(
      scope,
      start: start,
      end: end,
    );
  }
}

final class ImportAiStatusController extends _UiController {
  ImportAiStatusController._(super.bindings);

  bool get importAiCategorizationRunning =>
      bindings.aiCategorizationService.importAiCategorizationRunning;

  int get importAiProgressCompleted =>
      bindings.aiCategorizationService.importAiProgressCompleted;

  int get importAiProgressTotal =>
      bindings.aiCategorizationService.importAiProgressTotal;

  String? consumeImportAiSnackMessage() {
    return bindings.consumeImportAiSnackMessage();
  }
}
