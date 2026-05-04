import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../domain/bank_statement_monthly.dart';
import '../../dashboard/domain/dashboard_snapshot.dart';
import '../../../core/formatting/formatting.dart';
import 'widgets/transaction_category_dropdown.dart';

const double _kReviewHorizontalPadding = 24;
const double _kReviewScrollTopPadding = 8;
const double _kReviewScrollBottomPadding = 32;

/// Full-screen flow: one uncategorized transaction at a time. Category picker
/// and save-rule behavior match the list view — only presentation differs.
///
/// [scope] must match the dashboard that opened this screen ([GlobalDashboardScope]
/// for Overview, [AccountDashboardScope] for an account).
class TransactionReviewScreen extends StatefulWidget {
  const TransactionReviewScreen({
    super.key,
    required this.controller,
    required this.scope,
  });

  final TransactionUiController controller;
  final DashboardScope scope;

  @override
  State<TransactionReviewScreen> createState() =>
      _TransactionReviewScreenState();
}

class _TransactionReviewScreenState extends State<TransactionReviewScreen> {
  late final _TransactionReviewDataNotifier _dataNotifier;

  @override
  void initState() {
    super.initState();
    _dataNotifier = _TransactionReviewDataNotifier();
    widget.controller.addListener(_handleControllerChanged);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant TransactionReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.scope != widget.scope) {
      _loadData();
    }
  }

  void _handleControllerChanged() {
    _loadData();
  }

  Future<void> _loadData() async {
    _dataNotifier.setLoading();
    try {
      final data = await widget.controller.uncategorizedQueue(widget.scope);
      if (!mounted) return;
      _dataNotifier.setData(data);
    } on Object catch (error) {
      if (!mounted) return;
      _dataNotifier.setError(error);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _dataNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: _dataNotifier,
      builder: (context, _) {
        final uncategorizedQueue = _dataNotifier.data;
        return Scaffold(
          backgroundColor: const Color(0xFFF7F5F2),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              uncategorizedQueue == null || uncategorizedQueue.isEmpty
                  ? 'Review'
                  : '${uncategorizedQueue.length} left',
            ),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Done',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: _buildBody(
              theme: theme,
              colorScheme: cs,
              uncategorizedQueue: uncategorizedQueue,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required List<BankStatementLine>? uncategorizedQueue,
  }) {
    if (uncategorizedQueue == null) {
      if (_dataNotifier.error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(_kReviewHorizontalPadding),
            child: Text(
              'Could not load transactions.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (uncategorizedQueue.isEmpty) {
      return _ReviewDoneEmptyState(theme: theme, colorScheme: colorScheme);
    }

    return _SingleUncategorizedReview(
      controller: widget.controller,
      theme: theme,
      colorScheme: colorScheme,
      line: uncategorizedQueue.first,
    );
  }
}

class _TransactionReviewDataNotifier extends ChangeNotifier {
  List<BankStatementLine>? _data;
  Object? _error;
  var _loading = false;

  List<BankStatementLine>? get data => _data;
  Object? get error => _error;
  bool get loading => _loading;

  void setLoading() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void setData(List<BankStatementLine> data) {
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

/// Shown when there are no uncategorized transactions left.
class _ReviewDoneEmptyState extends StatelessWidget {
  const _ReviewDoneEmptyState({required this.theme, required this.colorScheme});

  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_kReviewHorizontalPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 56,
              color: colorScheme.primary.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 20),
            Text(
              'Nothing left to categorize.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Great work.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-at-a-time card for the first line in the uncategorized queue.
class _SingleUncategorizedReview extends StatelessWidget {
  const _SingleUncategorizedReview({
    required this.controller,
    required this.theme,
    required this.colorScheme,
    required this.line,
  });

  final TransactionUiController controller;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final BankStatementLine line;

  @override
  Widget build(BuildContext context) {
    final tx = line.transaction;
    final amountColor = tx.amount < 0
        ? const Color(0xFFC41E3A)
        : const Color(0xFF1B7A4C);
    final mutedOnSurface = colorScheme.onSurface.withValues(alpha: 0.42);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            _kReviewHorizontalPadding,
            _kReviewScrollTopPadding,
            _kReviewHorizontalPadding,
            _kReviewScrollBottomPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  formatShortDate(tx.date),
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: mutedOnSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(
                  tx.description,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 28),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMoney(tx.amount),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.2,
                      color: amountColor,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'Category',
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 0.9,
                    color: mutedOnSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TransactionCategoryField(
                  controller: controller,
                  transaction: tx,
                  displayCategory: line.suggestedCategory,
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose a category to continue. '
                  'Outflows can save a matching rule afterward.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedOnSurface,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
