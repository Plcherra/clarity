import 'dart:async';

import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../accounts/application/account_service.dart';
import '../../categories/application/category_catalog_service.dart';
import '../../dashboard/application/dashboard_service.dart';
import '../data/ai_categorization_service.dart' as data_ai;
import '../data/csv_parser.dart';
import '../domain/spend_categories.dart';
import '../domain/transaction_fingerprint.dart';
import 'ai_categorization_service.dart' as app_ai;
import 'category_service.dart';
import 'category_workflow_service.dart';
import 'merchant_service.dart';
import 'transaction_service.dart';

typedef TransactionDashboardRecompute =
    FutureOr<void> Function({
      required List<Transaction> activeAccountTransactions,
      required List<Transaction> allTransactionsForMetrics,
      required List<Transaction> transactionsForCsvDiagnostics,
      required CsvParseDiagnostics? diag,
    });

class TransactionWorkflowService {
  TransactionWorkflowService({
    required this.transactionService,
    required this.categoryService,
    required this.categoryCatalogService,
    required this.categoryWorkflowService,
    required this.merchantService,
    required this.accountService,
    required this.dashboardService,
    required this.aiCategorizationService,
    required this.importAiEngineConfigured,
    required this.refreshAllState,
    required this.recomputeDashboard,
    required this.notifyTransactionDataChanged,
    required this.notifyImportAiStatusChanged,
  });

  final TransactionService transactionService;
  final CategoryService categoryService;
  final CategoryCatalogService categoryCatalogService;
  final CategoryWorkflowService categoryWorkflowService;
  final MerchantService merchantService;
  final AccountService accountService;
  final DashboardService dashboardService;
  final app_ai.AiCategorizationApplicationService aiCategorizationService;
  final bool Function() importAiEngineConfigured;
  final Future<void> Function() refreshAllState;
  final TransactionDashboardRecompute recomputeDashboard;
  final void Function() notifyTransactionDataChanged;
  final void Function() notifyImportAiStatusChanged;

  Future<void> loadFromCsv(
    String utf8Text, {
    required String accountId,
    DateTime? reference,
  }) async {
    final id = accountId.trim();
    if (id.isEmpty) {
      throw const FormatException('An account must be selected.');
    }

    final accounts = await accountService.fetchAccounts();
    if (!accounts.any((account) => account.id == id)) {
      throw const FormatException('Unknown account.');
    }

    final parsed = parseBankCsv(utf8Text);
    final existing = await _fetchTransactions(accountId: id);
    final existingFingerprints = existing.map(transactionFingerprint).toSet();
    final created = <Transaction>[];

    for (final transaction in parsed.transactions) {
      final stamped = Transaction(
        date: transaction.date,
        description: transaction.description,
        amount: transaction.amount,
        accountId: id,
        category: transaction.category,
        balanceAfter: transaction.balanceAfter,
      );
      final fingerprint = transactionFingerprint(stamped);
      if (existingFingerprints.contains(fingerprint)) continue;
      existingFingerprints.add(fingerprint);
      final record = await _createTransactionFromModel(
        Transaction(
          date: stamped.date,
          description: stamped.description,
          amount: stamped.amount,
          accountId: stamped.accountId,
          category: stamped.category,
          balanceAfter: stamped.balanceAfter,
          fingerprint: fingerprint,
        ),
        importedFromCsv: true,
      );
      created.add(_transactionFromRecord(record));
    }

    final accountTransactions = await _fetchTransactions(accountId: id);
    dashboardService.spendReference = reference ?? DateTime.now();
    await recomputeDashboard(
      activeAccountTransactions: accountTransactions,
      allTransactionsForMetrics: await _fetchTransactions(),
      transactionsForCsvDiagnostics: accountTransactions,
      diag: parsed.diagnostics,
    );
    notifyTransactionDataChanged();

    if (created.isNotEmpty && needsImportAiAfterCsvUpload(id)) {
      unawaited(startBackgroundImportAiCategorization(id));
    }
  }

  Future<TransactionRecord> addTransaction(Transaction transaction) {
    return _createTransactionFromModel(transaction);
  }

  Future<bool> deleteTransaction(Transaction transaction) async {
    final record = await _findRecordForTransaction(transaction);
    if (record == null) return false;
    await transactionService.deleteTransaction(record.id);
    await refreshAllState();
    return true;
  }

  Future<int> clearTransactionsForAccount(String accountId) async {
    final records = await transactionService.fetchTransactions(
      accountId: accountId.trim(),
    );
    for (final record in records) {
      await transactionService.deleteTransaction(record.id);
    }
    await refreshAllState();
    return records.length;
  }

  Future<int> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    return 0;
  }

  bool needsImportAiAfterCsvUpload(String accountId) {
    return false;
  }

  Future<void> startBackgroundImportAiCategorization(String accountId) async {
    notifyImportAiStatusChanged();
  }

  Future<({int applied, int queuedForReview})>
  autoCategorizeGlobalUncategorized({
    required data_ai.AICategorizationService service,
    double autoApplyConfidenceThreshold = 0.90,
  }) async {
    return (applied: 0, queuedForReview: 0);
  }

  Future<int> undoLastAiAutoApply() async {
    return 0;
  }

  Future<TransactionRecord> _createTransactionFromModel(
    Transaction transaction, {
    bool importedFromCsv = false,
  }) {
    return transactionService.createTransaction(
      accountId: transaction.accountId,
      categoryId: null,
      amount: transaction.amount.abs(),
      type: transaction.amount < 0 ? 'expense' : 'income',
      description: transaction.description,
      date: transaction.date,
      merchant: transaction.description,
      importedFromCsv: importedFromCsv,
    );
  }

  Future<TransactionRecord?> _findRecordForTransaction(
    Transaction transaction,
  ) async {
    final records = await transactionService.fetchTransactions(
      accountId: transaction.accountId,
    );
    final targetKey = transaction.fingerprint?.trim().isNotEmpty == true
        ? transaction.fingerprint!
        : transactionCategoryKey(transaction);
    for (final record in records) {
      final current = _transactionFromRecord(record);
      final key = current.fingerprint?.trim().isNotEmpty == true
          ? current.fingerprint!
          : transactionCategoryKey(current);
      if (key == targetKey) return record;
    }
    return null;
  }

  Future<List<Transaction>> _fetchTransactions({String? accountId}) async {
    final records = await transactionService.fetchTransactions(
      accountId: accountId,
    );
    return records.map(_transactionFromRecord).toList();
  }
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
    importId: record.importedFromCsv ? 'csv' : null,
    fingerprint: record.id,
    financialRole: record.type.trim().toLowerCase() == 'income'
        ? FinancialRole.income
        : FinancialRole.expense,
  );
}
