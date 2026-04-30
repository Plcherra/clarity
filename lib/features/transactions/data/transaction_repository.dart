import '../../../core/models/models.dart';
import '../../../core/storage/transactions/transaction_storage.dart';
import '../domain/spend_categories.dart';
import '../domain/transaction_fingerprint.dart';

class TransactionHydrationResult {
  const TransactionHydrationResult({required this.activeTransactions});

  final List<Transaction> activeTransactions;
}

class TransactionDedupeResult {
  const TransactionDedupeResult({
    required this.changed,
    required this.activeTransactions,
  });

  final bool changed;
  final List<Transaction> activeTransactions;
}

class TransactionMutationResult {
  const TransactionMutationResult({
    required this.success,
    required this.removedKeys,
    required this.removedCount,
  });

  final bool success;
  final Set<String> removedKeys;
  final int removedCount;
}

class TransactionRepository {
  /// All persisted transactions keyed by accountId (append-only by import).
  Map<String, List<Transaction>> transactionsByAccount = const {};

  List<Transaction> get allTransactions {
    if (transactionsByAccount.isEmpty) return const [];
    final out = <Transaction>[];
    for (final e in transactionsByAccount.entries) {
      out.addAll(e.value);
    }
    return out;
  }

  List<Transaction> activeTransactionsFor(String? activeAccountId) {
    if (activeAccountId == null) return const [];
    return List<Transaction>.unmodifiable(
      transactionsByAccount[activeAccountId] ?? const <Transaction>[],
    );
  }

  void save() {
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
  }

  Future<TransactionHydrationResult> hydratePersistedTransactions({
    required String? activeAccountId,
  }) async {
    try {
      transactionsByAccount = await loadTransactionsByAccount();
    } on Object {
      transactionsByAccount = {};
    }
    return TransactionHydrationResult(
      activeTransactions: activeTransactionsFor(activeAccountId),
    );
  }

  /// One-time migration: remove duplicated transactions caused by unstable v1 fingerprints.
  ///
  /// Keeps one row per stable identity key per account, preferring rows with:
  /// - persisted/manual categoryId
  /// - non-null running balance
  /// - earliest importId
  Future<TransactionDedupeResult> dedupePersistedTransactionsIfNeeded({
    required String? activeAccountId,
  }) async {
    final done = await getTransactionsDedupeMigrationDone();
    if (done) {
      return TransactionDedupeResult(
        changed: false,
        activeTransactions: activeTransactionsFor(activeAccountId),
      );
    }

    Transaction pickBetter(Transaction a, Transaction b) {
      int score(Transaction t) {
        var s = 0;
        final cid = t.categoryId;
        if (cid != null && cid.trim().isNotEmpty) s += 1000;
        if (t.balanceAfter != null) s += 10;
        return s;
      }

      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa > sb ? a : b;

      final ia = int.tryParse(a.importId ?? '');
      final ib = int.tryParse(b.importId ?? '');
      if (ia != null && ib != null && ia != ib) {
        return ia < ib ? a : b;
      }

      return a;
    }

    var changed = false;
    final next = <String, List<Transaction>>{};
    for (final e in transactionsByAccount.entries) {
      final accountId = e.key;
      final list = e.value;
      final byKey = <String, Transaction>{};
      for (final t in list) {
        final k = transactionFingerprint(t);
        final existing = byKey[k];
        if (existing == null) {
          byKey[k] = t;
        } else {
          byKey[k] = pickBetter(existing, t);
          changed = true;
        }
      }
      next[accountId] = byKey.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (next[accountId]!.length != list.length) changed = true;
    }

    if (changed) {
      transactionsByAccount = next;
      await saveTransactionsByAccount(transactionsByAccount);
    }

    await setTransactionsDedupeMigrationDone();
    return TransactionDedupeResult(
      changed: changed,
      activeTransactions: activeTransactionsFor(activeAccountId),
    );
  }

  /// Deletes a single transaction row.
  Future<TransactionMutationResult> deleteTransaction(
    Transaction transaction,
  ) async {
    final key = transactionCategoryKey(transaction);
    if (key.trim().isEmpty) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }

    final nextByAccount = <String, List<Transaction>>{};
    var removed = false;
    for (final e in transactionsByAccount.entries) {
      final nextList = <Transaction>[];
      for (final t in e.value) {
        if (transactionCategoryKey(t) == key) {
          removed = true;
          continue;
        }
        nextList.add(t);
      }
      nextByAccount[e.key] = List<Transaction>.unmodifiable(nextList);
    }
    if (!removed) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }

    transactionsByAccount = nextByAccount;
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    return TransactionMutationResult(
      success: true,
      removedKeys: {key},
      removedCount: 1,
    );
  }

  /// Deletes all transactions for one account.
  Future<TransactionMutationResult> clearTransactionsForAccount(
    String accountId,
  ) async {
    final id = accountId.trim();
    if (id.isEmpty) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }
    final existing = transactionsByAccount[id] ?? const <Transaction>[];
    if (existing.isEmpty) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }

    final removedKeys = existing.map(transactionCategoryKey).toSet();
    final nextByAccount = <String, List<Transaction>>{
      for (final e in transactionsByAccount.entries)
        e.key: e.key == id
            ? const <Transaction>[]
            : List<Transaction>.unmodifiable(e.value),
    };

    transactionsByAccount = nextByAccount;
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    return TransactionMutationResult(
      success: true,
      removedKeys: removedKeys,
      removedCount: removedKeys.length,
    );
  }

  Future<TransactionMutationResult> deleteTransactionsForImportBatch({
    required String accountId,
    required String importId,
  }) async {
    final id = accountId.trim();
    final targetImportId = importId.trim();
    if (id.isEmpty || targetImportId.isEmpty) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }

    final existing = transactionsByAccount[id] ?? const <Transaction>[];
    if (existing.isEmpty) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }

    final kept = <Transaction>[];
    final removed = <Transaction>[];
    for (final t in existing) {
      if ((t.importId?.trim() ?? '') == targetImportId) {
        removed.add(t);
      } else {
        kept.add(t);
      }
    }
    if (removed.isEmpty) {
      return const TransactionMutationResult(
        success: false,
        removedKeys: {},
        removedCount: 0,
      );
    }

    final removedKeys = removed.map(transactionCategoryKey).toSet();
    final nextByAccount = <String, List<Transaction>>{
      for (final e in transactionsByAccount.entries)
        e.key: e.key == id
            ? List<Transaction>.unmodifiable(kept)
            : List<Transaction>.unmodifiable(e.value),
    };

    transactionsByAccount = nextByAccount;
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
    return TransactionMutationResult(
      success: true,
      removedKeys: removedKeys,
      removedCount: removed.length,
    );
  }

  void persistActiveAccountTransactionsIfAny({
    required String? activeAccountId,
    required List<Transaction> transactions,
  }) {
    final id = activeAccountId;
    if (id == null || id.trim().isEmpty) return;
    if (!transactionsByAccount.containsKey(id)) return;
    transactionsByAccount = {...transactionsByAccount, id: transactions};
    saveTransactionsByAccount(transactionsByAccount).catchError((_) {});
  }
}
