import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../transactions/domain/bank_statement_monthly.dart';
import '../../../core/formatting/formatting.dart';
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
        final title = formatYearMonthLabel(group.yearMonth);
        final totalColor = group.totalAmount < 0
            ? const Color(0xFFC41E3A)
            : group.totalAmount > 0
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
                      formatMoney(group.totalAmount),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        color: totalColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.transactions.length} transactions',
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
                child: Column(
                  children: [
                    for (var i = 0; i < group.transactions.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      _LineTile(line: group.transactions[i], appState: appState),
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

