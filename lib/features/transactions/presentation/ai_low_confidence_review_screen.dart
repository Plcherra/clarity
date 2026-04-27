import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/formatting/formatting.dart';
import '../../../core/models/models.dart';
import '../domain/spend_categories.dart';

class AiLowConfidenceReviewScreen extends StatefulWidget {
  const AiLowConfidenceReviewScreen({
    super.key,
    required this.appState,
    this.autoApplyThreshold = 0.90,
  });

  final AppState appState;
  final double autoApplyThreshold;

  @override
  State<AiLowConfidenceReviewScreen> createState() =>
      _AiLowConfidenceReviewScreenState();
}

class _AiLowConfidenceReviewScreenState extends State<AiLowConfidenceReviewScreen> {
  late Map<String, String?> _choice;

  @override
  void initState() {
    super.initState();
    _choice = {};
  }

  List<String> get _allowed => widget.appState.allowedCategoryPickerLabels;

  List<Transaction> get _items {
    final unc = widget.appState.uncategorizedImportedRowsGlobal();
    final out = <Transaction>[];
    for (final t in unc) {
      final k = transactionCategoryKey(t);
      final already = widget.appState.transactionCategoryAssignments[k]?.trim();
      if (already != null && already.isNotEmpty) continue;
      final s = widget.appState.aiCategorySuggestions[k];
      if (s == null) continue;
      final cat = s.suggestedCanonical?.trim();
      if (cat == null || cat.isEmpty) continue;
      if (!_allowed.contains(cat)) continue;
      if (s.confidence >= widget.autoApplyThreshold) continue;
      out.add(t);
      _choice.putIfAbsent(k, () => cat);
    }
    return out;
  }

  void _save() {
    final toSave = <String, String>{};
    for (final e in _choice.entries) {
      final k = e.key.trim();
      final v = e.value?.trim();
      if (k.isEmpty) continue;
      if (v == null || v.isEmpty) continue;
      toSave[k] = v;
    }
    if (toSave.isEmpty) return;
    final backfillBatch =
        widget.appState.applyCategoriesWithMerchantLearning(toSave);
    if (!mounted) return;
    final snack = ScaffoldMessenger.of(context);
    snack.clearSnackBars();
    snack.showSnackBar(
      SnackBar(
        content: Text(
          'Saved ${toSave.length} categor${toSave.length == 1 ? 'y' : 'ies'}. '
          'Applied to similar merchants too.',
        ),
        action: backfillBatch.isEmpty
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await widget.appState.undoCategoryApplyBatch(backfillBatch);
                },
              ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI review'),
        actions: [
          IconButton(
            tooltip: 'Undo last AI auto-apply',
            onPressed: () async {
              final undone = await widget.appState.undoLastAiAutoApply();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    undone == 0
                        ? 'Nothing to undo.'
                        : 'Undid $undone AI categor${undone == 1 ? 'y' : 'ies'}.',
                  ),
                ),
              );
              setState(() {});
            },
            icon: Icon(
              Icons.undo_rounded,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'No low-confidence suggestions to review right now.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = items[i];
                final k = transactionCategoryKey(t);
                final s = widget.appState.aiCategorySuggestions[k]!;
                final confPct = (s.confidence * 100).round();
                final selected = _choice[k];
                return Material(
                  color: cs.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatShortDate(t.date)} · ${formatMoney(t.amount)} · $confPct% confident',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButton<String?>(
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(12),
                          value: _validDropdownValue(selected),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('— Leave uncategorized —'),
                            ),
                            ..._allowed.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c,
                                child: Text(c),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _choice[k] = v),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save'),
            ),
    );
  }

  String? _validDropdownValue(String? selected) {
    if (selected == null) return null;
    for (final a in _allowed) {
      if (a == selected) return selected;
    }
    return null;
  }
}

