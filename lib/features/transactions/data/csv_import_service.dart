import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../dashboard/domain/balance_resolve.dart';
import '../domain/spend_categories.dart';
import '../domain/transaction_fingerprint.dart';
import 'csv_parser.dart';
import 'transaction_service.dart';

class CsvImportBatchSummary {
  const CsvImportBatchSummary({
    required this.importId,
    required this.transactionCount,
    required this.importedAtUtc,
  });

  final String importId;
  final int transactionCount;
  final DateTime? importedAtUtc;
}

class CsvImportResult {
  const CsvImportResult({
    required this.activeAccountId,
    required this.spendReference,
    required this.categoryOverrides,
    required this.transactions,
    required this.totalBalance,
    required this.diagnostics,
  });

  final String activeAccountId;
  final DateTime spendReference;
  final Map<String, String> categoryOverrides;
  final List<Transaction> transactions;
  final double totalBalance;
  final CsvParseDiagnostics? diagnostics;
}

class CsvImportService {
  List<CsvImportBatchSummary> csvImportBatchesForAccount(
    String accountId, {
    required Map<String, List<Transaction>> transactionsByAccount,
  }) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final accountTxs = transactionsByAccount[id] ?? const <Transaction>[];
    if (accountTxs.isEmpty) return const [];

    final counts = <String, int>{};
    for (final t in accountTxs) {
      final importId = t.importId?.trim();
      if (importId == null || importId.isEmpty) continue;
      counts[importId] = (counts[importId] ?? 0) + 1;
    }
    final out = <CsvImportBatchSummary>[];
    for (final e in counts.entries) {
      final micros = int.tryParse(e.key);
      final importedAtUtc = micros == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
      out.add(
        CsvImportBatchSummary(
          importId: e.key,
          transactionCount: e.value,
          importedAtUtc: importedAtUtc,
        ),
      );
    }
    out.sort((a, b) {
      final ai = a.importedAtUtc?.microsecondsSinceEpoch;
      final bi = b.importedAtUtc?.microsecondsSinceEpoch;
      if (ai != null && bi != null && ai != bi) return bi.compareTo(ai);
      return b.importId.compareTo(a.importId);
    });
    return out;
  }

  Future<CsvImportResult> loadFromCsv(
    String utf8Text, {
    required String accountId,
    required DateTime? reference,
    required List<Account> accounts,
    required Map<String, String> transactionCategoryAssignments,
    required TransactionService transactionService,
  }) async {
    final id = accountId.trim();
    if (id.isEmpty) {
      throw const FormatException('An account must be selected.');
    }
    if (!accounts.any((a) => a.id == id)) {
      throw const FormatException('Unknown account.');
    }
    final ref = reference ?? DateTime.now();
    final result = parseBankCsv(utf8Text);
    final importId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();

    final existingRecords = await transactionService.fetchTransactions(
      accountId: id,
    );
    final existing = existingRecords.map(_transactionFromRecord).toList();
    final existingFingerprints = <String>{};
    for (final t in existing) {
      // Always use the current stable identity key for dedupe, regardless of
      // what might have been stored historically in [fingerprint].
      existingFingerprints.add(transactionFingerprint(t));
    }

    final stampedNew = <Transaction>[];
    var skipped = 0;
    for (final t in result.transactions) {
      final base = Transaction(
        date: t.date,
        description: t.description,
        amount: t.amount,
        accountId: id,
        category: t.category,
        balanceAfter: t.balanceAfter,
        categoryId: null,
        importId: importId,
      );
      final key = transactionCategoryKey(base);
      final persisted = transactionCategoryAssignments[key]?.trim();
      final cid = (persisted != null && persisted.isNotEmpty)
          ? persisted
          : null;
      final withCid = Transaction(
        date: base.date,
        description: base.description,
        amount: base.amount,
        accountId: base.accountId,
        category: base.category,
        balanceAfter: base.balanceAfter,
        categoryId: cid,
        importId: base.importId,
      );
      final fp = transactionFingerprint(withCid);
      if (existingFingerprints.contains(fp)) {
        skipped += 1;
        continue;
      }
      existingFingerprints.add(fp);
      stampedNew.add(
        Transaction(
          date: withCid.date,
          description: withCid.description,
          amount: withCid.amount,
          accountId: withCid.accountId,
          category: withCid.category,
          balanceAfter: withCid.balanceAfter,
          categoryId: withCid.categoryId,
          importId: withCid.importId,
          fingerprint: fp,
        ),
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[Clarity][Import dedupe] existing=${existing.length}, '
        'parsed=${result.transactions.length}, '
        'added=${stampedNew.length}, '
        'skipped=$skipped',
      );
    }

    for (final transaction in stampedNew) {
      await transactionService.createTransaction(
        accountId: transaction.accountId,
        categoryId: transaction.categoryId,
        amount: transaction.amount.abs(),
        type: transaction.amount < 0 ? 'expense' : 'income',
        description: transaction.description,
        date: transaction.date,
        merchant: transaction.description,
        importedFromCsv: true,
        importId: transaction.importId,
      );
    }

    final transactionRecords = await transactionService.fetchTransactions(
      accountId: id,
    );
    final transactions = List<Transaction>.unmodifiable(
      transactionRecords.map(_transactionFromRecord),
    );
    return CsvImportResult(
      activeAccountId: id,
      spendReference: ref,
      categoryOverrides: const {},
      transactions: transactions,
      totalBalance: resolveTotalBalance(transactions, result.totalBalance),
      diagnostics: result.diagnostics,
    );
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
