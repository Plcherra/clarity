import '../../../core/formatting/formatting.dart';
import '../../../core/storage/budgets/budget_keys.dart';
import '../../../core/storage/budgets/budget_storage.dart';
import '../domain/budget_models.dart';

/// Persisted monthly / weekly / custom budget amounts and active period selection.
///
/// Does not depend on [ChangeNotifier]; [AppState] owns this repository and calls
/// `notifyListeners` / `refreshAllState` after mutations that affect UI.
class BudgetRepository {
  /// Month-aware budget amounts:
  /// `YYYY-MM` -> ([budgetDisplayKey] of display label -> amount).
  Map<String, Map<String, double>> categoryMonthlyBudgetsByYearMonth = {};

  /// Week-aware budget amounts:
  /// `YYYY-MM-DD` (week start Monday) -> ([budgetDisplayKey] -> amount).
  Map<String, Map<String, double>> categoryWeeklyBudgetsByWeekStart = {};

  /// Custom-range budget amounts:
  /// `customKey` -> ([budgetDisplayKey] -> amount).
  Map<String, Map<String, double>> categoryCustomBudgetsByKey = {};

  /// Custom-range key -> explicit date range.
  Map<String, BudgetPeriodRange> customBudgetRangesByKey = {};

  BudgetPeriodType activeBudgetPeriodType = BudgetPeriodType.monthly;
  String? activeBudgetPeriodKey;

  Future<void> hydrate({required DateTime reference}) async {
    try {
      final snapshot = await loadBudgetSnapshot(reference: reference);
      categoryMonthlyBudgetsByYearMonth = snapshot.monthly;
      categoryWeeklyBudgetsByWeekStart = snapshot.weekly;
      categoryCustomBudgetsByKey = snapshot.custom;
      customBudgetRangesByKey = {
        for (final e in snapshot.customRanges.entries)
          e.key: BudgetPeriodRange(
            start: e.value.start,
            end: e.value.end,
          ),
      };
    } on Object {
      categoryMonthlyBudgetsByYearMonth = {};
      categoryWeeklyBudgetsByWeekStart = {};
      categoryCustomBudgetsByKey = {};
      customBudgetRangesByKey = {};
    }
    activeBudgetPeriodType = BudgetPeriodType.monthly;
    activeBudgetPeriodKey = budgetYearMonthKey(DateTime.now());
  }

  String budgetYearMonthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  /// Weekly period key uses the exact user-selected start date (not normalized).
  String budgetWeekStartKey(DateTime date) => _dateKey(date);

  BudgetPeriodType get resolvedActiveBudgetPeriodType => activeBudgetPeriodType;

  String get resolvedActiveBudgetPeriodKey {
    final key = activeBudgetPeriodKey?.trim();
    if (key != null && key.isNotEmpty) return key;
    return switch (resolvedActiveBudgetPeriodType) {
      BudgetPeriodType.monthly => budgetYearMonthKey(DateTime.now()),
      BudgetPeriodType.weekly => budgetWeekStartKey(DateTime.now()),
      BudgetPeriodType.custom => '',
    };
  }

  void setActivePeriod(BudgetPeriodType type, String key) {
    activeBudgetPeriodType = type;
    activeBudgetPeriodKey = key;
  }

  List<String> defaultBudgetYearMonths({DateTime? start}) {
    final base = start ?? DateTime.now();
    final out = <String>[];
    for (var i = 0; i < 12; i++) {
      final d = DateTime(base.year, base.month + i, 1);
      out.add(budgetYearMonthKey(d));
    }
    return out;
  }

  List<String> defaultBudgetWeeks({DateTime? start}) {
    final seed = start ?? DateTime.now();
    final base = DateTime(seed.year, seed.month, seed.day);
    final out = <String>[];
    for (var i = 0; i < 12; i++) {
      out.add(_dateKey(base.add(Duration(days: i * 7))));
    }
    return out;
  }

  List<String> budgetMonthsForPicker({DateTime? start}) {
    final defaults = defaultBudgetYearMonths(start: start);
    final extras = categoryMonthlyBudgetsByYearMonth.keys
        .where((k) => !defaults.contains(k))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return [...defaults, ...extras];
  }

  List<String> budgetWeeksForPicker({DateTime? start}) {
    final defaults = defaultBudgetWeeks(start: start);
    final extras = categoryWeeklyBudgetsByWeekStart.keys
        .where((k) => !defaults.contains(k))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return [...defaults, ...extras];
  }

  List<String> customBudgetKeysForPicker() {
    final keys = customBudgetRangesByKey.keys.toList();
    keys.sort((a, b) {
      final ra = customBudgetRangesByKey[a];
      final rb = customBudgetRangesByKey[b];
      if (ra == null && rb == null) return a.compareTo(b);
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.start.compareTo(ra.start);
    });
    return keys;
  }

  String customBudgetKeyForRange(DateTime start, DateTime end) {
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    final lo = a.isBefore(b) ? a : b;
    final hi = a.isBefore(b) ? b : a;
    return '${_dateKey(lo)}_${_dateKey(hi)}';
  }

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) {
    final key = customBudgetKeyForRange(start, end);
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    final lo = a.isBefore(b) ? a : b;
    final hi = a.isBefore(b) ? b : a;
    customBudgetRangesByKey = {
      ...customBudgetRangesByKey,
      key: BudgetPeriodRange(start: lo, end: hi),
    };
    return key;
  }

  Map<String, double> monthlyBudgetsForYearMonth(String yearMonth) {
    return Map<String, double>.from(
      categoryMonthlyBudgetsByYearMonth[yearMonth] ?? const {},
    );
  }

  Map<String, double> budgetsForPeriod({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    final raw = switch (periodType) {
      BudgetPeriodType.monthly =>
        categoryMonthlyBudgetsByYearMonth[periodKey] ?? const {},
      BudgetPeriodType.weekly =>
        categoryWeeklyBudgetsByWeekStart[periodKey] ?? const {},
      BudgetPeriodType.custom => categoryCustomBudgetsByKey[periodKey] ?? const {},
    };
    return Map<String, double>.from(raw);
  }

  double? budgetForDisplayLabel({
    required String displayLabel,
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return budgetsForPeriod(periodType: periodType, periodKey: periodKey)[
      budgetDisplayKey(displayLabel)
    ];
  }

  BudgetPeriodRange? budgetPeriodRangeFor({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return switch (periodType) {
      BudgetPeriodType.monthly => _monthRangeFromKey(periodKey),
      BudgetPeriodType.weekly => _weekRangeFromKey(periodKey),
      BudgetPeriodType.custom => customBudgetRangesByKey[periodKey],
    };
  }

  String budgetPeriodLabel({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    final range = budgetPeriodRangeFor(
      periodType: periodType,
      periodKey: periodKey,
    );
    if (range == null) return periodKey;
    return switch (periodType) {
      BudgetPeriodType.monthly => formatYearMonthLabel(budgetYearMonthKey(range.start)),
      BudgetPeriodType.weekly =>
        '${formatShortDate(range.start)} – ${formatShortDate(range.end)}',
      BudgetPeriodType.custom =>
        '${formatShortDate(range.start)} – ${formatShortDate(range.end)}',
    };
  }

  BudgetPeriodRange? _monthRangeFromKey(String yearMonth) {
    final parts = yearMonth.split('-');
    final y = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final m = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (y == null || m == null || m < 1 || m > 12) return null;
    final start = DateTime(y, m, 1);
    final end = DateTime(y, m + 1, 0);
    return BudgetPeriodRange(start: start, end: end);
  }

  /// Calendar month range from `YYYY-MM` (never null for valid keys).
  BudgetPeriodRange monthRangeFromYearMonthKey(String yearMonth) =>
      _monthRangeFromKey(yearMonth)!;

  BudgetPeriodRange? _weekRangeFromKey(String weekStartKey) {
    final start = _parseDateKey(weekStartKey);
    if (start == null) return null;
    final end = start.add(const Duration(days: 6));
    return BudgetPeriodRange(start: start, end: end);
  }

  String _dateKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDateKey(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  /// Applies visible-row budget edits for one period (persist-then-commit).
  ///
  /// [draftByNormalizedDisplayKey] keys must already be [budgetDisplayKey] outputs.
  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    final nextByMonth = <String, Map<String, double>>{
      for (final e in categoryMonthlyBudgetsByYearMonth.entries)
        e.key: Map<String, double>.from(e.value),
    };
    final nextByWeek = <String, Map<String, double>>{
      for (final e in categoryWeeklyBudgetsByWeekStart.entries)
        e.key: Map<String, double>.from(e.value),
    };
    final nextByCustom = <String, Map<String, double>>{
      for (final e in categoryCustomBudgetsByKey.entries)
        e.key: Map<String, double>.from(e.value),
    };
    final nextCustomRanges = <String, BudgetPeriodRange>{
      ...customBudgetRangesByKey,
    };

    final target = switch (periodType) {
      BudgetPeriodType.monthly =>
        Map<String, double>.from(nextByMonth[periodKey] ?? const {}),
      BudgetPeriodType.weekly =>
        Map<String, double>.from(nextByWeek[periodKey] ?? const {}),
      BudgetPeriodType.custom =>
        Map<String, double>.from(nextByCustom[periodKey] ?? const {}),
    };
    for (final e in draftByNormalizedDisplayKey.entries) {
      final value = e.value;
      if (value == null || !value.isFinite || value < 0) {
        target.remove(e.key);
      } else {
        target[e.key] = value;
      }
    }

    switch (periodType) {
      case BudgetPeriodType.monthly:
        if (target.isEmpty) {
          nextByMonth.remove(periodKey);
        } else {
          nextByMonth[periodKey] = target;
        }
        break;
      case BudgetPeriodType.weekly:
        if (target.isEmpty) {
          nextByWeek.remove(periodKey);
        } else {
          nextByWeek[periodKey] = target;
        }
        break;
      case BudgetPeriodType.custom:
        if (target.isEmpty) {
          nextByCustom.remove(periodKey);
        } else {
          nextByCustom[periodKey] = target;
        }
        nextCustomRanges[periodKey] ??=
            budgetPeriodRangeFor(
              periodType: BudgetPeriodType.custom,
              periodKey: periodKey,
            ) ??
            BudgetPeriodRange(start: DateTime.now(), end: DateTime.now());
        break;
    }
    try {
      final storageRanges = <String, BudgetStorageRange>{};
      for (final e in nextCustomRanges.entries) {
        storageRanges[e.key] = BudgetStorageRange(
          start: e.value.start,
          end: e.value.end,
        );
      }
      await saveBudgetSnapshot(
        BudgetStorageSnapshot(
          monthly: nextByMonth,
          weekly: nextByWeek,
          custom: nextByCustom,
          customRanges: storageRanges,
        ),
      );
    } on Object {
      return false;
    }
    categoryMonthlyBudgetsByYearMonth = nextByMonth;
    categoryWeeklyBudgetsByWeekStart = nextByWeek;
    categoryCustomBudgetsByKey = nextByCustom;
    customBudgetRangesByKey = nextCustomRanges;
    activeBudgetPeriodType = periodType;
    activeBudgetPeriodKey = periodKey;
    return true;
  }

  Future<bool> commitMonthlyBudgetDraft(
    String yearMonth,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) {
    return commitBudgetDraft(
      BudgetPeriodType.monthly,
      yearMonth,
      draftByNormalizedDisplayKey,
    );
  }
}
