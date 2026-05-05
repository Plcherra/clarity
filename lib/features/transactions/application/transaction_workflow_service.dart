import 'dart:async';

import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../accounts/data/account_service.dart';
import '../../dashboard/application/dashboard_service.dart';
import '../data/csv_parser.dart';
import '../data/transaction_service.dart';
import '../domain/spend_categories.dart';
import '../domain/transaction_fingerprint.dart';
import 'ai_categorization_service.dart' as app_ai;
import 'category_workflow_service.dart';

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
    required this.categoryWorkflowService,
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
  final CategoryWorkflowService categoryWorkflowService;
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

    aiCategorizationService.startCsvImportProgress(
      notifyStatusChanged: notifyImportAiStatusChanged,
    );
    try {
      final parsed = parseBankCsv(utf8Text);
      final importId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      final existing = await _fetchTransactions(accountId: id);
      final existingFingerprints = existing.map(transactionFingerprint).toSet();
      final created = <Transaction>[];
      final totalRows = parsed.transactions.length;
      var processedRows = 0;
      aiCategorizationService.updateCsvUploadProgress(
        processedRows: processedRows,
        totalRows: totalRows,
        notifyStatusChanged: notifyImportAiStatusChanged,
      );

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
        if (existingFingerprints.contains(fingerprint)) {
          processedRows += 1;
          aiCategorizationService.updateCsvUploadProgress(
            processedRows: processedRows,
            totalRows: totalRows,
            notifyStatusChanged: notifyImportAiStatusChanged,
          );
          continue;
        }
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
          importId: importId,
        );
        created.add(_transactionFromRecord(record));
        processedRows += 1;
        aiCategorizationService.updateCsvUploadProgress(
          processedRows: processedRows,
          totalRows: totalRows,
          notifyStatusChanged: notifyImportAiStatusChanged,
        );
      }

      aiCategorizationService.updateCsvUploadProgress(
        processedRows: totalRows,
        totalRows: totalRows,
        notifyStatusChanged: notifyImportAiStatusChanged,
      );

      dashboardService.spendReference = reference ?? DateTime.now();
      if (created.isNotEmpty && await _hasImportedRowsPendingCategory(id)) {
        await _categorizeImportedTransactions(id);
      }

      final accountTransactions = await _fetchTransactions(accountId: id);
      await recomputeDashboard(
        activeAccountTransactions: accountTransactions,
        allTransactionsForMetrics: await _fetchTransactions(),
        transactionsForCsvDiagnostics: accountTransactions,
        diag: parsed.diagnostics,
      );
      notifyTransactionDataChanged();
      aiCategorizationService.finishCsvImportProgress(
        notifyStatusChanged: notifyImportAiStatusChanged,
      );
    } catch (_) {
      aiCategorizationService.stopCsvImportProgress(
        notifyStatusChanged: notifyImportAiStatusChanged,
      );
      rethrow;
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
    final id = accountId.trim();
    final batchId = importId.trim();
    if (id.isEmpty || batchId.isEmpty) return 0;
    final deleted = await transactionService.deleteTransactionsForImportBatch(
      accountId: id,
      importId: batchId,
    );
    if (deleted > 0) {
      await refreshAllState();
    }
    return deleted;
  }

  Future<bool> _hasImportedRowsPendingCategory(String accountId) async {
    final transactions = await _fetchTransactions(accountId: accountId.trim());
    return transactions.any(_isUncategorizedImportedTransaction);
  }

  Future<void> _categorizeImportedTransactions(String accountId) async {
    final id = accountId.trim();
    if (id.isEmpty) return;

    var importedAiRows = <Transaction>[];

    List<Transaction> pendingImportedRowsForAccount(String accountId) {
      if (accountId.trim() != id) return const [];
      return importedAiRows
          .where(
            (transaction) => _isUncategorizedImportedTransaction(transaction),
          )
          .toList();
    }

    importedAiRows = await _fetchTransactions(accountId: id);
    await aiCategorizationService.startBackgroundImportAiCategorization(
      id,
      importAiEngineConfigured: importAiEngineConfigured(),
      pendingImportedRowsForAccount: pendingImportedRowsForAccount,
      merchantCategoryMemory: const {},
      applyPrefilledMerchantChunks: (_) async {},
      allowedCategoryPickerLabels: kSelectableSpendCategories,
      applyCategories: (assignments) async {
        if (assignments.isEmpty) return;
        await categoryWorkflowService.bulkSetCategoryOverrides(
          assignments,
          availableTransactions: importedAiRows,
          refreshAfter: false,
        );
        final assignedKeys = assignments.keys.toSet();
        importedAiRows = importedAiRows
            .where(
              (transaction) =>
                  !assignedKeys.contains(transactionCategoryKey(transaction)),
            )
            .toList();
      },
      notifyStatusChanged: notifyImportAiStatusChanged,
    );
  }

  Future<TransactionRecord> _createTransactionFromModel(
    Transaction transaction, {
    bool importedFromCsv = false,
    String? importId,
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
      importId: importId,
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
