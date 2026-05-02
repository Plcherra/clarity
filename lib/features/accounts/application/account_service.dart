import '../../../core/models/models.dart';
import '../../../core/storage/accounts/account_storage.dart';
import '../../../core/storage/transactions/transaction_storage.dart';
import '../../transactions/domain/spend_categories.dart';

/// Non-null when an account row was deleted and storage was updated successfully.
class DeletedAccountPersistResult {
  const DeletedAccountPersistResult({
    required this.removedKeys,
    required this.transactionsByAccount,
  });

  final Set<String> removedKeys;
  final Map<String, List<Transaction>> transactionsByAccount;
}

/// Persisted account list and UI “current account” pointer.
class AccountService {
  String? activeAccountId;

  List<Account> accounts = const [];

  Future<void> hydratePersistedAccounts() async {
    try {
      accounts = await loadAccounts();
    } on Object {
      accounts = const [];
    }
  }

  Future<bool> addAccount(Account account) async {
    final next = [...accounts, account];
    try {
      await saveAccounts(next);
    } on Object {
      return false;
    }
    accounts = next;
    return true;
  }

  /// Removes the account row, persists accounts + txn map slice, clears [activeAccountId] when it matches.
  Future<DeletedAccountPersistResult?> deleteAccount({
    required String accountId,
    required Map<String, List<Transaction>> transactionsByAccount,
  }) async {
    final id = accountId.trim();
    if (id.isEmpty) return null;
    if (!accounts.any((a) => a.id == id)) return null;

    final removedTransactions =
        transactionsByAccount[id] ?? const <Transaction>[];
    final removedKeys = removedTransactions.map(transactionCategoryKey).toSet();

    final nextAccounts = accounts.where((a) => a.id != id).toList();
    final nextByAccount = <String, List<Transaction>>{
      for (final e in transactionsByAccount.entries)
        if (e.key != id) e.key: List.unmodifiable(e.value),
    };

    try {
      await saveAccounts(nextAccounts);
      await saveTransactionsByAccount(nextByAccount);
    } on Object {
      return null;
    }

    accounts = nextAccounts;
    if (activeAccountId == id) {
      activeAccountId = null;
    }

    return DeletedAccountPersistResult(
      removedKeys: removedKeys,
      transactionsByAccount: nextByAccount,
    );
  }
}
