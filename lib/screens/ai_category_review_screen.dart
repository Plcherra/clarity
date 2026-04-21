import 'package:flutter/material.dart';

import '../ai_categorization_service.dart';
import '../app_state.dart';
import '../formatting.dart';
import '../models.dart';
import '../spend_categories.dart';

/// Loads AI suggestions then shows review; call after [AppState.loadFromCsv] when needed.
///
/// **Cancel / skip:** pops with [onFinished] and does not persist categories.
class AiCategorizationFlowScreen extends StatefulWidget {
  const AiCategorizationFlowScreen({
    super.key,
    required this.appState,
    required this.accountId,
    required this.onFinished,
  });

  final AppState appState;
  final String accountId;
  final VoidCallback onFinished;

  @override
  State<AiCategorizationFlowScreen> createState() =>
      _AiCategorizationFlowScreenState();
}

enum _FlowPhase { loading, error, review }

class _AiCategorizationFlowScreenState extends State<AiCategorizationFlowScreen> {
  _FlowPhase _phase = _FlowPhase.loading;
  Object? _error;
  Map<String, String?> _aiSuggestions = {};
  late final AICategorizationService _service;
  List<Transaction> _transactions = const [];

  @override
  void initState() {
    super.initState();
    _service = AICategorizationService();
    _runFetch();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _runFetch() async {
    setState(() {
      _phase = _FlowPhase.loading;
      _error = null;
    });
    final unc = widget.appState
        .uncategorizedImportedRowsForAccount(widget.accountId);
    if (unc.isEmpty) {
      if (!mounted) return;
      widget.onFinished();
      return;
    }
    try {
      final allowed = widget.appState.allowedCategoryPickerLabels;
      final map = await _service.suggestCategories(
        transactions: unc,
        allowedCategoryIds: allowed,
      );
      if (!mounted) return;
      setState(() {
        _transactions = unc;
        _aiSuggestions = map;
        _phase = _FlowPhase.review;
      });
    } catch (e, st) {
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _FlowPhase.error;
      });
    }
  }

  void _finish() {
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI categories'),
        actions: [
          if (_phase == _FlowPhase.review)
            IconButton(
              tooltip: 'Close',
              onPressed: _finish,
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
      body: switch (_phase) {
        _FlowPhase.loading => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Fetching suggestions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This may take a moment for larger statements.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _FlowPhase.error => _ErrorBody(
            error: _error,
            onRetry: _runFetch,
            onSkip: _finish,
          ),
        _FlowPhase.review => AiCategoryReviewScreen(
            appState: widget.appState,
            transactions: _transactions,
            initialSuggestions: _aiSuggestions,
            onSkip: _finish,
          ),
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.onRetry,
    required this.onSkip,
  });

  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  String _message() {
    if (error is MissingOpenAiApiKeyException) return error.toString();
    if (error is FormatException) {
      final m = (error as FormatException).message;
      if (m.isNotEmpty) return m;
    }
    return 'Could not reach AI or parse the response. Check your network and API key.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = _message();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 20),
          Text(
            msg,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSkip,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}

/// Review AI picks: per-row dropdown, save batches to [AppState.bulkSetCategoryOverrides].
///
/// Cancel: use [onSkip] without saving (categories stay uncategorized).
class AiCategoryReviewScreen extends StatefulWidget {
  const AiCategoryReviewScreen({
    super.key,
    required this.appState,
    required this.transactions,
    required this.initialSuggestions,
    required this.onSkip,
  });

  final AppState appState;
  final List<Transaction> transactions;
  final Map<String, String?> initialSuggestions;
  final VoidCallback onSkip;

  @override
  State<AiCategoryReviewScreen> createState() => _AiCategoryReviewScreenState();
}

class _AiCategoryReviewScreenState extends State<AiCategoryReviewScreen> {
  late Map<String, String?> _choice;

  @override
  void initState() {
    super.initState();
    _syncChoiceFromAi();
  }

  void _syncChoiceFromAi() {
    _choice = {};
    for (final t in widget.transactions) {
      final k = transactionCategoryKey(t);
      _choice[k] = widget.initialSuggestions[k];
    }
  }

  List<String> get _allowed => widget.appState.allowedCategoryPickerLabels;

  void _acceptAllFromAi() {
    setState(() {
      for (final t in widget.transactions) {
        final k = transactionCategoryKey(t);
        _choice[k] = widget.initialSuggestions[k];
      }
    });
  }

  void _saveAllAiSuggestions() {
    final toSave = <String, String>{};
    for (final t in widget.transactions) {
      final k = transactionCategoryKey(t);
      final s = widget.initialSuggestions[k];
      if (s != null && s.isNotEmpty) {
        toSave[k] = s;
      }
    }
    if (toSave.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No AI suggestions to apply. Pick categories below or Cancel.'),
        ),
      );
      return;
    }
    widget.appState.bulkSetCategoryOverrides(toSave);
    if (!mounted) return;
    final n = toSave.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved $n AI ${n == 1 ? 'category' : 'categories'}.',
        ),
      ),
    );
    widget.onSkip();
  }

  void _saveFromChoices() {
    final toSave = <String, String>{};
    for (final t in widget.transactions) {
      final k = transactionCategoryKey(t);
      final c = _choice[k]?.trim();
      if (c != null && c.isNotEmpty) {
        toSave[k] = c;
      }
    }
    if (toSave.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No categories selected. Choose one per row or tap Cancel.'),
        ),
      );
      return;
    }
    widget.appState.bulkSetCategoryOverrides(toSave);
    if (!mounted) return;
    final n = toSave.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved $n ${n == 1 ? 'category' : 'categories'}.',
        ),
      ),
    );
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 22,
                color: cs.primary.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Review ${widget.transactions.length} suggestion${widget.transactions.length == 1 ? '' : 's'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: _saveAllAiSuggestions,
                icon: const Icon(Icons.done_all_rounded, size: 20),
                label: const Text('Accept all & save'),
              ),
              OutlinedButton.icon(
                onPressed: _acceptAllFromAi,
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                label: const Text('Reset to AI'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: widget.transactions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = widget.transactions[i];
              final k = transactionCategoryKey(t);
              final selected = _choice[k];
              return Material(
                color: cs.surfaceContainerLowest,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
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
                      const SizedBox(height: 8),
                      DropdownButton<String?>(
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(12),
                        value: _validDropdownValue(selected),
                        hint: Text(
                          'Category',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
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
                        onChanged: (v) {
                          setState(() => _choice[k] = v);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, color: cs.outline.withValues(alpha: 0.18)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onSkip,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        label: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveFromChoices,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Value must be null or match an item (invalid AI labels map to null).
  String? _validDropdownValue(String? selected) {
    if (selected == null) return null;
    for (final a in _allowed) {
      if (a == selected) return selected;
    }
    return null;
  }
}
