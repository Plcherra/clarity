import 'dart:async';
import 'dart:io';

import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../dashboard/application/dashboard_service.dart';
import '../data/csv_import_service.dart';
import '../data/csv_parser.dart';
import '../data/transaction_service.dart';
import '../domain/spend_categories.dart';
import 'import_job_status_service.dart';

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
    required this.csvImportService,
    required this.dashboardService,
    required this.importJobStatusService,
    required this.refreshCategories,
    required this.refreshAllState,
    required this.recomputeDashboard,
    required this.notifyTransactionDataChanged,
    required this.notifyImportJobStatusChanged,
  });

  final TransactionService transactionService;
  final CsvImportService csvImportService;
  final DashboardService dashboardService;
  final ImportJobStatusService importJobStatusService;
  final Future<void> Function() refreshCategories;
  final Future<void> Function() refreshAllState;
  final TransactionDashboardRecompute recomputeDashboard;
  final void Function() notifyTransactionDataChanged;
  final void Function() notifyImportJobStatusChanged;

  Future<void> loadFromCsv(
    String utf8Text, {
    required String accountId,
    DateTime? reference,
  }) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/clarity_import_${DateTime.now().toUtc().microsecondsSinceEpoch}.csv',
    );
    try {
      await tempFile.writeAsString(utf8Text);
      await for (final progress in csvImportService.importAndCategorize(
        tempFile,
        accountId: accountId,
        refreshAfterImport: (completed) async {
          await refreshCategories();
          dashboardService.spendReference = reference ?? DateTime.now();
          final accountTransactions = await _fetchTransactions(
            accountId: completed.accountId,
          );
          await recomputeDashboard(
            activeAccountTransactions: accountTransactions,
            allTransactionsForMetrics: await _fetchTransactions(),
            transactionsForCsvDiagnostics: accountTransactions,
            diag: completed.diagnostics,
          );
          notifyTransactionDataChanged();
        },
      )) {
        importJobStatusService.applyCsvImportProgress(
          progress,
          notifyStatusChanged: notifyImportJobStatusChanged,
        );
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
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
