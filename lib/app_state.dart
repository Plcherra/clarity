import 'package:flutter/foundation.dart';

import 'balance_resolve.dart';
import 'bank_statement_monthly.dart';
import 'csv_parser.dart';
import 'dashboard_metrics.dart';
import 'models.dart';
import 'spend_categories.dart';

/// Holds parsed statement data and derived aggregates. No persistence.
class AppState extends ChangeNotifier {
  List<Transaction> transactions = const [];
  double totalBalance = 0;
  double spentThisMonth = 0;
  double incomeThisMonth = 0;
  double availableThisMonth = 0;
  int uncategorizedCount = 0;
  List<CategorySpend> topCategories = const [];
  List<CategoryLeakStat> biggestLeaksThisMonth = const [];
  int? burnRunwayDays;

  /// Newest calendar month first (from [monthlyGroupsFromTransactions]).
  List<MonthlyBankGroup> monthlyGroups = const [];

  /// Manual category by [transactionCategoryKey]; cleared when a new CSV is loaded.
  Map<String, String> categoryOverrides = const {};

  /// User-created category names (shown in the assignment sheet alongside built-ins).
  List<String> customCategories = const [];

  /// Lowercase base label -> user display name (renamed built-ins / display tweaks).
  Map<String, String> categoryDisplayRenames = const {};

  /// Lowercase canonical labels removed from the picker (deleted built-ins).
  Set<String> categoriesHiddenFromPicker = {};

  /// Reference month for "spent this month" / top categories (set in [loadFromCsv]).
  DateTime _spendReference = DateTime.now();

  /// Same instant used for monthly aggregates (defaults to import time / [loadFromCsv]).
  DateTime get spendReference => _spendReference;

  /// Loads and aggregates using [reference] for "this month" (defaults to now, local).
  void loadFromCsv(String utf8Text, {DateTime? reference}) {
    final ref = reference ?? DateTime.now();
    _spendReference = ref;
    categoryOverrides = const {};
    categoryDisplayRenames = const {};
    categoriesHiddenFromPicker = <String>{};
    final result = parseBankCsv(utf8Text);
    transactions = List.unmodifiable(result.transactions);
    totalBalance = resolveTotalBalance(transactions, result.totalBalance);
    _recomputeDerived(result.transactions, result.diagnostics);
    notifyListeners();
  }

  /// Assigns a category to a transaction and refreshes aggregates.
  void setCategoryOverride(Transaction t, String category) {
    final key = transactionCategoryKey(t);
    final next = Map<String, String>.from(categoryOverrides);
    next[key] = category;
    categoryOverrides = next;
    _recomputeDerived(transactions, null);
    notifyListeners();
  }

  /// Adds a new category name (if needed), assigns [t], and notifies.
  void createCategoryAndAssign(Transaction t, String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    if (name.toLowerCase() == 'uncategorized') return;
    if (!isBuiltInSpendCategory(name) && !customCategories.contains(name)) {
      customCategories = [...customCategories, name];
    }
    setCategoryOverride(t, name);
  }

  /// Deletes a category from the picker and clears assignments using it (any label, built-in or custom).
  void deleteCategory(String canonicalLabel) {
    final k = canonicalLabel.trim().toLowerCase();
    if (k.isEmpty) return;

    customCategories = customCategories
        .where((c) => c.trim().toLowerCase() != k)
        .toList();

    if (kSelectableSpendCategories.any((c) => c.toLowerCase() == k)) {
      categoriesHiddenFromPicker = {...categoriesHiddenFromPicker, k};
    }

    final nextRenames = Map<String, String>.from(categoryDisplayRenames);
    nextRenames.remove(k);
    categoryDisplayRenames = nextRenames;

    final next = <String, String>{};
    for (final e in categoryOverrides.entries) {
      if (e.value.trim().toLowerCase() != k) {
        next[e.key] = e.value;
      }
    }
    categoryOverrides = next;
    _recomputeDerived(transactions, null);
    notifyListeners();
  }

  /// Renames a category. Built-ins: display-only map (overrides stay canonical). Custom: text + overrides.
  void renameCategory(String oldLabel, String newLabel) {
    final oldK = oldLabel.trim().toLowerCase();
    final newN = newLabel.trim();
    if (newN.isEmpty || oldK == newN.toLowerCase()) return;

    final isBuiltIn = kSelectableSpendCategories.any(
      (c) => c.toLowerCase() == oldK,
    );
    if (isBuiltIn) {
      categoryDisplayRenames = {
        ...categoryDisplayRenames,
        oldK: newN,
      };
    } else {
      final nextOv = <String, String>{};
      for (final e in categoryOverrides.entries) {
        if (e.value.trim().toLowerCase() == oldK) {
          nextOv[e.key] = newN;
        } else {
          nextOv[e.key] = e.value;
        }
      }
      categoryOverrides = nextOv;

      customCategories = customCategories
          .map((c) => c.trim().toLowerCase() == oldK ? newN : c)
          .toList();
    }

    _recomputeDerived(transactions, null);
    notifyListeners();
  }

  void _recomputeDerived(
    List<Transaction> txsForGrouping,
    CsvParseDiagnostics? diag,
  ) {
    spentThisMonth = _spentThisMonth(transactions, _spendReference);
    incomeThisMonth = totalIncomeInMonth(transactions, _spendReference);
    availableThisMonth = incomeThisMonth - spentThisMonth;
    uncategorizedCount = uncategorizedTransactionCount(
      transactions,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
    biggestLeaksThisMonth = List.unmodifiable(
      biggestCategoryLeaks(
        transactions,
        _spendReference,
        limit: 3,
        categoryOverrides: categoryOverrides,
        categoryDisplayRenamesLower: categoryDisplayRenames,
      ),
    );
    burnRunwayDays = runwayDaysFromBurnRate(
      totalBalance: totalBalance,
      spentThisMonth: spentThisMonth,
      referenceInMonth: _spendReference,
    );
    topCategories = List.unmodifiable(
      _topCategoriesThisMonth(
        transactions,
        _spendReference,
        5,
        categoryOverrides,
        categoryDisplayRenames,
      ),
    );
    final grouped = monthlyGroupsFromTransactions(
      txsForGrouping,
      categoryOverrides: categoryOverrides,
      categoryDisplayRenamesLower: categoryDisplayRenames,
    );
    monthlyGroups = List.unmodifiable(grouped.reversed.toList());
    if (kDebugMode && diag != null) {
      _debugPrintCsvImportDiagnostics(
        transactions,
        grouped,
        diag,
      );
    }
  }

  void clear() {
    transactions = const [];
    totalBalance = 0;
    spentThisMonth = 0;
    incomeThisMonth = 0;
    availableThisMonth = 0;
    uncategorizedCount = 0;
    topCategories = const [];
    biggestLeaksThisMonth = const [];
    burnRunwayDays = null;
    monthlyGroups = const [];
    categoryOverrides = const {};
    customCategories = const [];
    categoryDisplayRenames = const {};
    categoriesHiddenFromPicker = <String>{};
    notifyListeners();
  }
}

/// Outflows in the calendar month of [reference] in the local timezone.
double _spentThisMonth(
  List<Transaction> txs,
  DateTime reference,
) {
  final y = reference.year;
  final m = reference.month;
  var sum = 0.0;
  for (final t in txs) {
    final d = t.date;
    if (d.year == y && d.month == m && t.isOutflow) {
      sum += -t.amount;
    }
  }
  return sum;
}

bool _inMonth(DateTime d, DateTime reference) {
  return d.year == reference.year && d.month == reference.month;
}

List<CategorySpend> _topCategoriesThisMonth(
  List<Transaction> txs,
  DateTime reference,
  int limit,
  Map<String, String> categoryOverrides,
  Map<String, String> categoryDisplayRenamesLower,
) {
  final map = <String, double>{};
  for (final t in txs) {
    if (t.amount >= 0) continue;
    if (!_inMonth(t.date, reference)) continue;
    final base = spendGroupLabel(t, categoryOverrides: categoryOverrides);
    if (isIncomeCategoryLabel(base)) continue;
    final name = applyCategoryDisplayRenames(base, categoryDisplayRenamesLower);
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

/// Temporary diagnostics for wrong month counts / stray months (remove when fixed).
void _debugPrintCsvImportDiagnostics(
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

  final jan2025Parsed = txs
      .where((t) => t.date.year == 2025 && t.date.month == 1)
      .length;
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

  final dec2026Parsed = txs
      .where((t) => t.date.year == 2026 && t.date.month == 12)
      .length;
  debugPrint(
    '[Clarity][CSV import] Rows with parsed date in December 2026: '
    '$dec2026Parsed',
  );
}
