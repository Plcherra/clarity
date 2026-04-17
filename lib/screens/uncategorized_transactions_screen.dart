import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bank_statement_monthly.dart';
import '../formatting.dart';
import '../widgets/transaction_category_dropdown.dart';

/// All statement rows whose effective category is Uncategorized, newest first.
class UncategorizedTransactionsScreen extends StatelessWidget {
  const UncategorizedTransactionsScreen({super.key, required this.appState});

  final AppState appState;

  static List<BankStatementLine> _lines(AppState state) {
    final out = <BankStatementLine>[];
    for (final g in state.monthlyGroups) {
      for (final line in g.transactions) {
        if (line.suggestedCategory.trim().toLowerCase() == 'uncategorized') {
          out.add(line);
        }
      }
    }
    out.sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final lines = _lines(appState);

        return Scaffold(
          backgroundColor: const Color(0xFFF7F5F2),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text('Uncategorized'),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nothing left to categorize.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    Text(
                      '${lines.length} transaction${lines.length == 1 ? '' : 's'}',
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
                        border: Border.all(color: const Color(0xFFE4E0D8)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: cs.outlineVariant.withValues(alpha: 0.35),
                              ),
                            _LineTile(line: lines[i], appState: appState),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.appState});

  final BankStatementLine line;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = line.transaction;
    final muted = cs.onSurface.withValues(alpha: 0.42);
    final amountColor = tx.amount < 0
        ? const Color(0xFFC41E3A)
        : const Color(0xFF1B7A4C);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  formatShortDate(tx.date),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    height: 1.35,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TransactionCategoryField(
                      appState: appState,
                      transaction: tx,
                      displayCategory: line.suggestedCategory,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatMoney(tx.amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
