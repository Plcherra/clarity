import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bank_statement_monthly.dart';
import '../dashboard_queries.dart';
import '../dashboard_snapshot.dart';
import '../formatting.dart';
import '../widgets/transaction_category_dropdown.dart';
const double _kReviewHorizontalPadding = 24;
const double _kReviewScrollTopPadding = 8;
const double _kReviewScrollBottomPadding = 32;

/// Full-screen flow: one uncategorized transaction at a time (always the next
/// in queue as [AppState] updates). Category picker and save-rule behavior
/// match the list view — only presentation differs.
///
/// [scope] must match the dashboard that opened this screen ([GlobalDashboardScope]
/// for Overview, [AccountDashboardScope] for an account).
class TransactionReviewScreen extends StatelessWidget {
  const TransactionReviewScreen({
    super.key,
    required this.appState,
    required this.scope,
  });

  final AppState appState;
  final DashboardScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final uncategorizedQueue =
            uncategorizedTransactionsForDashboardScope(appState, scope);

        return Scaffold(
          backgroundColor: const Color(0xFFF7F5F2),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              uncategorizedQueue.isEmpty
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
            child: uncategorizedQueue.isEmpty
                ? _ReviewDoneEmptyState(theme: theme, colorScheme: cs)
                : _SingleUncategorizedReview(
                    appState: appState,
                    theme: theme,
                    colorScheme: cs,
                    line: uncategorizedQueue.first,
                  ),
          ),
        );
      },
    );
  }
}

/// Shown when there are no uncategorized transactions left.
class _ReviewDoneEmptyState extends StatelessWidget {
  const _ReviewDoneEmptyState({
    required this.theme,
    required this.colorScheme,
  });

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
    required this.appState,
    required this.theme,
    required this.colorScheme,
    required this.line,
  });

  final AppState appState;
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
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 16,
            ),
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
                  appState: appState,
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
