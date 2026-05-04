import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../../../core/models/models.dart';
import '../../transactions/domain/bank_statement_monthly.dart';
import '../../../core/formatting/formatting.dart';
import '../../transactions/presentation/widgets/transaction_category_dropdown.dart';

class MonthDetailScreen extends StatefulWidget {
  const MonthDetailScreen({
    super.key,
    required this.controller,
    required this.group,
  });

  final DashboardUiController controller;

  /// Month block from the same [DashboardSnapshot.monthlyGroups] list the user tapped.
  final MonthlyBankGroup group;

  @override
  State<MonthDetailScreen> createState() => _MonthDetailScreenState();
}

class _MonthDetailScreenState extends State<MonthDetailScreen> {
  late final _MonthDetailDataNotifier _dataNotifier;

  @override
  void initState() {
    super.initState();
    _dataNotifier = _MonthDetailDataNotifier();
    widget.controller.addListener(_handleControllerChanged);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant MonthDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.group != widget.group) {
      _loadData();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _dataNotifier.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    _loadData();
  }

  Future<void> _loadData() async {
    _dataNotifier.setLoading();
    try {
      final lines = await widget.controller.refreshedLinesForMonth(
        widget.group,
      );
      if (!mounted) return;
      _dataNotifier.setData(lines);
    } on Object catch (error) {
      if (!mounted) return;
      _dataNotifier.setError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: _dataNotifier,
      builder: (context, _) {
        final title = formatYearMonthLabel(widget.group.yearMonth);
        final lines = _dataNotifier.data;
        final accountIds =
            lines?.map((e) => e.transaction.accountId).toSet() ??
            const <String>{};
        final clearAccountId = accountIds.length == 1 ? accountIds.first : null;

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
              if (clearAccountId != null && lines != null && lines.isNotEmpty)
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
                    final deleted = await widget.controller
                        .clearTransactionsForAccount(clearAccountId);
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
          body: lines == null
              ? _dataNotifier.error != null
                    ? const Center(child: Text('Could not load transactions.'))
                    : const Center(child: CircularProgressIndicator())
              : _MonthDetailBody(
                  lines: lines,
                  controller: widget.controller,
                  theme: theme,
                  colorScheme: cs,
                ),
        );
      },
    );
  }
}

class _MonthDetailDataNotifier extends ChangeNotifier {
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

class _MonthDetailBody extends StatelessWidget {
  const _MonthDetailBody({
    required this.lines,
    required this.controller,
    required this.theme,
    required this.colorScheme,
  });

  final List<BankStatementLine> lines;
  final DashboardUiController controller;
  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final monthTotal = lines.fold<double>(
      0,
      (sum, e) => sum + e.transaction.amount,
    );
    final totalColor = monthTotal < 0
        ? const Color(0xFFC41E3A)
        : monthTotal > 0
        ? const Color(0xFF1B7A4C)
        : colorScheme.onSurface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            color: colorScheme.surface,
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
                  color: colorScheme.onSurface.withValues(alpha: 0.38),
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
                  color: colorScheme.onSurface.withValues(alpha: 0.45),
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
            color: colorScheme.surface,
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
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
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
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      _LineTile(
                        line: lines[i],
                        transactionController: controller.ui.transactions,
                        onDeleteTransaction: controller.deleteTransaction,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.transactionController,
    required this.onDeleteTransaction,
  });

  final BankStatementLine line;
  final TransactionUiController transactionController;
  final Future<bool> Function(Transaction transaction) onDeleteTransaction;

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
                      controller: transactionController,
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
                      final deleted = await onDeleteTransaction(tx);
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
