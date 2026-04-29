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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeek(DateTime d) {
    final x = _dateOnly(d);
    return x.subtract(Duration(days: x.weekday - DateTime.monday));
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

  String _weeklyPrimaryLabel(String key) {
    final range = widget.appState.budgetPeriodRangeFor(
      periodType: BudgetPeriodType.weekly,
      periodKey: key,
    );
    if (range == null) return _periodDisplayLabel(BudgetPeriodType.weekly, key);
    final thisWeekStart = _startOfWeek(DateTime.now());
    final start = _dateOnly(range.start);
    final diff = start.difference(thisWeekStart).inDays;
    if (diff == 0) return 'This week';
    if (diff == 7) return 'Next week';
    if (diff == -7) return 'Last week';
    return 'Week of ${_monthName(start.month)} ${start.day}';
  }

  String _weeklySecondaryLabel(String key) {
    final range = widget.appState.budgetPeriodRangeFor(
      periodType: BudgetPeriodType.weekly,
      periodKey: key,
    );
    if (range == null) return key;
    return '${formatShortDate(range.start)} – ${formatShortDate(range.end)}';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final keys = _periodKeys(_selectedType);
        if (_selectedPeriodKey.trim().isEmpty && keys.isNotEmpty) {
          _selectedPeriodKey = keys.first;
        }
        if (_selectedPeriodKey.trim().isNotEmpty &&
            !keys.contains(_selectedPeriodKey)) {
          _selectedPeriodKey = keys.isNotEmpty ? keys.first : '';
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
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            for (final key in keys)
                                              Padding(
                                                padding: const EdgeInsets.only(right: 8),
                                                child: ChoiceChip(
                                                  showCheckmark: false,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                  label: Text(
                                                    formatYearMonthLabel(key),
                                                  ),
                                                  selected:
                                                      _selectedPeriodKey == key,
                                                  onSelected: (_) {
                                                    setState(
                                                      () => _selectedPeriodKey = key,
                                                    );
                                                    _activatePeriod(
                                                      BudgetPeriodType.monthly,
                                                      key,
                                                    );
                                                  },
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                              if (_selectedType == BudgetPeriodType.weekly)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: cs.outline.withValues(alpha: 0.14),
                                    ),
                                  ),
                                  child: keys.isEmpty
                                      ? Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            'No weekly periods available.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurface.withValues(
                                                    alpha: 0.58,
                                                  ),
                                                ),
                                          ),
                                        )
                                      : Column(
                                          children: [
                                            for (var i = 0; i < keys.length; i++) ...[
                                              if (i > 0)
                                                Divider(
                                                  height: 1,
                                                  color: cs.outline.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                ),
                                              ListTile(
                                                dense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 2,
                                                    ),
                                                title: Text(
                                                  _weeklyPrimaryLabel(keys[i]),
                                                  style: theme.textTheme.bodyMedium
                                                      ?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                ),
                                                subtitle: Text(
                                                  _weeklySecondaryLabel(keys[i]),
                                                ),
                                                trailing: _selectedPeriodKey ==
                                                        keys[i]
                                                    ? const Icon(Icons.check_rounded)
                                                    : null,
                                                onTap: () {
                                                  setState(
                                                    () => _selectedPeriodKey = keys[i],
                                                  );
                                                  _activatePeriod(
                                                    BudgetPeriodType.weekly,
                                                    keys[i],
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
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

