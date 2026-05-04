import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../../../core/formatting/formatting.dart';
import '../../../core/models/models.dart';
import '../data/ai_categorization_service.dart';
import '../domain/spend_categories.dart';

class AiLowConfidenceReviewScreen extends StatefulWidget {
  const AiLowConfidenceReviewScreen({
    super.key,
    required this.controller,
    this.autoApplyThreshold = 0.90,
  });

  final TransactionUiController controller;
  final double autoApplyThreshold;

  @override
  State<AiLowConfidenceReviewScreen> createState() =>
      _AiLowConfidenceReviewScreenState();
}

class _AiLowConfidenceReviewScreenState
    extends State<AiLowConfidenceReviewScreen> {
  late final AICategorizationService _service;
  late final _AiLowConfidenceReviewDataNotifier _dataNotifier;
  late Map<String, String?> _choice;

  @override
  void initState() {
    super.initState();
    _service = AICategorizationService();
    _dataNotifier = _AiLowConfidenceReviewDataNotifier();
    _choice = {};
    widget.controller.addListener(_handleControllerChanged);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant AiLowConfidenceReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.autoApplyThreshold != widget.autoApplyThreshold) {
      _loadData();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _service.close();
    _dataNotifier.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    _loadData();
  }

  List<String> get _allowed => widget.controller.allowedCategoryPickerLabels;

  Future<void> _loadData() async {
    _dataNotifier.setLoading();
    try {
      final items = await _loadItems();
      if (!mounted) return;
      _dataNotifier.setData(items);
    } on Object catch (error) {
      if (!mounted) return;
      _dataNotifier.setError(error);
    }
  }

  Future<List<Transaction>> _loadItems() async {
    final unc = await widget.controller.uncategorizedImportedRowsGlobal();
    if (unc.isEmpty) return const [];
    final suggestions = await _service.suggestCategories(
      transactions: unc,
      allowedCategoryIds: _allowed,
    );
    final out = <Transaction>[];
    for (final t in unc) {
      final k = transactionCategoryKey(t);
      final already = widget.controller.transactionCategoryAssignments[k]
          ?.trim();
      if (already != null && already.isNotEmpty) continue;
      final cat = suggestions[k]?.trim();
      if (cat == null || cat.isEmpty) continue;
      if (!_allowed.contains(cat)) continue;
      out.add(t);
      _choice.putIfAbsent(k, () => cat);
    }
    return out;
  }

  Future<void> _save() async {
    final toSave = <String, String>{};
    for (final e in _choice.entries) {
      final k = e.key.trim();
      final v = e.value?.trim();
      if (k.isEmpty) continue;
      if (v == null || v.isEmpty) continue;
      toSave[k] = v;
    }
    if (toSave.isEmpty) return;
    final transactions = _dataNotifier.data ?? const <Transaction>[];
    var saved = 0;
    for (final transaction in transactions) {
      final key = transactionCategoryKey(transaction);
      final category = toSave[key];
      if (category == null || category.trim().isEmpty) continue;
      await widget.controller.setCategoryOverride(transaction, category);
      saved += 1;
    }
    if (!mounted) return;
    final snack = ScaffoldMessenger.of(context);
    snack.clearSnackBars();
    snack.showSnackBar(
      SnackBar(
        content: Text(
          saved == 1 ? 'Saved 1 category.' : 'Saved $saved categories.',
        ),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI review')),
      body: ListenableBuilder(
        listenable: _dataNotifier,
        builder: (context, _) {
          final items = _dataNotifier.data;
          if (items == null) {
            if (_dataNotifier.error != null) {
              return const Center(child: Text('Could not load suggestions.'));
            }
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return Center(
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
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = items[i];
              final k = transactionCategoryKey(t);
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
                        '${formatShortDate(t.date)} · ${formatMoney(t.amount)}',
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
          );
        },
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _dataNotifier,
        builder: (context, _) {
          final items = _dataNotifier.data;
          if (items == null || items.isEmpty) return const SizedBox();
          return FloatingActionButton.extended(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save'),
          );
        },
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

class _AiLowConfidenceReviewDataNotifier extends ChangeNotifier {
  List<Transaction>? _data;
  Object? _error;
  var _loading = false;

  List<Transaction>? get data => _data;
  Object? get error => _error;
  bool get loading => _loading;

  void setLoading() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void setData(List<Transaction> data) {
    _data = data;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  void setError(Object error) {
    _error = error;
    _loading = false;
    notifyListeners();
  }
}
