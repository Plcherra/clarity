import '../../../core/models/models.dart';
import '../../transactions/application/category_service.dart';
import '../../transactions/application/transaction_service.dart';
import 'account_service.dart';

class AccountWorkflowService {
  AccountWorkflowService({
    required this.accountService,
    required this.transactionService,
    required this.categoryService,
    required this.refreshAllState,
    required this.notifyAccountsChanged,
  });

  final AccountService accountService;
  final TransactionService transactionService;
  final CategoryService categoryService;
  final void Function() refreshAllState;
  final void Function() notifyAccountsChanged;

  Future<bool> addAccount(Account account) async {
    final ok = await accountService.addAccount(account);
    if (ok) notifyAccountsChanged();
    return ok;
  }

  Future<bool> deleteAccount(String accountId) async {
    final applied = await accountService.deleteAccount(
      accountId: accountId,
      transactionsByAccount: transactionService.transactionsByAccount,
    );
    if (applied == null) return false;

    transactionService.transactionsByAccount = applied.transactionsByAccount;
    transactionService.removeTransactionMetadataForKeys(
      applied.removedKeys,
      categoryService: categoryService,
    );
    transactionService.persistTransactionCategoryAssignments();
    transactionService.persistAiCategorySuggestions().catchError((_) {});
    refreshAllState();
    return true;
  }
}
