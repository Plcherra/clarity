import 'package:flutter/material.dart';

import '../app_state.dart';
import '../budget_keys.dart';
import '../spend_categories.dart';

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
      (a, b) => a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase()),
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

  void _syncControllersFromState(List<_BudgetRow> rows) {
    for (final row in rows) {
      final focus = _focusNodes[row.canonical];
      final controller = _controllers[row.canonical];
      if (focus == null || controller == null) continue;
      if (focus.hasFocus) continue;
      final b = widget.appState.monthlyBudgetForDisplayLabel(row.displayLabel);
      final nextText = b == null ? '' : _formatBudgetSeed(b);
      if (controller.text != nextText) {
        controller.text = nextText;
      }
    }
  }

  Future<void> _save(List<_BudgetRow> rows) async {
    // Visible-row edits merge into the full stored map in [AppState.commitMonthlyBudgetDraft];
    // do not rebuild from visible rows only.
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
    final ok = await widget.appState.commitMonthlyBudgetDraft(draft);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save budgets. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final rows = _sortedRows(widget.appState);
        final keep = rows.map((r) => r.canonical).toSet();
        _ensureControllers(keep);
        _schedulePruneOrphans(keep);
        _syncControllersFromState(rows);

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
                          'Monthly amount per category',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.8,
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w500,
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
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: rows.length,
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    color: cs.outline.withValues(alpha: 0.12),
                                  ),
                                  itemBuilder: (context, i) {
                                    final row = rows[i];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              row.displayLabel,
                                              style: theme.textTheme.bodyLarge?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller: _controllers[row.canonical],
                                              focusNode: _focusNodes[row.canonical],
                                              keyboardType: const TextInputType.numberWithOptions(
                                                decimal: true,
                                                signed: false,
                                              ),
                                              textAlign: TextAlign.end,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '—',
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                prefixText: r'$ ',
                                                prefixStyle: theme.textTheme.bodyMedium?.copyWith(
                                                  color: cs.onSurface.withValues(alpha: 0.45),
                                                ),
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
                      onPressed: rows.isEmpty ? null : () => _save(rows),
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
