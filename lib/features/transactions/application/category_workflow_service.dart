import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../accounts/application/account_service.dart';
import '../../categories/application/category_read_model.dart';
import '../../categories/application/category_service.dart';
import '../../profile/application/profile_service.dart';
import '../domain/spend_categories.dart';
import 'transaction_service.dart';

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

  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory,
  ) {
    return const [];
  }

  Future<int> undoCategoryApplyBatch(
    List<AiAppliedCategoryChange> batch,
  ) async {
    return 0;
  }

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
    Map<String, String> keyToCanonicalCategory,
  ) async {
    if (keyToCanonicalCategory.isEmpty) return;
    final records = await transactionService.fetchTransactions();
    final recordsByKey = {
      for (final record in records)
        transactionCategoryKey(_transactionFromRecord(record)): record,
    };
    for (final entry in keyToCanonicalCategory.entries) {
      final categoryName = entry.value.trim();
      if (categoryName.isEmpty) continue;
      final transactionRecord = recordsByKey[entry.key];
      if (transactionRecord == null) continue;
      final categoryRecord = await categoryReadModel.ensureExpenseCategory(
        categoryName,
      );
      await transactionService.updateTransaction(
        transactionRecord.id,
        categoryId: categoryRecord.id,
      );
    }
    await refreshAllState();
    notifyTransactionDataChanged();
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
