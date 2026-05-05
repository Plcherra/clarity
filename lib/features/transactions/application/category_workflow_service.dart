import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../accounts/data/account_service.dart';
import '../../categories/application/category_read_model.dart';
import '../../categories/data/category_service.dart';
import '../../profile/application/profile_service.dart';
import '../data/transaction_service.dart';
import '../domain/spend_categories.dart';

class CategoryWorkflowService {
  CategoryWorkflowService({
    required this.categoryService,
    required this.categoryReadModel,
    required this.transactionService,
    required this.accountService,
    required this.profileService,
    required this.refreshAllState,
    required this.notifyTransactionDataChanged,
  });

  final CategoryService categoryService;
  final CategoryReadModel categoryReadModel;
  final TransactionService transactionService;
  final AccountService accountService;
  final ProfileService profileService;
  final Future<void> Function() refreshAllState;
  final void Function() notifyTransactionDataChanged;

  Future<void> setCategoryOverride(
    Transaction transaction,
    String category,
  ) async {
    final categoryRecord = await categoryReadModel.ensureExpenseCategory(
      category,
    );
    final transactionRecord = await _findRecordForTransaction(transaction);
    if (transactionRecord == null) return;
    await transactionService.updateTransaction(
      transactionRecord.id,
      categoryId: categoryRecord.id,
    );
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> bulkSetCategoryOverrides(
    Map<String, String> keyToCanonicalCategory, {
    Iterable<Transaction>? availableTransactions,
    bool refreshAfter = true,
  }) async {
    if (keyToCanonicalCategory.isEmpty) return;
    final transactionIdsByKey = <String, String>{};
    if (availableTransactions != null) {
      for (final transaction in availableTransactions) {
        final id = transaction.fingerprint?.trim();
        if (id == null || id.isEmpty) continue;
        transactionIdsByKey[transactionCategoryKey(transaction)] = id;
      }
    } else {
      final records = await transactionService.fetchTransactions();
      for (final record in records) {
        transactionIdsByKey[transactionCategoryKey(
              _transactionFromRecord(record),
            )] =
            record.id;
      }
    }

    final categoryByName = <String, CategoryRecord>{};
    for (final categoryName in keyToCanonicalCategory.values) {
      final name = categoryName.trim();
      if (name.isEmpty || categoryByName.containsKey(name.toLowerCase())) {
        continue;
      }
      categoryByName[name.toLowerCase()] = await categoryReadModel
          .ensureExpenseCategory(name);
    }

    final transactionIdsByCategoryId = <String, List<String>>{};
    for (final entry in keyToCanonicalCategory.entries) {
      final categoryName = entry.value.trim();
      if (categoryName.isEmpty) continue;
      final transactionId = transactionIdsByKey[entry.key];
      if (transactionId == null) continue;
      final categoryRecord = categoryByName[categoryName.toLowerCase()];
      if (categoryRecord == null) continue;
      transactionIdsByCategoryId
          .putIfAbsent(categoryRecord.id, () => <String>[])
          .add(transactionId);
    }

    for (final entry in transactionIdsByCategoryId.entries) {
      await transactionService.updateTransactionsCategory(
        ids: entry.value,
        categoryId: entry.key,
      );
    }
    if (refreshAfter) {
      await refreshAllState();
      notifyTransactionDataChanged();
    }
  }

  Future<void> createCategoryAndAssign(
    Transaction transaction,
    String rawName,
  ) async {
    final name = rawName.trim();
    if (name.isEmpty || name.toLowerCase() == 'uncategorized') return;
    final categoryRecord = await categoryReadModel.ensureExpenseCategory(name);
    final transactionRecord = await _findRecordForTransaction(transaction);
    if (transactionRecord == null) return;
    await transactionService.updateTransaction(
      transactionRecord.id,
      categoryId: categoryRecord.id,
    );
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> deleteCategory(String canonicalLabel) async {
    final key = canonicalLabel.trim().toLowerCase();
    if (key.isEmpty) return;
    final categoryRecord = categoryReadModel.categoryByName(canonicalLabel);
    if (categoryRecord == null) return;
    await categoryService.deleteCategory(categoryRecord.id);
    await categoryReadModel.refresh();
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<void> renameCategory(String oldLabel, String newLabel) async {
    final oldKey = oldLabel.trim().toLowerCase();
    final next = newLabel.trim();
    if (oldKey.isEmpty || next.isEmpty) return;
    final categoryRecord = categoryReadModel.categoryByName(oldLabel);
    if (categoryRecord == null) return;
    await categoryService.updateCategory(categoryRecord.id, name: next);
    await categoryReadModel.refresh();
    await refreshAllState();
    notifyTransactionDataChanged();
  }

  Future<TransactionRecord?> _findRecordForTransaction(
    Transaction transaction,
  ) async {
    final id = transaction.fingerprint?.trim();
    if (id != null && id.isNotEmpty) {
      final records = await transactionService.fetchTransactions(
        accountId: transaction.accountId,
      );
      for (final record in records) {
        if (record.id == id) return record;
      }
    }

    final records = await transactionService.fetchTransactions(
      accountId: transaction.accountId,
    );
    final targetKey = transactionCategoryKey(transaction);
    for (final record in records) {
      if (transactionCategoryKey(_transactionFromRecord(record)) == targetKey) {
        return record;
      }
    }
    return null;
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
