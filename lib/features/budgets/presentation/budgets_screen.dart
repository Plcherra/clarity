import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../dashboard_snapshot.dart';
import '../../../core/formatting/formatting.dart';
import '../../../core/storage/budgets/budget_keys.dart';
import '../../transactions/domain/spend_categories.dart';

String _formatBudgetSeed(double v) {
  if (!v.isFinite || v < 0) return '';
  final r = v.round();
  if ((v - r).abs() < 1e-9) return r.toString();
  var s = v.toString();
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

class _BudgetRow {
  const _BudgetRow({required this.canonical, required this.displayLabel});

  final String canonical;
  final String displayLabel;
}

/// Monthly budgets per category (picker list). Hidden categories are omitted here;
/// their persisted amounts remain until edited elsewhere (Rule A).
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  BudgetPeriodType _selectedType = BudgetPeriodType.monthly;
  String _selectedPeriodKey = '';
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.appState.resolvedActiveBudgetPeriodType;
    _selectedPeriodKey = widget.appState.resolvedActiveBudgetPeriodKey;
    if (_selectedType == BudgetPeriodType.custom &&
        _selectedPeriodKey.trim().isNotEmpty) {
      final range = widget.appState.budgetPeriodRangeFor(
        periodType: BudgetPeriodType.custom,
        periodKey: _selectedPeriodKey,
      );
      if (range != null) {
        _customStart = range.start;
        _customEnd = range.end;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  List<_BudgetRow> _sortedRows(AppState s) {
    final canonicals = categoryPickerCanonicals(
      customCategories: s.customCategories,
      hiddenLower: s.categoriesHiddenFromPicker,
    );
    final rows = <_BudgetRow>[];
    for (final c in canonicals) {
      final display = applyCategoryDisplayRenames(c, s.categoryDisplayRenames);
      rows.add(_BudgetRow(canonical: c, displayLabel: display));
    }
    rows.sort(
      (a, b) =>
          a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase()),
    );
    return rows;
  }

  void _ensureControllers(Iterable<String> canonicals) {
    final set = canonicals.toSet();
    for (final k in set) {
      _controllers.putIfAbsent(k, TextEditingController.new);
      _focusNodes.putIfAbsent(k, FocusNode.new);
    }
  }

  void _schedulePruneOrphans(Set<String> keep) {
    final orphan = _controllers.keys.where((k) => !keep.contains(k)).toList();
    if (orphan.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final k in orphan) {
        _controllers.remove(k)?.dispose();
        _focusNodes.remove(k)?.dispose();
      }
    });
  }

  void _syncControllersFromState(
    List<_BudgetRow> rows,
    BudgetPeriodType periodType,
    String periodKey,
  ) {
    for (final row in rows) {
      final focus = _focusNodes[row.canonical];
      final controller = _controllers[row.canonical];
      if (focus == null || controller == null) continue;
      if (focus.hasFocus) continue;
      final b = widget.appState.budgetForDisplayLabel(
        displayLabel: row.displayLabel,
        periodType: periodType,
        periodKey: periodKey,
      );
      final nextText = b == null ? '' : _formatBudgetSeed(b);
      if (controller.text != nextText) {
        controller.text = nextText;
      }
    }
  }

  List<String> _periodKeys(BudgetPeriodType type) {
    return switch (type) {
      BudgetPeriodType.monthly => widget.appState.budgetMonthsForPicker(),
      BudgetPeriodType.weekly => widget.appState.budgetWeeksForPicker(),
      BudgetPeriodType.custom => widget.appState.customBudgetKeysForPicker(),
    };
  }

  String _periodDisplayLabel(BudgetPeriodType type, String key) {
    if (type == BudgetPeriodType.monthly) return formatYearMonthLabel(key);
    return widget.appState.budgetPeriodLabel(periodType: type, periodKey: key);
  }

  String _monthName(int m) {
    const months = [
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
    if (m < 1 || m > 12) return '';
    return months[m - 1];
  }

  DateTime? _parseYearMonthKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return null;
    return DateTime(y, m, 1);
  }

  String _yearMonthKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  }

  Future<String?> _openMonthYearPicker(String initialKey) async {
    final initial = _parseYearMonthKey(initialKey) ?? DateTime.now();
    var selected = initial;
    var shownYear = initial.year;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              title: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        setModalState(() => shownYear = shownYear - 1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '$shownYear',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setModalState(() => shownYear = shownYear + 1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              content: SizedBox(
                width: 300,
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.2,
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
                        Navigator.of(context).pop(_yearMonthKey(monthDate));
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline.withValues(
                                    alpha: 0.25,
                                  ),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                          color: isSelected
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.10)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _monthName(month).substring(0, 3),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight:
                                    isSelected ? FontWeight.w700 : FontWeight.w500,
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

  DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  String _weeklyRangeLabel(String key) {
    final range = widget.appState.budgetPeriodRangeFor(
      periodType: BudgetPeriodType.weekly,
      periodKey: key,
    );
    if (range == null) return key;
    return '${formatShortDate(range.start)} – ${formatShortDate(range.end)}';
  }

  String _formatLongDate(DateTime date) {
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  void _activatePeriod(BudgetPeriodType type, String key) {
    if (key.trim().isEmpty) return;
    widget.appState.setActiveBudgetPeriod(type: type, key: key);
  }

  void _onPeriodTypeChanged(BudgetPeriodType type) {
    String nextKey = '';
    if (type == BudgetPeriodType.custom) {
      if (_customStart != null && _customEnd != null) {
        nextKey = widget.appState.ensureCustomBudgetPeriod(
          _customStart!,
          _customEnd!,
        );
      } else {
        final customKeys = _periodKeys(BudgetPeriodType.custom);
        if (customKeys.isNotEmpty) {
          nextKey = customKeys.first;
          final range = widget.appState.budgetPeriodRangeFor(
            periodType: BudgetPeriodType.custom,
            periodKey: nextKey,
          );
          if (range != null) {
            _customStart = range.start;
            _customEnd = range.end;
          }
        }
      }
    } else if (type == BudgetPeriodType.weekly) {
      final parsedCurrent = _parseDateKey(_selectedPeriodKey);
      nextKey = widget.appState.budgetWeekStartKey(parsedCurrent ?? DateTime.now());
    } else {
      final keys = _periodKeys(type);
      nextKey = keys.isNotEmpty ? keys.first : '';
    }
    setState(() {
      _selectedType = type;
      _selectedPeriodKey = nextKey;
    });
    _activatePeriod(type, nextKey);
  }

  Future<void> _save(
    List<_BudgetRow> rows,
    BudgetPeriodType periodType,
    String periodKey,
  ) async {
    if (periodKey.trim().isEmpty) return;
    final draft = <String, double?>{};
    for (final row in rows) {
      final key = budgetDisplayKey(row.displayLabel);
      final raw = _controllers[row.canonical]?.text.trim() ?? '';
      if (raw.isEmpty) {
        draft[key] = null;
        continue;
      }
      final parsed = double.tryParse(raw.replaceAll(',', ''));
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        draft[key] = null;
      } else {
        draft[key] = parsed;
      }
    }
    final ok = await widget.appState.commitBudgetDraft(periodType, periodKey, draft);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save budgets. Try again.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Budgets saved for ${_periodDisplayLabel(periodType, periodKey)}',
        ),
      ),
    );
  }

  Future<void> _pickCustomDate({required bool start}) async {
    final initial =
        (start ? _customStart : _customEnd) ??
        _customStart ??
        _customEnd ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _customStart = DateTime(picked.year, picked.month, picked.day);
      } else {
        _customEnd = DateTime(picked.year, picked.month, picked.day);
      }
      if (_customStart != null && _customEnd != null) {
        _selectedPeriodKey = widget.appState.ensureCustomBudgetPeriod(
          _customStart!,
          _customEnd!,
        );
      }
    });
    if (_customStart != null && _customEnd != null) {
      _activatePeriod(BudgetPeriodType.custom, _selectedPeriodKey);
    }
  }

  Future<void> _pickWeeklyStartDate() async {
    final initial = _parseDateKey(_selectedPeriodKey) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: initial,
    );
    if (picked == null) return;
    final key = widget.appState.budgetWeekStartKey(picked);
    setState(() => _selectedPeriodKey = key);
    _activatePeriod(BudgetPeriodType.weekly, key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final keys = _periodKeys(_selectedType);
        if (_selectedType == BudgetPeriodType.weekly) {
          if (_selectedPeriodKey.trim().isEmpty) {
            _selectedPeriodKey = widget.appState.budgetWeekStartKey(DateTime.now());
          }
        } else if (_selectedType == BudgetPeriodType.monthly) {
          if (_selectedPeriodKey.trim().isEmpty) {
            _selectedPeriodKey = keys.isNotEmpty
                ? keys.first
                : widget.appState.activeBudgetYearMonth;
          }
        } else {
          if (_selectedPeriodKey.trim().isEmpty && keys.isNotEmpty) {
            _selectedPeriodKey = keys.first;
          }
          if (_selectedPeriodKey.trim().isNotEmpty &&
              !keys.contains(_selectedPeriodKey)) {
            _selectedPeriodKey = keys.isNotEmpty ? keys.first : '';
          }
        }

        final hasSelectedPeriod = _selectedPeriodKey.trim().isNotEmpty;

        final rows = _sortedRows(widget.appState);
        final keep = rows.map((r) => r.canonical).toSet();
        _ensureControllers(keep);
        _schedulePruneOrphans(keep);
        if (hasSelectedPeriod) {
          _syncControllersFromState(rows, _selectedType, _selectedPeriodKey);
        }

        final selectedRange = hasSelectedPeriod
            ? widget.appState.budgetPeriodRangeFor(
                periodType: _selectedType,
                periodKey: _selectedPeriodKey,
              )
            : null;
        final spentByDisplay = selectedRange == null
            ? const <String, double>{}
            : widget.appState.spentByDisplayCategoryForScopeInRange(
                const GlobalDashboardScope(),
                start: selectedRange.start,
                end: selectedRange.end,
              );
        final performance = hasSelectedPeriod
            ? widget.appState.budgetPerformanceForScope(
                const GlobalDashboardScope(),
                periodType: _selectedType,
                periodKey: _selectedPeriodKey,
              )
            : BudgetPerformanceSnapshot(
                periodType: _selectedType,
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

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text('Budgets'),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFFF3F1ED), cs.surface],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      children: [
                        Text(
                          'Budget period',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.8,
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cs.outline.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SegmentedButton<BudgetPeriodType>(
                                segments: const [
                                  ButtonSegment<BudgetPeriodType>(
                                    value: BudgetPeriodType.monthly,
                                    label: Text('Monthly'),
                                  ),
                                  ButtonSegment<BudgetPeriodType>(
                                    value: BudgetPeriodType.weekly,
                                    label: Text('Weekly'),
                                  ),
                                  ButtonSegment<BudgetPeriodType>(
                                    value: BudgetPeriodType.custom,
                                    label: Text('Custom'),
                                  ),
                                ],
                                selected: {_selectedType},
                                showSelectedIcon: false,
                                onSelectionChanged: (selection) {
                                  if (selection.isEmpty) return;
                                  _onPeriodTypeChanged(selection.first);
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                switch (_selectedType) {
                                  BudgetPeriodType.monthly => 'Select month',
                                  BudgetPeriodType.weekly => 'Select week',
                                  BudgetPeriodType.custom => 'Select date range',
                                },
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.58),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_selectedType == BudgetPeriodType.monthly)
                                keys.isEmpty
                                    ? Text(
                                        'No months available.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withValues(alpha: 0.58),
                                        ),
                                      )
                                    : SizedBox(
                                        height: 44,
                                        child: OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.calendar_month_rounded,
                                            size: 18,
                                          ),
                                          label: Text(
                                            _selectedPeriodKey.trim().isEmpty
                                                ? 'Select month'
                                                : formatYearMonthLabel(
                                                    _selectedPeriodKey,
                                                  ),
                                          ),
                                          onPressed: () async {
                                            final picked = await _openMonthYearPicker(
                                              _selectedPeriodKey,
                                            );
                                            if (!mounted || picked == null) return;
                                            setState(() => _selectedPeriodKey = picked);
                                            _activatePeriod(
                                              BudgetPeriodType.monthly,
                                              picked,
                                            );
                                          },
                                        ),
                                      ),
                              if (_selectedType == BudgetPeriodType.weekly)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: 44,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.date_range_rounded,
                                          size: 18,
                                        ),
                                        onPressed: _pickWeeklyStartDate,
                                        label: Text(
                                          _parseDateKey(_selectedPeriodKey) == null
                                              ? 'Week starts'
                                              : 'Week starts ${_formatLongDate(_parseDateKey(_selectedPeriodKey)!)}',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Selected range: ${_weeklyRangeLabel(_selectedPeriodKey)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withValues(alpha: 0.58),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              if (_selectedType == BudgetPeriodType.custom)
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 44,
                                        child: OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.calendar_today_rounded,
                                            size: 16,
                                          ),
                                          onPressed: () =>
                                              _pickCustomDate(start: true),
                                          label: Text(
                                            _customStart == null
                                                ? 'Start Date'
                                                : '${_monthName(_customStart!.month)} ${_customStart!.day}, ${_customStart!.year}',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 44,
                                        child: OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.event_rounded,
                                            size: 16,
                                          ),
                                          onPressed: () =>
                                              _pickCustomDate(start: false),
                                          label: Text(
                                            _customEnd == null
                                                ? 'End Date'
                                                : '${_monthName(_customEnd!.month)} ${_customEnd!.day}, ${_customEnd!.year}',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 10),
                              Text(
                                switch (_selectedType) {
                                  BudgetPeriodType.monthly =>
                                    'Monthly budgets for each category.',
                                  BudgetPeriodType.weekly =>
                                    'Weekly budgets for each category.',
                                  BudgetPeriodType.custom =>
                                    'Custom range budgets for each category.',
                                },
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.58),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total budgeted ${formatMoney(performance.totalBudgeted)}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total spent ${formatMoney(performance.totalSpent)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (hasSelectedPeriod) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Period: ${_periodDisplayLabel(_selectedType, _selectedPeriodKey)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.58),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                totalOver > 0
                                    ? 'Overspent ${formatMoney(totalOver)}'
                                    : 'Remaining ${formatMoney(totalRemaining)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: totalOver > 0
                                      ? const Color(0xFFC41E3A)
                                      : const Color(0xFF1B7A4C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${performance.onTrackCategoryCount}/${performance.budgetedCategoryCount} categories on track',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.58),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: rows.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'No categories yet.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: rows.length,
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    color: cs.outline.withValues(alpha: 0.12),
                                  ),
                                  itemBuilder: (context, i) {
                                    final row = rows[i];
                                    final spent =
                                        spentByDisplay[row.displayLabel] ?? 0.0;
                                    final budget = hasSelectedPeriod
                                        ? widget.appState.budgetForDisplayLabel(
                                            displayLabel: row.displayLabel,
                                            periodType: _selectedType,
                                            periodKey: _selectedPeriodKey,
                                          )
                                        : null;
                                    final overspent =
                                        budget != null && spent > budget;
                                    final remaining = budget == null
                                        ? null
                                        : budget - spent;
                                    final indicatorColor = budget == null
                                        ? cs.onSurface.withValues(alpha: 0.35)
                                        : overspent
                                            ? const Color(0xFFC41E3A)
                                            : const Color(0xFF1B7A4C);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                  color: indicatorColor,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  row.displayLabel,
                                                  style: theme
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                flex: 2,
                                                child: TextField(
                                                  controller: _controllers[
                                                      row.canonical],
                                                  focusNode: _focusNodes[
                                                      row.canonical],
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                        signed: false,
                                                      ),
                                                  textAlign: TextAlign.end,
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    hintText: '—',
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    prefixText: r'$ ',
                                                    prefixStyle: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: cs.onSurface
                                                              .withValues(
                                                                alpha: 0.45,
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            budget == null
                                                ? 'Spent ${formatMoney(spent)} · No budget set'
                                                : overspent
                                                    ? 'Spent ${formatMoney(spent)} · Overspent ${formatMoney(-remaining!)}'
                                                    : 'Spent ${formatMoney(spent)} · Remaining ${formatMoney(remaining!)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: overspent
                                                      ? const Color(0xFFC41E3A)
                                                      : cs.onSurface.withValues(
                                                          alpha: 0.58,
                                                        ),
                                                ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: FilledButton(
                      onPressed: rows.isEmpty || !hasSelectedPeriod
                          ? null
                          : () => _save(rows, _selectedType, _selectedPeriodKey),
                      child: const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

