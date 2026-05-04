import '../core/models/models.dart';
import '../core/supabase/supabase_records.dart';
import '../features/accounts/data/account_service.dart';
import '../features/categories/application/category_read_model.dart';
import '../features/dashboard/application/dashboard_service.dart';
import '../features/transactions/data/csv_parser.dart';
import '../features/transactions/data/transaction_service.dart';
import '../features/transactions/domain/transaction_resolution.dart' as tx_res;

/// Coordinates dashboard recomputation from the app service graph.
class DashboardRefreshCoordinator {
  DashboardRefreshCoordinator({
    required this.dashboardService,
    required this.transactionService,
    required this.accountService,
    required this.categoryReadModel,
    required this.notifyTransactionDataChanged,
  });

  final DashboardService dashboardService;
  final TransactionService transactionService;
  final AccountService accountService;
  final CategoryReadModel categoryReadModel;
  final void Function() notifyTransactionDataChanged;

  Future<List<Transaction>> refreshAllState() async {
    final accounts = await _fetchAccounts();
    final transactions = await _fetchTransactions();
    _recomputeDashboard(
      activeAccountTransactions: transactions,
      allTransactionsForMetrics: transactions,
      transactionsForCsvDiagnostics: transactions,
      diagnostics: null,
      accounts: accounts,
    );
    notifyTransactionDataChanged();
    return transactions;
  }

  Future<void> syncAfterTransactionWorkflow({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diagnostics,
  }) async {
    final accounts = await _fetchAccounts();
    _recomputeDashboard(
      activeAccountTransactions: activeAccountTransactions,
      allTransactionsForMetrics: allTransactionsForMetrics,
      transactionsForCsvDiagnostics: transactionsForCsvDiagnostics,
      diagnostics: diagnostics,
      accounts: accounts,
    );
  }

  void _recomputeDashboard({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diagnostics,
    required List<Account> accounts,
  }) {
    dashboardService.recomputeDerivedState(
      activeAccountTransactions: activeAccountTransactions,
      allTransactionsForMetrics: allTransactionsForMetrics,
      transactionsForCsvDiagnostics: transactionsForCsvDiagnostics,
      diag: diagnostics,
      accounts: accounts,
      categoryOverrides: const {},
      categoryDisplayRenames: categoryReadModel.categoryDisplayRenames,
      resolveTransactions: (txs, {required allTransactionsContext}) {
        return _resolveTransactions(
          txs,
          accounts: accounts,
          allTransactionsContext: allTransactionsContext,
        );
      },
    );
  }

  List<tx_res.ResolvedTransaction> _resolveTransactions(
    List<Transaction> txs, {
    required List<Account> accounts,
    required List<Transaction> allTransactionsContext,
  }) {
    return tx_res.resolveTransactions(
      txs,
      categoryOverrides: const {},
      categoryDisplayRenamesLower: categoryReadModel.categoryDisplayRenames,
      merchantCategoryMemory: const {},
      accountsById: {for (final account in accounts) account.id: account},
      allTransactions: allTransactionsContext,
    );
  }

  Future<List<Account>> _fetchAccounts() async {
    return accountService.fetchAccounts();
  }

  Future<List<Transaction>> _fetchTransactions() async {
    final records = await transactionService.fetchTransactions();
    return records
        .map(
          (record) => _transactionFromRecord(
            record,
            categoryNameForId: categoryReadModel.categoryNameForId,
          ),
        )
        .toList();
  }
}

Transaction _transactionFromRecord(
  TransactionRecord record, {
  String? Function(String? id)? categoryNameForId,
}) {
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
    categoryId: categoryNameForId?.call(record.categoryId),
    importId: record.importId ?? (record.importedFromCsv ? 'csv' : null),
    fingerprint: record.id,
    financialRole: record.type.trim().toLowerCase() == 'income'
        ? FinancialRole.income
        : FinancialRole.expense,
  );
}
