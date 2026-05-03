import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../../../core/formatting/formatting.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../dashboard/domain/dashboard_snapshot.dart';
import '../../transactions/domain/spend_categories.dart';
import '../domain/budget_models.dart';

class BudgetCategoryRow {
  const BudgetCategoryRow({
    required this.canonical,
    required this.displayLabel,
  });

  final String canonical;
  final String displayLabel;
}

class BudgetPeriodChange {
  const BudgetPeriodChange({
    required this.periodKey,
    required this.customStart,
    required this.customEnd,
  });

  final String periodKey;
  final DateTime? customStart;
  final DateTime? customEnd;
}

class BudgetsPresentationMetrics {
  const BudgetsPresentationMetrics({
    required this.spentByDisplay,
    required this.performance,
    required this.totalRemaining,
    required this.totalOver,
  });

  final Map<String, double> spentByDisplay;
  final BudgetPerformanceSnapshot performance;
  final double totalRemaining;
  final double totalOver;
}

class BudgetCategoryListItemData {
  const BudgetCategoryListItemData({
    required this.canonical,
    required this.displayLabel,
    required this.indicatorColor,
    required this.statusText,
    required this.statusColor,
  });

  final String canonical;
  final String displayLabel;
  final Color indicatorColor;
  final String statusText;
  final Color statusColor;
}

class BudgetsViewModel {
  BudgetsViewModel({required this.controller});

  final BudgetUiController controller;
  final ValueNotifier<bool> hasUnsavedChanges = ValueNotifier<bool>(false);

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  BudgetPeriodType initialPeriodType() => BudgetPeriodType.monthly;

  String initialPeriodKey() => yearMonthKey(controller.spendReference);

  ({DateTime? start, DateTime? end}) initialCustomRange({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    if (periodType != BudgetPeriodType.custom || periodKey.trim().isEmpty) {
      return (start: null, end: null);
    }
    final range = _budgetPeriodRangeFor(
      periodType: BudgetPeriodType.custom,
      periodKey: periodKey,
    );
    if (range == null) return (start: null, end: null);
    return (start: range.start, end: range.end);
  }

  List<BudgetCategoryRow> sortedRows() {
    final canonicals = categoryPickerCanonicals(
      customCategories: controller.customCategories,
      hiddenLower: controller.categoriesHiddenFromPicker,
    );
    final rows = <BudgetCategoryRow>[];
    for (final canonical in canonicals) {
      final displayLabel = applyCategoryDisplayRenames(
        canonical,
        controller.categoryDisplayRenames,
      );
      rows.add(
        BudgetCategoryRow(canonical: canonical, displayLabel: displayLabel),
      );
    }
    rows.sort(
      (a, b) =>
          a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase()),
    );
    return rows;
  }

  List<String> periodKeys(BudgetPeriodType type) {
    return switch (type) {
      BudgetPeriodType.monthly => _monthlyKeysForPicker(),
      BudgetPeriodType.weekly => _weeklyKeysForPicker(),
      BudgetPeriodType.custom => const <String>[],
    };
  }

  String normalizeSelectedPeriodKey({
    required BudgetPeriodType periodType,
    required String selectedPeriodKey,
    required List<String> availableKeys,
  }) {
    if (periodType == BudgetPeriodType.weekly) {
      if (selectedPeriodKey.trim().isNotEmpty) return selectedPeriodKey;
      return controller.budgetWeekStartKey(DateTime.now());
    }
    if (periodType == BudgetPeriodType.monthly) {
      if (selectedPeriodKey.trim().isNotEmpty) return selectedPeriodKey;
      return availableKeys.isNotEmpty
          ? availableKeys.first
          : yearMonthKey(controller.spendReference);
    }
    if (selectedPeriodKey.trim().isEmpty && availableKeys.isNotEmpty) {
      return availableKeys.first;
    }
    if (selectedPeriodKey.trim().isNotEmpty &&
        !availableKeys.contains(selectedPeriodKey)) {
      return availableKeys.isNotEmpty ? availableKeys.first : '';
    }
    return selectedPeriodKey;
  }

  String periodDisplayLabel({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    if (periodType == BudgetPeriodType.monthly) {
      return formatYearMonthLabel(periodKey);
    }
    return _budgetPeriodLabel(periodType: periodType, periodKey: periodKey);
  }

  String monthName(int month) {
    if (month < 1 || month > 12) return '';
    return _months[month - 1];
  }

  DateTime? parseYearMonthKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return null;
    return DateTime(year, month, 1);
  }

  String yearMonthKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  DateTime? parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  String weeklyRangeLabel(String key) {
    final range = _budgetPeriodRangeFor(
      periodType: BudgetPeriodType.weekly,
      periodKey: key,
    );
    if (range == null) return key;
    return '${formatShortDate(range.start)} – ${formatShortDate(range.end)}';
  }

  String formatLongDate(DateTime date) {
    return '${monthName(date.month)} ${date.day}, ${date.year}';
  }

  BudgetPeriodChange resolvePeriodTypeChange({
    required BudgetPeriodType nextType,
    required String currentPeriodKey,
    required DateTime? customStart,
    required DateTime? customEnd,
  }) {
    var nextKey = '';
    var nextCustomStart = customStart;
    var nextCustomEnd = customEnd;

    if (nextType == BudgetPeriodType.custom) {
      if (customStart != null && customEnd != null) {
        nextKey = controller.ensureCustomBudgetPeriod(customStart, customEnd);
      } else {
        final customKeys = periodKeys(BudgetPeriodType.custom);
        if (customKeys.isNotEmpty) {
          nextKey = customKeys.first;
          final range = _budgetPeriodRangeFor(
            periodType: BudgetPeriodType.custom,
            periodKey: nextKey,
          );
          if (range != null) {
            nextCustomStart = range.start;
            nextCustomEnd = range.end;
          }
        }
      }
    } else if (nextType == BudgetPeriodType.weekly) {
      final parsedCurrent = parseDateKey(currentPeriodKey);
      nextKey = controller.budgetWeekStartKey(parsedCurrent ?? DateTime.now());
    } else {
      final keys = periodKeys(nextType);
      nextKey = keys.isNotEmpty ? keys.first : '';
    }

    return BudgetPeriodChange(
      periodKey: nextKey,
      customStart: nextCustomStart,
      customEnd: nextCustomEnd,
    );
  }

  Future<BudgetsPresentationMetrics> buildPresentationMetrics({
    required bool hasSelectedPeriod,
    required BudgetPeriodType periodType,
    required String periodKey,
  }) async {
    final selectedRange = hasSelectedPeriod
        ? _budgetPeriodRangeFor(periodType: periodType, periodKey: periodKey)
        : null;
    final spentByDisplay = selectedRange == null
        ? const <String, double>{}
        : await controller.spentByDisplayCategoryForScopeInRange(
            const GlobalDashboardScope(),
            start: selectedRange.start,
            end: selectedRange.end,
          );

    final performance = hasSelectedPeriod
        ? await controller.budgetPerformanceForScope(
            const GlobalDashboardScope(),
            periodType: periodType,
            periodKey: periodKey,
          )
        : BudgetPerformanceSnapshot(
            periodType: periodType,
            periodKey: '',
            periodLabel: '',
            totalBudgeted: 0,
            totalSpent: 0,
            budgetedCategoryCount: 0,
            onTrackCategoryCount: 0,
            totalOverspent: 0,
            topOverspendingCategories: const [],
          );

    final totalRemaining = performance.totalBudgeted - performance.totalSpent;
    final totalOver = totalRemaining < 0 ? -totalRemaining : 0.0;
    return BudgetsPresentationMetrics(
      spentByDisplay: spentByDisplay,
      performance: performance,
      totalRemaining: totalRemaining,
      totalOver: totalOver,
    );
  }

  Future<List<BudgetCategoryListItemData>> buildCategoryListItems({
    required List<BudgetCategoryRow> rows,
    required bool hasSelectedPeriod,
    required BudgetPeriodType periodType,
    required String periodKey,
    required Map<String, double> spentByDisplay,
    required ColorScheme colorScheme,
  }) async {
    final budgets = await _fetchBudgetsForPeriod(periodType, periodKey);
    final items = <BudgetCategoryListItemData>[];
    for (final row in rows) {
      final spent = spentByDisplay[row.displayLabel] ?? 0.0;
      final budget = hasSelectedPeriod
          ? _budgetForDisplayLabel(row.displayLabel, budgets)
          : null;
      final overspent = budget != null && spent > budget;
      final remaining = budget == null ? null : budget - spent;
      final indicatorColor = budget == null
          ? colorScheme.onSurface.withValues(alpha: 0.32)
          : overspent
          ? const Color(0xFFC41E3A)
          : const Color(0xFF1B7A4C);
      final statusText = budget == null
          ? 'Spent ${formatMoney(spent)} · No budget'
          : overspent
          ? 'Spent ${formatMoney(spent)} · Over ${formatMoney(-remaining!)}'
          : 'Spent ${formatMoney(spent)} · Left ${formatMoney(remaining!)}';
      final statusColor = overspent
          ? const Color(0xFFC41E3A)
          : colorScheme.onSurface.withValues(alpha: 0.58);
      items.add(
        BudgetCategoryListItemData(
          canonical: row.canonical,
          displayLabel: row.displayLabel,
          indicatorColor: indicatorColor,
          statusText: statusText,
          statusColor: statusColor,
        ),
      );
    }
    return items;
  }

  Future<void> updateUnsavedChanges({
    required List<BudgetCategoryRow> rows,
    required Map<String, TextEditingController> controllers,
    required BudgetPeriodType periodType,
    required String periodKey,
  }) async {
    hasUnsavedChanges.value = await _computeUnsavedChanges(
      rows: rows,
      controllers: controllers,
      periodType: periodType,
      periodKey: periodKey,
    );
  }

  Future<bool> _computeUnsavedChanges({
    required List<BudgetCategoryRow> rows,
    required Map<String, TextEditingController> controllers,
    required BudgetPeriodType periodType,
    required String periodKey,
  }) async {
    if (periodKey.trim().isEmpty) return false;
    final budgets = await _fetchBudgetsForPeriod(periodType, periodKey);
    for (final row in rows) {
      final raw = controllers[row.canonical]?.text.trim() ?? '';
      final draftValue = _parseBudgetRaw(raw);
      final currentValue = _budgetForDisplayLabel(row.displayLabel, budgets);
      if (!_sameNullableDouble(draftValue, currentValue)) {
        return true;
      }
    }
    return false;
  }

  void clearUnsavedChanges() {
    hasUnsavedChanges.value = false;
  }

  Future<void> syncControllersFromState({
    required List<BudgetCategoryRow> rows,
    required BudgetPeriodType periodType,
    required String periodKey,
    required Map<String, TextEditingController> controllers,
    required Map<String, FocusNode> focusNodes,
  }) async {
    final budgets = await _fetchBudgetsForPeriod(periodType, periodKey);
    for (final row in rows) {
      final focus = focusNodes[row.canonical];
      final controller = controllers[row.canonical];
      if (focus == null || controller == null || focus.hasFocus) continue;
      final budget = _budgetForDisplayLabel(row.displayLabel, budgets);
      final nextText = budget == null ? '' : formatBudgetSeed(budget);
      if (controller.text != nextText) {
        controller.text = nextText;
      }
    }
  }

  void ensureControllers({
    required Iterable<String> canonicalKeys,
    required Map<String, TextEditingController> controllers,
    required Map<String, FocusNode> focusNodes,
  }) {
    final keySet = canonicalKeys.toSet();
    for (final key in keySet) {
      controllers.putIfAbsent(key, TextEditingController.new);
      focusNodes.putIfAbsent(key, FocusNode.new);
    }
  }

  Map<String, double?> buildDraft({
    required List<BudgetCategoryRow> rows,
    required Map<String, TextEditingController> controllers,
  }) {
    final draft = <String, double?>{};
    for (final row in rows) {
      final key = row.displayLabel.trim().toLowerCase();
      final raw = controllers[row.canonical]?.text.trim() ?? '';
      draft[key] = _parseBudgetRaw(raw);
    }
    return draft;
  }

  double? _parseBudgetRaw(String raw) {
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

  bool _sameNullableDouble(double? a, double? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < 1e-9;
  }

  Future<List<BudgetRecord>> _fetchBudgetsForPeriod(
    BudgetPeriodType periodType,
    String periodKey,
  ) async {
    final budgets = await controller.budgetService.fetchBudgets();
    final period = _periodToDatabaseValue(periodType);
    final start = _periodStartDate(periodType, periodKey);
    return budgets.where((budget) {
      if (budget.period != period) return false;
      if (start == null) return true;
      return _sameDay(budget.startDate, start);
    }).toList();
  }

  double? _budgetForDisplayLabel(
    String displayLabel,
    List<BudgetRecord> budgets,
  ) {
    final key = displayLabel.trim().toLowerCase();
    for (final budget in budgets) {
      if (budget.name.trim().toLowerCase() == key) return budget.amount;
    }
    return null;
  }

  BudgetPeriodRange? _budgetPeriodRangeFor({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return switch (periodType) {
      BudgetPeriodType.monthly => _monthlyRange(periodKey),
      BudgetPeriodType.weekly => _weeklyRange(periodKey),
      BudgetPeriodType.custom => _customRange(periodKey),
    };
  }

  BudgetPeriodRange? _monthlyRange(String key) {
    final start = parseYearMonthKey(key);
    if (start == null) return null;
    return BudgetPeriodRange(
      start: start,
      end: DateTime(start.year, start.month + 1, 0),
    );
  }

  BudgetPeriodRange? _weeklyRange(String key) {
    final start = parseDateKey(key);
    if (start == null) return null;
    return BudgetPeriodRange(
      start: start,
      end: start.add(const Duration(days: 6)),
    );
  }

  BudgetPeriodRange? _customRange(String key) {
    final parts = key.split('_');
    if (parts.length != 2) return null;
    final start = parseDateKey(parts[0]);
    final end = parseDateKey(parts[1]);
    if (start == null || end == null) return null;
    return BudgetPeriodRange(start: start, end: end);
  }

  String _budgetPeriodLabel({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    final range = _budgetPeriodRangeFor(
      periodType: periodType,
      periodKey: periodKey,
    );
    if (range == null) return periodKey;
    return '${formatShortDate(range.start)} – ${formatShortDate(range.end)}';
  }

  List<String> _monthlyKeysForPicker() {
    final now = controller.spendReference;
    return List<String>.generate(18, (index) {
      final date = DateTime(now.year, now.month - index);
      return yearMonthKey(date);
    });
  }

  List<String> _weeklyKeysForPicker() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List<String>.generate(12, (index) {
      final date = monday.subtract(Duration(days: index * 7));
      return _dateKey(date);
    });
  }

  DateTime? _periodStartDate(BudgetPeriodType periodType, String periodKey) {
    return switch (periodType) {
      BudgetPeriodType.monthly => parseYearMonthKey(periodKey),
      BudgetPeriodType.weekly => parseDateKey(periodKey),
      BudgetPeriodType.custom => _customRange(periodKey)?.start,
    };
  }

  String _periodToDatabaseValue(BudgetPeriodType periodType) {
    return switch (periodType) {
      BudgetPeriodType.monthly => 'monthly',
      BudgetPeriodType.weekly => 'weekly',
      BudgetPeriodType.custom => 'custom',
    };
  }

  bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void dispose() {
    hasUnsavedChanges.dispose();
  }

  Future<DateTime?> showPremiumDatePicker({
    required BuildContext context,
    required DateTime initialDate,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: initialDate,
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            datePickerTheme: DatePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 2,
              backgroundColor: cs.surface,
              headerBackgroundColor: cs.surfaceContainerHighest,
              headerForegroundColor: cs.onSurface,
              dayStyle: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              dayShape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              yearShape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              todayBorder: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Future<String?> openMonthYearPicker({
    required BuildContext context,
    required String initialKey,
  }) async {
    final initial = parseYearMonthKey(initialKey) ?? DateTime.now();
    var selected = initial;
    var shownYear = initial.year;
    return showDialog<String>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              titlePadding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              title: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setModalState(() => shownYear = shownYear - 1),
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    ),
                    Expanded(
                      child: Text(
                        '$shownYear',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setModalState(() => shownYear = shownYear + 1),
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              content: SizedBox(
                width: 286,
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 7,
                    crossAxisSpacing: 7,
                    childAspectRatio: 2.35,
                  ),
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final monthDate = DateTime(shownYear, month, 1);
                    final isSelected =
                        selected.year == shownYear && selected.month == month;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        selected = monthDate;
                        Navigator.of(context).pop(yearMonthKey(monthDate));
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outline.withValues(alpha: 0.24),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                          color: isSelected
                              ? cs.primary.withValues(alpha: 0.10)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          monthName(month).substring(0, 3),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String formatBudgetSeed(double value) {
  if (!value.isFinite || value < 0) return '';
  final rounded = value.round();
  if ((value - rounded).abs() < 1e-9) return rounded.toString();
  var text = value.toString();
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
