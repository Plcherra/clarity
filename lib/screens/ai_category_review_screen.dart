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
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: switch (_phase) {
        _FlowPhase.loading => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 24),
                Text('Fetching suggestions…'),
              ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = error is MissingOpenAiApiKeyException
        ? error.toString()
        : 'Could not reach AI or parse the response. Check your network and API key.';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(msg, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onSkip, child: const Text('Skip')),
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
    if (toSave.isNotEmpty) {
      widget.appState.bulkSetCategoryOverrides(toSave);
    }
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
    if (toSave.isNotEmpty) {
      widget.appState.bulkSetCategoryOverrides(toSave);
    }
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
          child: Text(
            'Review ${widget.transactions.length} suggestion${widget.transactions.length == 1 ? '' : 's'}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _saveAllAiSuggestions,
                child: const Text('Accept all AI & save'),
              ),
              OutlinedButton(
                onPressed: _acceptAllFromAi,
                child: const Text('Reset to AI'),
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
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                        value: _validDropdownValue(selected),
                        hint: const Text('Category'),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onSkip,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saveFromChoices,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// [DropdownButtonFormField] requires value to be null or one of the items.
  String? _validDropdownValue(String? selected) {
    if (selected == null) return null;
    for (final a in _allowed) {
      if (a == selected) return selected;
    }
    return null;
  }
}
