import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../domain/budget_models.dart';
import '../../../core/formatting/formatting.dart';
import 'budget_category_list.dart';
import 'budgets_header.dart';
import 'budgets_viewmodel.dart';

/// Monthly budgets per category (picker list). Hidden categories are omitted here;
/// their persisted amounts remain until edited elsewhere (Rule A).
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

enum _PeriodSwitchChoice { save, discard, cancel }

class _BudgetsScreenState extends State<BudgetsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  late final BudgetsViewModel _viewModel;

  BudgetPeriodType _selectedType = BudgetPeriodType.monthly;
  String _selectedPeriodKey = '';
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _viewModel = BudgetsViewModel(appState: widget.appState);
    _selectedType = _viewModel.initialPeriodType();
    _selectedPeriodKey = _viewModel.initialPeriodKey();
    final customRange = _viewModel.initialCustomRange(
      periodType: _selectedType,
      periodKey: _selectedPeriodKey,
    );
    _customStart = customRange.start;
    _customEnd = customRange.end;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _viewModel.dispose();
    super.dispose();
  }

  void _schedulePruneOrphans(Set<String> keep) {
    final orphan = _controllers.keys.where((k) => !keep.contains(k)).toList();
    if (orphan.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final key in orphan) {
        _controllers.remove(key)?.dispose();
        _focusNodes.remove(key)?.dispose();
      }
    });
  }

  void _onDraftEdited([String _ = '']) {
    _viewModel.updateUnsavedChanges(
      rows: _viewModel.sortedRows(),
      controllers: _controllers,
      periodType: _selectedType,
      periodKey: _selectedPeriodKey,
    );
  }

  void _activatePeriod(BudgetPeriodType type, String key) {
    if (key.trim().isEmpty) return;
    widget.appState.setActiveBudgetPeriod(type: type, key: key);
  }

  Future<bool> _confirmPeriodSwitchIfNeeded() async {
    if (!_viewModel.hasUnsavedChanges.value) return true;

    final choice = await showDialog<_PeriodSwitchChoice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save changes before switching period?'),
          content: const Text(
            'You have unsaved budget changes for this period.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PeriodSwitchChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PeriodSwitchChoice.discard),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PeriodSwitchChoice.save),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (!mounted) return false;

    switch (choice) {
      case _PeriodSwitchChoice.save:
        return _save(_viewModel.sortedRows());
      case _PeriodSwitchChoice.discard:
        _viewModel.clearUnsavedChanges();
        return true;
      case _PeriodSwitchChoice.cancel:
      case null:
        return false;
    }
  }

  Future<void> _onPeriodTypeChanged(BudgetPeriodType type) async {
    if (!await _confirmPeriodSwitchIfNeeded()) return;

    final change = _viewModel.resolvePeriodTypeChange(
      nextType: type,
      currentPeriodKey: _selectedPeriodKey,
      customStart: _customStart,
      customEnd: _customEnd,
    );
    setState(() {
      _selectedType = type;
      _selectedPeriodKey = change.periodKey;
      _customStart = change.customStart;
      _customEnd = change.customEnd;
    });
    _activatePeriod(type, change.periodKey);
  }

  Future<void> _pickMonthly() async {
    final picked = await _viewModel.openMonthYearPicker(
      context: context,
      initialKey: _selectedPeriodKey,
    );
    if (!mounted || picked == null) return;
    if (!await _confirmPeriodSwitchIfNeeded()) return;

    setState(() => _selectedPeriodKey = picked);
    _activatePeriod(BudgetPeriodType.monthly, picked);
  }

  Future<void> _pickWeeklyStartDate() async {
    final initial =
        _viewModel.parseDateKey(_selectedPeriodKey) ?? DateTime.now();
    final picked = await _viewModel.showPremiumDatePicker(
      context: context,
      initialDate: initial,
    );
    if (!mounted || picked == null) return;
    if (!await _confirmPeriodSwitchIfNeeded()) return;

    final key = widget.appState.budgetWeekStartKey(picked);
    setState(() => _selectedPeriodKey = key);
    _activatePeriod(BudgetPeriodType.weekly, key);
  }

  Future<void> _pickCustomDate({required bool start}) async {
    final initial =
        (start ? _customStart : _customEnd) ??
        _customStart ??
        _customEnd ??
        DateTime.now();
    final picked = await _viewModel.showPremiumDatePicker(
      context: context,
      initialDate: initial,
    );
    if (!mounted || picked == null) return;
    if (!await _confirmPeriodSwitchIfNeeded()) return;

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

  Future<bool> _save(List<BudgetCategoryRow> rows) async {
    if (_selectedPeriodKey.trim().isEmpty) return false;
    final draft = _viewModel.buildDraft(rows: rows, controllers: _controllers);
    final ok = await widget.appState.commitBudgetDraft(
      _selectedType,
      _selectedPeriodKey,
      draft,
    );
    if (!mounted) return false;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save budgets. Try again.')),
      );
      return false;
    }
    _viewModel.clearUnsavedChanges();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Budgets saved for ${_viewModel.periodDisplayLabel(periodType: _selectedType, periodKey: _selectedPeriodKey)}',
        ),
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compactButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      side: BorderSide(color: cs.outline.withValues(alpha: 0.16)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.30),
    );

    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final keys = _viewModel.periodKeys(_selectedType);
        _selectedPeriodKey = _viewModel.normalizeSelectedPeriodKey(
          periodType: _selectedType,
          selectedPeriodKey: _selectedPeriodKey,
          availableKeys: keys,
        );
        final hasSelectedPeriod = _selectedPeriodKey.trim().isNotEmpty;
        final rows = _viewModel.sortedRows();
        final keep = rows.map((r) => r.canonical).toSet();

        _viewModel.ensureControllers(
          canonicalKeys: keep,
          controllers: _controllers,
          focusNodes: _focusNodes,
        );
        _schedulePruneOrphans(keep);
        if (hasSelectedPeriod) {
          _viewModel.syncControllersFromState(
            rows: rows,
            periodType: _selectedType,
            periodKey: _selectedPeriodKey,
            controllers: _controllers,
            focusNodes: _focusNodes,
          );
        }
        final weeklyDate = _viewModel.parseDateKey(_selectedPeriodKey);
        final metrics = _viewModel.buildPresentationMetrics(
          hasSelectedPeriod: hasSelectedPeriod,
          periodType: _selectedType,
          periodKey: _selectedPeriodKey,
        );
        final categoryItems = _viewModel.buildCategoryListItems(
          rows: rows,
          hasSelectedPeriod: hasSelectedPeriod,
          periodType: _selectedType,
          periodKey: _selectedPeriodKey,
          spentByDisplay: metrics.spentByDisplay,
          colorScheme: cs,
        );
        final canAttemptSave = rows.isNotEmpty && hasSelectedPeriod;

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            toolbarHeight: 52,
            titleSpacing: 6,
            title: const Text('Budgets'),
            leading: const SizedBox(width: 48),
            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: _viewModel.hasUnsavedChanges,
                builder: (context, hasChanges, _) {
                  final canSave = canAttemptSave && hasChanges;

                  return IconButton(
                    tooltip: 'Save changes',
                    visualDensity: VisualDensity.compact,
                    onPressed: canSave
                        ? () async {
                            await _save(rows);
                          }
                        : null,
                    icon: Icon(
                      Icons.check_rounded,
                      size: 22,
                      color: hasChanges ? cs.primary : Colors.grey,
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BudgetsHeader(
                    selectedType: _selectedType,
                    selectedPeriodKey: _selectedPeriodKey,
                    keys: keys,
                    monthlyLabel: _selectedPeriodKey.trim().isEmpty
                        ? 'Select month'
                        : formatYearMonthLabel(_selectedPeriodKey),
                    weeklyLabel: weeklyDate == null
                        ? 'Pick week start'
                        : _viewModel.formatLongDate(weeklyDate),
                    weeklyRangeLabel: _viewModel.weeklyRangeLabel(
                      _selectedPeriodKey,
                    ),
                    customStartLabel: _customStart == null
                        ? 'Start'
                        : formatShortDate(_customStart!),
                    customEndLabel: _customEnd == null
                        ? 'End'
                        : formatShortDate(_customEnd!),
                    onPeriodTypeChanged: _onPeriodTypeChanged,
                    onPickMonthly: () => _pickMonthly(),
                    onPickWeekly: () => _pickWeeklyStartDate(),
                    onPickCustomStart: () => _pickCustomDate(start: true),
                    onPickCustomEnd: () => _pickCustomDate(start: false),
                    compactButtonStyle: compactButtonStyle,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: cs.outline.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SummaryMetric(
                            label: 'Budgeted',
                            value: formatMoney(
                              metrics.performance.totalBudgeted,
                            ),
                            valueColor: cs.onSurface,
                            alignment: CrossAxisAlignment.start,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: cs.outline.withValues(alpha: 0.10),
                        ),
                        Expanded(
                          child: _SummaryMetric(
                            label: 'Spent',
                            value: formatMoney(metrics.performance.totalSpent),
                            valueColor: cs.onSurface,
                            alignment: CrossAxisAlignment.center,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: cs.outline.withValues(alpha: 0.10),
                        ),
                        Expanded(
                          child: _SummaryMetric(
                            label: metrics.totalOver > 0 ? 'Over' : 'Left',
                            value: metrics.totalOver > 0
                                ? formatMoney(metrics.totalOver)
                                : formatMoney(metrics.totalRemaining),
                            valueColor: metrics.totalOver > 0
                                ? const Color(0xFFC41E3A)
                                : const Color(0xFF1B7A4C),
                            alignment: CrossAxisAlignment.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: BudgetCategoryList(
                      items: categoryItems,
                      controllers: _controllers,
                      focusNodes: _focusNodes,
                      onCategoryValueChanged: _onDraftEdited,
                      onTrackCategoryCount:
                          metrics.performance.onTrackCategoryCount,
                      budgetedCategoryCount:
                          metrics.performance.budgetedCategoryCount,
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

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.alignment,
  });

  final String label;
  final String value;
  final Color valueColor;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.54),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
