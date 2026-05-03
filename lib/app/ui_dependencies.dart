import 'package:flutter/foundation.dart';

import '../core/models/models.dart';
import '../core/supabase/supabase_records.dart';
import '../features/accounts/application/account_service.dart';
import '../features/accounts/application/account_workflow_service.dart';
import '../features/budgets/application/budget_service.dart';
import '../features/budgets/application/budget_workflow_service.dart';
import '../features/budgets/domain/budget_models.dart';
import '../features/categories/application/category_catalog_service.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/dashboard/domain/dashboard_queries.dart';
import '../features/dashboard/domain/dashboard_snapshot.dart';
import '../features/transactions/application/ai_categorization_service.dart'
    as app_ai;
import '../features/transactions/application/category_service.dart';
import '../features/transactions/application/category_workflow_service.dart';
import '../features/transactions/application/merchant_service.dart';
import '../features/transactions/application/transaction_service.dart';
import '../features/transactions/application/transaction_workflow_service.dart';
import '../features/transactions/data/csv_import_service.dart';
import '../features/transactions/domain/bank_statement_monthly.dart';
import '../features/transactions/domain/spend_categories.dart';
import '../features/transactions/domain/transaction_resolution.dart'
    as transaction_resolution;

final class AppUiControllerBindings {
  const AppUiControllerBindings({
    required this.dashboardService,
    required this.transactionService,
    required this.categoryService,
    required this.categoryWorkflowService,
    required this.transactionWorkflowService,
    required this.categoryCatalogService,
    required this.merchantService,
    required this.accountService,
    required this.budgetService,
    required this.budgetWorkflowService,
    required this.aiCategorizationService,
    required this.accountWorkflowService,
    required this.importAiEngineConfigured,
  });

  final DashboardService dashboardService;
  final TransactionService transactionService;
  final CategoryService categoryService;
  final CategoryWorkflowService categoryWorkflowService;
  final TransactionWorkflowService transactionWorkflowService;
  final CategoryCatalogService categoryCatalogService;
  final MerchantService merchantService;
  final AccountService accountService;
  final BudgetService budgetService;
  final BudgetWorkflowService budgetWorkflowService;
  final app_ai.AiCategorizationApplicationService aiCategorizationService;
  final AccountWorkflowService accountWorkflowService;
  final bool Function() importAiEngineConfigured;
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

  Future<List<Account>> fetchAccounts() async {
    final records = await bindings.accountService.fetchAccounts();
    return records.map(_accountFromRecord).toList();
  }

  Stream<List<Account>> watchAccounts() {
    return bindings.accountService.watchAccounts().map(
      (records) => records.map(_accountFromRecord).toList(),
    );
  }

  Future<List<Transaction>> fetchTransactions({String? accountId}) async {
    final records = await bindings.transactionService.fetchTransactions(
      accountId: accountId,
    );
    return records.map(_transactionFromRecord).toList();
  }

  Stream<List<Transaction>> watchTransactions({String? accountId}) {
    return bindings.transactionService
        .watchTransactions(accountId: accountId)
        .map((records) => records.map(_transactionFromRecord).toList());
  }

  Future<Map<String, List<Transaction>>> fetchTransactionsByAccount() async {
    final records = await bindings.transactionService.fetchTransactions();
    final grouped = <String, List<Transaction>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.accountId, () => <Transaction>[]);
      grouped[record.accountId]!.add(_transactionFromRecord(record));
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List<Transaction>.unmodifiable(entry.value),
    };
  }
}

final class DashboardUiController extends _UiController {
  DashboardUiController._(super.bindings);

  late final AppUiDependencies _ui;

  AppUiDependencies get ui => _ui;

  Future<DashboardSnapshot> buildSnapshot(DashboardScope scope) async {
    final accounts = await fetchAccounts();
    final allTransactions = await fetchTransactions();
    final scopedTransactions = await transactionsForDashboardScope(scope);
    return buildDashboardSnapshot(
      scope: scope,
      reference: bindings.dashboardService.spendReference,
      accounts: accounts,
      allTransactions: allTransactions,
      scopedTransactions: scopedTransactions,
      categoryOverrides: bindings.categoryService.categoryOverrides,
      categoryDisplayRenamesLower:
          bindings.categoryCatalogService.categoryDisplayRenames,
      scopedBalanceFromStatement: null,
    );
  }

  Future<BudgetPerformanceSnapshot> budgetPerformanceForScope(
    DashboardScope scope,
  ) {
    return _ui.budgets.budgetPerformanceForScope(scope);
  }

  Future<List<Transaction>> transactionsForDashboardScope(
    DashboardScope scope,
  ) async {
    return switch (scope) {
      GlobalDashboardScope() => fetchTransactions(),
      AccountDashboardScope(:final accountId) => fetchTransactions(
        accountId: accountId,
      ),
    };
  }

  Future<List<BankStatementLine>> uncategorizedQueue(
    DashboardScope scope,
  ) async {
    return uncategorizedTransactionsForDashboardScope(
      scope,
      scopedTransactions: await transactionsForDashboardScope(scope),
      categoryOverrides: bindings.categoryService.categoryOverrides,
      categoryDisplayRenamesLower:
          bindings.categoryCatalogService.categoryDisplayRenames,
    );
  }

  Future<List<BankStatementLine>> refreshedLinesForMonth(
    MonthlyBankGroup group,
  ) async {
    final allTransactions = await fetchTransactions();
    final accounts = await fetchAccounts();
    final accountsById = {for (final account in accounts) account.id: account};
    final byKey = <String, Transaction>{
      for (final transaction in allTransactions)
        transactionCategoryKey(transaction): transaction,
    };

    final lines = <BankStatementLine>[];
    for (final line in group.transactions) {
      final current = byKey[transactionCategoryKey(line.transaction)];
      if (current == null) continue;
      final resolved = transaction_resolution.resolveTransaction(
        t: current,
        categoryOverrides: bindings.categoryService.categoryOverrides,
        categoryDisplayRenamesLower:
            bindings.categoryCatalogService.categoryDisplayRenames,
        merchantCategoryMemory: bindings.merchantService.merchantCategoryMemory,
        accountsById: accountsById,
        allTransactions: allTransactions,
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

  Future<int> clearTransactionsForAccount(String accountId) async {
    final records = await bindings.transactionService.fetchTransactions(
      accountId: accountId,
    );
    for (final record in records) {
      await bindings.transactionService.deleteTransaction(record.id);
    }
    notifyChanged();
    return records.length;
  }

  Future<bool> deleteTransaction(Transaction transaction) async {
    final records = await bindings.transactionService.fetchTransactions(
      accountId: transaction.accountId,
    );
    final key = transactionCategoryKey(transaction);
    for (final record in records) {
      final current = _transactionFromRecord(record);
      if (transactionCategoryKey(current) == key) {
        await bindings.transactionService.deleteTransaction(record.id);
        notifyChanged();
        return true;
      }
    }
    return false;
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

  Map<String, String> get transactionCategoryAssignments => const {};

  Map<String, AiCategorySuggestion> get aiCategorySuggestions => const {};

  Map<String, String> get merchantCategoryMemory =>
      bindings.merchantService.merchantCategoryMemory;

  Future<List<BankStatementLine>> uncategorizedQueue(DashboardScope scope) {
    return _ui.dashboard.uncategorizedQueue(scope);
  }

  Future<List<Transaction>> uncategorizedImportedRowsGlobal() async {
    final transactions = await fetchTransactions();
    return transactions.where(_isUncategorizedImportedTransaction).toList();
  }

  Future<List<Transaction>> uncategorizedImportedRowsForAccount(
    String accountId,
  ) async {
    final transactions = await fetchTransactions(accountId: accountId);
    return transactions.where(_isUncategorizedImportedTransaction).toList();
  }

  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    return bindings.categoryWorkflowService.applyCategoriesWithMerchantLearning(
      keyToCanonicalCategory,
    );
  }

  Future<int> undoCategoryApplyBatch(List<AiAppliedCategoryChange> batch) {
    return bindings.categoryWorkflowService.undoCategoryApplyBatch(batch);
  }

  Future<int> undoLastAiAutoApply() {
    return bindings.transactionWorkflowService.undoLastAiAutoApply();
  }

  Future<void> setCategoryOverride(Transaction transaction, String category) {
    return bindings.categoryWorkflowService.setCategoryOverride(
      transaction,
      category,
    );
  }

  Future<void> createCategoryAndAssign(
    Transaction transaction,
    String rawName,
  ) {
    return bindings.categoryWorkflowService.createCategoryAndAssign(
      transaction,
      rawName,
    );
  }

  Future<void> deleteCategory(String canonicalLabel) {
    return bindings.categoryWorkflowService.deleteCategory(canonicalLabel);
  }

  Future<void> renameCategory(String oldLabel, String newLabel) {
    return bindings.categoryWorkflowService.renameCategory(oldLabel, newLabel);
  }

  Future<bool> deleteTransaction(Transaction transaction) {
    return _ui.dashboard.deleteTransaction(transaction);
  }
}

final class AccountUiController extends _UiController {
  AccountUiController._(super.bindings);

  late final AppUiDependencies _ui;

  AppUiDependencies get ui => _ui;

  Future<List<Account>> get accounts => fetchAccounts();

  Future<bool> addAccount(Account account) async {
    return bindings.accountWorkflowService.addAccount(account);
  }

  Future<bool> deleteAccount(String accountId) async {
    return bindings.accountWorkflowService.deleteAccount(accountId);
  }

  Future<void> loadFromCsv(String utf8Text, {required String accountId}) async {
    await bindings.transactionWorkflowService.loadFromCsv(
      utf8Text,
      accountId: accountId,
    );
  }

  Future<bool> needsImportAiAfterCsvUpload(String accountId) {
    return bindings.transactionWorkflowService.needsImportAiAfterCsvUpload(
      accountId,
    );
  }

  bool get importAiEngineConfigured => bindings.importAiEngineConfigured();

  Future<void> startBackgroundImportAiCategorization(String accountId) {
    return bindings.transactionWorkflowService
        .startBackgroundImportAiCategorization(accountId);
  }

  Future<List<CsvImportBatchSummary>> csvImportBatchesForAccount(
    String accountId,
  ) async {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final records = await bindings.transactionService.fetchTransactions(
      accountId: id,
    );
    final counts = <String, int>{};
    for (final record in records) {
      final importId = record.importId?.trim();
      if (importId == null || importId.isEmpty) continue;
      counts[importId] = (counts[importId] ?? 0) + 1;
    }
    final summaries = <CsvImportBatchSummary>[
      for (final entry in counts.entries)
        CsvImportBatchSummary(
          importId: entry.key,
          transactionCount: entry.value,
          importedAtUtc: _importedAtFromImportId(entry.key),
        ),
    ];
    summaries.sort((a, b) {
      final ai = a.importedAtUtc?.microsecondsSinceEpoch;
      final bi = b.importedAtUtc?.microsecondsSinceEpoch;
      if (ai != null && bi != null && ai != bi) return bi.compareTo(ai);
      return b.importId.compareTo(a.importId);
    });
    return summaries;
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    return bindings.transactionWorkflowService.deleteTransactionsForImportBatch(
      accountId: accountId,
      importId: importId,
    );
  }

  Future<DashboardSnapshot> buildSnapshotForAccount(String accountId) {
    return _ui.dashboard.buildSnapshot(AccountDashboardScope(accountId));
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
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return _dateOnly(monday);
  }

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) {
    return '${_dateOnly(start)}_${_dateOnly(end)}';
  }

  Future<void> setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    return bindings.budgetWorkflowService.setActiveBudgetPeriod(
      type: type,
      key: key,
    );
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    return bindings.budgetWorkflowService.commitBudgetDraft(
      periodType,
      periodKey,
      draftByNormalizedDisplayKey,
    );
  }

  Future<BudgetPerformanceSnapshot> budgetPerformanceForScope(
    DashboardScope scope, {
    BudgetPeriodType? periodType,
    String? periodKey,
  }) async {
    final effectiveType = periodType ?? BudgetPeriodType.monthly;
    final effectiveKey = periodKey ?? _monthKey(spendReference);
    final start = _periodStartFor(effectiveType, effectiveKey);
    final end = _periodEndFor(effectiveType, effectiveKey);
    final period = _budgetPeriodToDatabaseValue(effectiveType);
    final allBudgets = await bindings.budgetService.fetchBudgets();
    final budgets = allBudgets.where((budget) {
      return budget.period == period && _sameDay(budget.startDate, start);
    }).toList();
    final spentByCategory = await spentByDisplayCategoryForScopeInRange(
      scope,
      start: start,
      end: end,
    );
    final totalBudgeted = budgets.fold<double>(
      0,
      (sum, budget) => sum + budget.amount,
    );
    final totalSpent = spentByCategory.values.fold<double>(
      0,
      (sum, amount) => sum + amount,
    );
    return BudgetPerformanceSnapshot(
      periodType: effectiveType,
      periodKey: effectiveKey,
      periodLabel: effectiveKey,
      totalBudgeted: totalBudgeted,
      totalSpent: totalSpent,
      budgetedCategoryCount: budgets.length,
      onTrackCategoryCount: 0,
      totalOverspent: totalSpent > totalBudgeted
          ? totalSpent - totalBudgeted
          : 0,
      topOverspendingCategories: const [],
    );
  }

  Future<Map<String, double>> spentByDisplayCategoryForScopeInRange(
    DashboardScope scope, {
    required DateTime start,
    required DateTime end,
  }) async {
    final allTransactions = await fetchTransactions();
    final transactionsByAccount = await fetchTransactionsByAccount();
    final accounts = await fetchAccounts();
    return bindings.dashboardService.spentByDisplayCategoryForScopeInRange(
      scope: scope,
      start: start,
      end: end,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: bindings.categoryService.categoryOverrides,
      categoryDisplayRenames:
          bindings.categoryCatalogService.categoryDisplayRenames,
      merchantCategoryMemory: bindings.merchantService.merchantCategoryMemory,
      accounts: accounts,
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
    return bindings.aiCategorizationService.consumeImportAiSnackMessage();
  }
}

Account _accountFromRecord(AccountRecord record) {
  return Account(
    id: record.id,
    name: record.name,
    type: _accountTypeFromDatabaseValue(record.type),
    currentBalance: record.balance,
  );
}

AccountType _accountTypeFromDatabaseValue(String value) {
  return switch (value.trim().toLowerCase()) {
    'savings' => AccountType.savings,
    'credit_card' || 'creditcard' || 'credit card' => AccountType.creditCard,
    _ => AccountType.checking,
  };
}

Transaction _transactionFromRecord(TransactionRecord record) {
  final amount = switch (record.type.trim().toLowerCase()) {
    'expense' => -record.amount.abs(),
    'income' => record.amount.abs(),
    _ => record.amount,
  };
  return Transaction(
    date: record.date,
    description: record.description ?? record.merchant ?? '',
    amount: amount,
    accountId: record.accountId,
    categoryId: record.categoryId,
    importId: record.importId ?? (record.importedFromCsv ? 'csv' : null),
    fingerprint: record.id,
    financialRole: record.type.trim().toLowerCase() == 'income'
        ? FinancialRole.income
        : FinancialRole.expense,
  );
}

bool _isUncategorizedImportedTransaction(Transaction transaction) {
  return transaction.importId != null &&
      (transaction.categoryId == null ||
          transaction.categoryId!.trim().isEmpty);
}

DateTime _periodStartFor(BudgetPeriodType? periodType, String? periodKey) {
  final reference = DateTime.now();
  return switch (periodType) {
    BudgetPeriodType.monthly =>
      _parseYearMonthKey(periodKey) ??
          DateTime(reference.year, reference.month),
    BudgetPeriodType.weekly =>
      _parseDateKey(periodKey) ??
          reference.subtract(Duration(days: reference.weekday - 1)),
    BudgetPeriodType.custom =>
      _parseCustomRange(periodKey)?.start ??
          DateTime(reference.year, reference.month),
    _ => DateTime(reference.year, reference.month),
  };
}

DateTime _periodEndFor(BudgetPeriodType? periodType, String? periodKey) {
  final start = _periodStartFor(periodType, periodKey);
  return switch (periodType) {
    BudgetPeriodType.weekly => start.add(const Duration(days: 6)),
    BudgetPeriodType.custom => _parseCustomRange(periodKey)?.end ?? start,
    _ => DateTime(start.year, start.month + 1, 0),
  };
}

String _budgetPeriodToDatabaseValue(BudgetPeriodType type) {
  return switch (type) {
    BudgetPeriodType.monthly => 'monthly',
    BudgetPeriodType.weekly => 'weekly',
    BudgetPeriodType.custom => 'custom',
  };
}

bool _sameDay(DateTime? a, DateTime b) {
  if (a == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime? _parseYearMonthKey(String? key) {
  final parts = key?.split('-') ?? const <String>[];
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) return null;
  return DateTime(year, month);
}

DateTime? _parseDateKey(String? key) {
  final parts = key?.split('-') ?? const <String>[];
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

({DateTime start, DateTime end})? _parseCustomRange(String? key) {
  final parts = key?.split('_') ?? const <String>[];
  if (parts.length != 2) return null;
  final start = _parseDateKey(parts[0]);
  final end = _parseDateKey(parts[1]);
  if (start == null || end == null) return null;
  return (start: start, end: end);
}

String _monthKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}

String _dateOnly(DateTime date) {
  return date.toIso8601String().split('T').first;
}

DateTime? _importedAtFromImportId(String importId) {
  final micros = int.tryParse(importId);
  if (micros == null) return null;
  return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
}
