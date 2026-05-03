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
  final Future<void> Function() refreshAllState;
  final void Function() notifyAccountsChanged;

  Future<bool> addAccount(Account account) async {
    await accountService.createAccount(
      name: account.name,
      type: _accountTypeToDatabaseValue(account.type),
      balance: account.currentBalance ?? 0,
    );
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

String _accountTypeToDatabaseValue(AccountType type) {
  return switch (type) {
    AccountType.checking => 'checking',
    AccountType.savings => 'savings',
    AccountType.creditCard => 'credit_card',
  };
}
