import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../transactions/data/csv_parser.dart';
import '../../transactions/domain/spend_categories.dart';
import '../../transactions/domain/transaction_resolution.dart' as tx_res;
import '../domain/dashboard_metrics.dart';
import '../domain/dashboard_snapshot.dart';
import '../../transactions/domain/bank_statement_monthly.dart';

/// Derived dashboard aggregates recomputed when transactions/category state changes.
class DashboardDerivedValues {
  const DashboardDerivedValues({
    required this.spentThisMonth,
    required this.incomeThisMonth,
    required this.availableThisMonth,
    required this.uncategorizedCount,
    required this.biggestLeaksThisMonth,
    required this.burnRunwayDays,
    required this.topCategories,
    required this.monthlyGroups,
  });

  final double spentThisMonth;
  final double incomeThisMonth;
  final double availableThisMonth;
  final int uncategorizedCount;
  final List<CategoryLeakStat> biggestLeaksThisMonth;
  final int? burnRunwayDays;
  final List<CategorySpend> topCategories;
  final List<MonthlyBankGroup> monthlyGroups;
}

class DashboardService {
  List<Transaction> transactionsForDashboardScope({
    required DashboardScope scope,
    required List<Transaction> allTransactions,
    required Map<String, List<Transaction>> transactionsByAccount,
  }) {
    return switch (scope) {
      GlobalDashboardScope() => allTransactions,
      AccountDashboardScope(:final accountId) => List<Transaction>.from(
        transactionsByAccount[accountId] ?? const [],
      ),
    };
  }

  bool _inRangeInclusive(DateTime d, DateTime start, DateTime end) {
    final x = DateTime(d.year, d.month, d.day);
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    return (x.isAtSameMomentAs(a) || x.isAfter(a)) &&
        (x.isAtSameMomentAs(b) || x.isBefore(b));
  }

  Map<String, double> spentByDisplayCategoryForScopeInRange({
    required DashboardScope scope,
    required DateTime start,
    required DateTime end,
    required List<Transaction> allTransactions,
    required Map<String, List<Transaction>> transactionsByAccount,
    required Map<String, String> categoryOverrides,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
  }) {
    final scoped = transactionsForDashboardScope(
      scope: scope,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
    );
    final accountsById = {for (final a in accounts) a.id: a};
    final resolved = tx_res.resolveTransactions(
      scoped,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accountsById: accountsById,
      allTransactions: allTransactions,
    );
    final out = <String, double>{};
    for (final r in resolved) {
      final t = r.transaction;
      if (!_inRangeInclusive(t.date, start, end)) continue;
      if (!r.countsAsSpend) continue;
      final display = r.displayCategory;
      if (isIgnoredCategoryLabel(display) || isIncomeCategoryLabel(display)) {
        continue;
      }
      out[display] = (out[display] ?? 0) + (-t.amount);
    }
    return out;
  }

  Map<String, double> spentByDisplayCategoryForScope({
    required DashboardScope scope,
    required DateTime? reference,
    required List<Transaction> allTransactions,
    required Map<String, List<Transaction>> transactionsByAccount,
    required Map<String, String> categoryOverrides,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
  }) {
    final ref = reference ?? DateTime.now();
    final start = DateTime(ref.year, ref.month, 1);
    final end = DateTime(ref.year, ref.month + 1, 0);
    return spentByDisplayCategoryForScopeInRange(
      scope: scope,
      start: start,
      end: end,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
    );
  }

  Map<String, double> spentThisMonthByDisplayCategory({
    required DateTime? reference,
    required List<Transaction> allTransactions,
    required Map<String, List<Transaction>> transactionsByAccount,
    required Map<String, String> categoryOverrides,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, String> merchantCategoryMemory,
    required List<Account> accounts,
  }) {
    return spentByDisplayCategoryForScope(
      scope: const GlobalDashboardScope(),
      reference: reference,
      allTransactions: allTransactions,
      transactionsByAccount: transactionsByAccount,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenames: categoryDisplayRenames,
      merchantCategoryMemory: merchantCategoryMemory,
      accounts: accounts,
    );
  }

  DashboardDerivedValues recomputeDerived({
    required List<Transaction> activeAccountTransactions,
    required List<Transaction> allTransactionsForMetrics,
    required List<Transaction> transactionsForCsvDiagnostics,
    required CsvParseDiagnostics? diag,
    required DateTime spendReference,
    required double totalBalance,
    required List<Account> accounts,
    required Map<String, String> categoryOverrides,
    required Map<String, String> categoryDisplayRenames,
    required List<tx_res.ResolvedTransaction> Function(
      List<Transaction> txs, {
      required List<Transaction> allTransactionsContext,
    })
    resolveTransactions,
  }) {
    final spentThisMonthVal = _spentThisMonth(
      allTransactionsForMetrics,
      accounts,
      spendReference,
      categoryOverrides,
    );
    final incomeVal = totalIncomeInMonth(
      allTransactionsForMetrics,
      accounts,
      spendReference,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
    final availableVal = incomeVal - spentThisMonthVal;
    final uncategorizedCt = resolveTransactions(
      allTransactionsForMetrics,
      allTransactionsContext: allTransactionsForMetrics,
    ).where((r) => r.needsCategorization).length;
    final leaks = List<CategoryLeakStat>.unmodifiable(
      biggestCategoryLeaks(
        allTransactionsForMetrics,
        accounts,
        spendReference,
        limit: 3,
        categoryOverrides: categoryOverrides,
        categoryDisplayRenamesLower: categoryDisplayRenames,
      ),
    );
    final runway = runwayDaysFromBurnRate(
      totalBalance: totalBalance,
      spentThisMonth: spentThisMonthVal,
      referenceInMonth: spendReference,
    );
    final topCats = List<CategorySpend>.unmodifiable(
      _topCategoriesThisMonth(
        allTransactionsForMetrics,
        accounts,
        spendReference,
        5,
        categoryOverrides,
        categoryDisplayRenames,
      ),
    );
    final grouped = monthlyGroupsFromTransactions(
      activeAccountTransactions,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
    final monthlyGroupsVal = List<MonthlyBankGroup>.unmodifiable(
      grouped.reversed.toList(),
    );
    if (kDebugMode && diag != null) {
      debugPrintCsvImportDiagnostics(
        transactionsForCsvDiagnostics,
        grouped,
        diag,
      );
    }
    return DashboardDerivedValues(
      spentThisMonth: spentThisMonthVal,
      incomeThisMonth: incomeVal,
      availableThisMonth: availableVal,
      uncategorizedCount: uncategorizedCt,
      biggestLeaksThisMonth: leaks,
      burnRunwayDays: runway,
      topCategories: topCats,
      monthlyGroups: monthlyGroupsVal,
    );
  }
}

double _spentThisMonth(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime reference,
  Map<String, String> categoryOverrides,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final resolved = tx_res.resolveTransactions(
    txs,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: const {},
    merchantCategoryMemory: const {},
    accountsById: accountsById,
    allTransactions: txs,
  );
  final y = reference.year;
  final m = reference.month;
  var sum = 0.0;
  for (final r in resolved) {
    final t = r.transaction;
    final d = t.date;
    if (d.year != y || d.month != m || !t.isOutflow) continue;
    if (!r.countsAsSpend) continue;
    sum += -t.amount;
  }
  return sum;
}

bool _inMonth(DateTime d, DateTime reference) {
  return d.year == reference.year && d.month == reference.month;
}

List<CategorySpend> _topCategoriesThisMonth(
  List<Transaction> txs,
  List<Account> accounts,
  DateTime reference,
  int limit,
  Map<String, String> categoryOverrides,
  Map<String, String> categoryDisplayRenamesLower,
) {
  final accountsById = {for (final a in accounts) a.id: a};
  final resolved = tx_res.resolveTransactions(
    txs,
    categoryOverrides: categoryOverrides,
    categoryDisplayRenamesLower: categoryDisplayRenamesLower,
    merchantCategoryMemory: const {},
    accountsById: accountsById,
    allTransactions: txs,
  );
  final map = <String, double>{};
  for (final r in resolved) {
    final t = r.transaction;
    if (!_inMonth(t.date, reference)) continue;
    if (!r.countsAsSpend) continue;
    final name = r.displayCategory;
    if (isIgnoredCategoryLabel(name)) continue;
    map[name] = (map[name] ?? 0) + (-t.amount);
  }
  final list =
      map.entries
              .map((e) => CategorySpend(name: e.key, amount: e.value))
              .toList()
            ..sort((a, b) => b.amount.compareTo(a.amount));
  if (list.length <= limit) return list;
  return list.sublist(0, limit);
}

String _yearMonthKeyForDebug(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

void debugPrintCsvImportDiagnostics(
  List<Transaction> txs,
  List<MonthlyBankGroup> groupsChronological,
  CsvParseDiagnostics diag,
) {
  debugPrint(
    '[Clarity][CSV import] Column layout: '
    '${diag.layoutInferred ? "INFERRED (no header match)" : "HEADER_MATCH"} '
    '| header row index (0-based): ${diag.headerRowIndex}',
  );
  debugPrint(
    '[Clarity][CSV import] Date column: index=${diag.dateColumnIndex} '
    'header="${diag.dateColumnHeader}"',
  );
  debugPrint(
    '[Clarity][CSV import] Amount column: index=${diag.amountColumnIndex} '
    'header="${diag.amountColumnHeader}"',
  );
  if (diag.balanceColumnIndex != null) {
    debugPrint(
      '[Clarity][CSV import] Balance column: index=${diag.balanceColumnIndex} '
      'header="${diag.balanceColumnHeader}"',
    );
  }
  debugPrint('[Clarity][CSV import] ${diag.ambiguousSlashPolicy}');
  if (diag.firstParsedDateRawCell != null) {
    debugPrint(
      '[Clarity][CSV import] First data row raw date cell: '
      '"${diag.firstParsedDateRawCell}" => ${diag.firstCellParsingRule}',
    );
  }
  if (diag.lastParsedDateRawCell != null) {
    debugPrint(
      '[Clarity][CSV import] Last data row raw date cell: '
      '"${diag.lastParsedDateRawCell}" => ${diag.lastCellParsingRule}',
    );
  }

  final jan2025Parsed = txs.where((t) => t.date.year == 2025 && t.date.month == 1).length;
  debugPrint(
    '[Clarity][CSV import] Rows with parsed calendar date in January 2025: '
    '$jan2025Parsed (total parsed transaction rows: ${txs.length})',
  );

  MonthlyBankGroup? janGroup;
  for (final g in groupsChronological) {
    if (g.yearMonth == '2025-01') {
      janGroup = g;
      break;
    }
  }
  final inJanGroupAfterFilter = janGroup?.transactions.length ?? 0;
  debugPrint(
    '[Clarity][CSV import] Rows in monthly bucket 2025-01 after line filters '
    '(summary/balance skipped): $inJanGroupAfterFilter',
  );

  if (txs.isNotEmpty) {
    final f = txs.first;
    final l = txs.last;
    debugPrint(
      '[Clarity][CSV import] First row (file order): parsed date=${f.date} '
      '-> yearMonth key ${_yearMonthKeyForDebug(f.date)} | ${f.description}',
    );
    debugPrint(
      '[Clarity][CSV import] Last row (file order): parsed date=${l.date} '
      '-> yearMonth key ${_yearMonthKeyForDebug(l.date)} | ${l.description}',
    );
  }

  final dec2026Parsed = txs.where((t) => t.date.year == 2026 && t.date.month == 12).length;
  debugPrint(
    '[Clarity][CSV import] Rows with parsed date in December 2026: '
    '$dec2026Parsed',
  );
}
