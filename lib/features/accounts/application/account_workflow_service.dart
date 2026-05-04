import '../../../core/models/models.dart';
import '../../transactions/data/transaction_service.dart';
import '../data/account_service.dart';

class AccountWorkflowService {
  AccountWorkflowService({
    required this.accountService,
    required this.transactionService,
    required this.refreshAllState,
    required this.notifyAccountsChanged,
  });

  final AccountService accountService;
  final TransactionService transactionService;
  final Future<void> Function() refreshAllState;
  final void Function() notifyAccountsChanged;

  Future<bool> addAccount(Account account) async {
    await accountService.createAccount(account);
    notifyAccountsChanged();
    await refreshAllState();
    return true;
  }

  Future<bool> deleteAccount(String accountId) async {
    await accountService.deleteAccount(accountId);
    notifyAccountsChanged();
    await refreshAllState();
    return true;
  }
}
