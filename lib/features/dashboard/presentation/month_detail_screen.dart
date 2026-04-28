import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/models/models.dart';
import '../../transactions/domain/bank_statement_monthly.dart';
import '../../../core/formatting/formatting.dart';
import '../../transactions/domain/spend_categories.dart' show transactionCategoryKey;
import '../../transactions/widgets/transaction_category_dropdown.dart';

class MonthDetailScreen extends StatelessWidget {
  const MonthDetailScreen({
    super.key,
    required this.appState,
    required this.group,
  });

  final AppState appState;

  /// Month block from the same [DashboardSnapshot.monthlyGroups] list the user tapped.
  final MonthlyBankGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final scopedAccountIds = group.transactions
            .map((e) => e.transaction.accountId)
            .toSet();
        final hasScopedStorageEntry = scopedAccountIds.any(
          appState.transactionsByAccount.containsKey,
        );
        final allTransactions = appState.allTransactions;
        final lines = <BankStatementLine>[];
        if (hasScopedStorageEntry) {
          final byKey = <String, Transaction>{
            for (final t in allTransactions) transactionCategoryKey(t): t,
          };
          for (final line in group.transactions) {
            final k = transactionCategoryKey(line.transaction);
            final current = byKey[k];
            if (current == null) continue;
            final resolved = appState.resolveTransaction(
              current,
              allTransactionsContext: allTransactions,
            );
            lines.add(
              BankStatementLine(
                transaction: current,
                suggestedCategory: resolved.displayCategory,
              ),
            );
          }
        } else {
          lines.addAll(group.transactions);
        }

        final monthTotal = lines.fold<double>(0, (sum, e) => sum + e.transaction.amount);
        final accountIds = lines.map((e) => e.transaction.accountId).toSet();
        final clearAccountId = accountIds.length == 1 ? accountIds.first : null;
        final title = formatYearMonthLabel(group.yearMonth);
        final totalColor = monthTotal < 0
            ? const Color(0xFFC41E3A)
            : monthTotal > 0
                ? const Color(0xFF1B7A4C)
                : cs.onSurface;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F5F2),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(title),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (clearAccountId != null && lines.isNotEmpty)
                IconButton(
                  tooltip: 'Clear all transactions',
                  icon: const Icon(Icons.delete_forever_rounded),
                  color: Colors.red.shade700,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear all transactions?'),
                        content: const Text(
                          'This will permanently delete every transaction for this account. This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Delete all'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final deleted = await appState.clearTransactionsForAccount(
                      clearAccountId,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          deleted > 0
                              ? 'Deleted $deleted transaction${deleted == 1 ? '' : 's'}.'
                              : 'No transactions were deleted.',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE0DCD4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NET THIS MONTH',
                      style: theme.textTheme.labelMedium?.copyWith(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.38),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatMoney(monthTotal),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        color: totalColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lines.length} transactions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Transactions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE4E0D8)),
                ),
                child: lines.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 26,
                        ),
                        child: Text(
                          'No transactions left for this month.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : Column(
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
    final amountColor =
        tx.amount < 0 ? const Color(0xFFC41E3A) : const Color(0xFF1B7A4C);

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(tx.amount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: amountColor,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete transaction',
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: Colors.red.shade700,
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete this transaction?'),
                          content: const Text(
                            'This transaction will be permanently deleted.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      final deleted = await appState.deleteTransaction(tx);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            deleted
                                ? 'Transaction deleted.'
                                : 'Could not delete transaction.',
                          ),
                        ),
                      );
                    },
                    visualDensity: VisualDensity.compact,
                ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

