import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../transactions/domain/bank_statement_monthly.dart';
import '../domain/dashboard_queries.dart';
import '../domain/dashboard_snapshot.dart';
import '../../../core/formatting/formatting.dart';
import '../../../core/models/models.dart';
import '../../budgets/presentation/budgets_screen.dart';
import 'month_detail_screen.dart';
import '../../transactions/presentation/transaction_review_screen.dart';
import '../../transactions/presentation/ai_low_confidence_review_screen.dart';
import '../../../ai_categorization_service.dart';

typedef SnapshotBuilder =
    DashboardSnapshot Function(AppState appState, DashboardScope scope);

Color _balanceColor(double v) {
  if (v > 0) return const Color(0xFF1B7A4C);
  if (v < 0) return const Color(0xFFC41E3A);
  return const Color(0xFF3A3A38);
}

class _AiRunningDialog extends StatelessWidget {
  const _AiRunningDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Auto-categorizing'),
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Applying high-confidence categories…',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class FinancialDashboardView extends StatelessWidget {
  const FinancialDashboardView({
    super.key,
    required this.appState,
    required this.scope,
    required this.buildSnapshot,
    this.showBackButton = false,
    this.title = 'Overview',
    this.onUploadTransactions,
  });

  final AppState appState;
  final DashboardScope scope;
  final SnapshotBuilder buildSnapshot;
  final bool showBackButton;
  final String title;

  /// When set (per-account dashboard only), shows a prominent CSV import control.
  final Future<void> Function()? onUploadTransactions;

  static const _sectionGap = 32.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final snap = buildSnapshot(appState, scope);
        final uncategorizedQueue =
            uncategorizedTransactionsForDashboardScope(appState, scope);
        final attentionCount = uncategorizedQueue.length;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: showBackButton
                ? IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            actions: [
              IconButton(
                tooltip: 'Auto-categorize (AI)',
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final service = AICategorizationService();
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const _AiRunningDialog(),
                  );
                  try {
                    final res = await appState.autoCategorizeGlobalUncategorized(
                      service: service,
                    );
                    if (nav.canPop()) nav.pop(); // close dialog

                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'AI applied ${res.applied} categor${res.applied == 1 ? 'y' : 'ies'}. '
                          '${res.queuedForReview} need review.',
                        ),
                        action: res.queuedForReview > 0
                            ? SnackBarAction(
                                label: 'Review',
                                onPressed: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (context) =>
                                          AiLowConfidenceReviewScreen(
                                            appState: appState,
                                          ),
                                    ),
                                  );
                                },
                              )
                            : SnackBarAction(
                                label: 'Undo',
                                onPressed: () async {
                                  await appState.undoLastAiAutoApply();
                                },
                              ),
                      ),
                    );
                  } catch (e) {
                    if (nav.canPop()) nav.pop(); // close dialog
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('AI failed: $e'),
                        action: SnackBarAction(
                          label: 'Dismiss',
                          onPressed: () {},
                        ),
                      ),
                    );
                  } finally {
                    service.close();
                  }
                },
                icon: Icon(
                  Icons.auto_awesome_rounded,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFFF3F1ED), cs.surface],
              ),
            ),
            child: SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Text(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            letterSpacing: 3.2,
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 8),
                          Text(
                            'debug: reviewQueue=$attentionCount · '
                            'snapUncat=${snap.uncategorizedCount}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.onSurface.withValues(alpha: 0.42),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (onUploadTransactions != null) ...[
                          _UploadTransactionsButton(
                            onPressed: onUploadTransactions!,
                          ),
                          const SizedBox(height: 20),
                        ],
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    BudgetsScreen(appState: appState),
                              ),
                            );
                          },
                          child: const Text('Set Budgets'),
                        ),
                        const SizedBox(height: 20),
                        if (attentionCount > 0) ...[
                          _UncategorizedAttentionCard(
                            count: attentionCount,
                            onTap: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (context) => TransactionReviewScreen(
                                    appState: appState,
                                    scope: scope,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: _sectionGap),
                        ],
                        _ResponsiveMetricCard(
                          label: 'Available this month',
                          value: formatMoney(snap.availableThisMonth),
                          large: true,
                          valueColor: _balanceColor(snap.availableThisMonth),
                          footnote:
                              'Income ${formatMoney(snap.incomeThisMonth)} · '
                              'Spending ${formatMoney(snap.spentThisMonth)}',
                        ),
                        const SizedBox(height: _sectionGap),
                        _ResponsiveMetricCard(
                          label: 'Spent this month',
                          value: formatMoney(snap.spentThisMonth),
                          large: false,
                          valueColor: const Color(0xFF9B2C2C),
                        ),
                        const SizedBox(height: _sectionGap),
                        _SectionTitle(
                          theme: theme,
                          title: 'Biggest leaks this month',
                        ),
                        const SizedBox(height: 16),
                        _BiggestLeaksCard(leaks: snap.biggestLeaksThisMonth),
                        const SizedBox(height: _sectionGap),
                        _BurnRateCard(
                          runwayDays: snap.burnRunwayDays,
                          totalBalance: snap.totalBalance,
                          spentThisMonth: snap.spentThisMonth,
                        ),
                        const SizedBox(height: _sectionGap),
                        _SectionTitle(theme: theme, title: 'Statement by month'),
                        const SizedBox(height: 8),
                        Text(
                          'Tap a month for transactions',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.8,
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _MonthlyGroupsList(
                          groups: snap.monthlyGroups,
                          appState: appState,
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UploadTransactionsButton extends StatefulWidget {
  const _UploadTransactionsButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_UploadTransactionsButton> createState() =>
      _UploadTransactionsButtonState();
}

class _UploadTransactionsButtonState extends State<_UploadTransactionsButton> {
  var _busy = false;

  Future<void> _handleTap() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _busy ? null : _handleTap,
        child: _busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: cs.onPrimary, size: 22),
                  const SizedBox(width: 8),
                  const Text('+ Upload Transactions'),
                ],
              ),
      ),
    );
  }
}

class _UncategorizedAttentionCard extends StatelessWidget {
  const _UncategorizedAttentionCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const red = Color(0xFFB91C1C);
    return Material(
      color: const Color(0xFFFFF5F5),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: red.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: red.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Row(
              children: [
                const Icon(Icons.label_off_outlined, color: red, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count transaction${count == 1 ? '' : 's'} need attention',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: red,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to review uncategorized items',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: red.withValues(alpha: 0.65),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BiggestLeaksCard extends StatelessWidget {
  const _BiggestLeaksCard({required this.leaks});

  final List<CategoryLeakStat> leaks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (leaks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE4E0D8)),
        ),
        child: Text(
          'No spending this month.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE4E0D8)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < leaks.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            _LeakRow(stat: leaks[i]),
          ],
        ],
      ),
    );
  }
}

class _LeakRow extends StatelessWidget {
  const _LeakRow({required this.stat});

  final CategoryLeakStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = stat.percentChangeFromLastMonth;
    final goodTrend = pct != null && pct < 0;
    final badTrend = pct != null && pct > 0;
    final trendColor = goodTrend
        ? const Color(0xFF1B7A4C)
        : badTrend
            ? const Color(0xFFC41E3A)
            : cs.onSurface.withValues(alpha: 0.4);

    Widget trendWidget;
    if (pct == null && stat.amountLastMonth <= 0 && stat.amountThisMonth > 0) {
      trendWidget = Text(
        'New',
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.45),
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (pct == null) {
      trendWidget = Text(
        '—',
        style: theme.textTheme.labelLarge?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.35),
        ),
      );
    } else {
      final pctLabel =
          '${pct >= 0 ? '+' : ''}${(pct * 100).abs().toStringAsFixed(0)}%';
      trendWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pct >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 18,
            color: trendColor,
          ),
          const SizedBox(width: 2),
          Text(
            pctLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: trendColor,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            stat.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(stat.amountThisMonth),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 4),
            trendWidget,
          ],
        ),
      ],
    );
  }
}

class _BurnRateCard extends StatelessWidget {
  const _BurnRateCard({
    required this.runwayDays,
    required this.totalBalance,
    required this.spentThisMonth,
  });

  final int? runwayDays;
  final double totalBalance;
  final double spentThisMonth;

  String _message() {
    if (runwayDays != null) {
      final x = runwayDays!;
      return "You're burning through money at a rate that will last you $x more day${x == 1 ? '' : 's'}.";
    }
    if (totalBalance <= 0) {
      return 'With no positive balance, runway cannot be estimated from this pace.';
    }
    if (spentThisMonth <= 0) {
      return 'No spending recorded yet this month to estimate burn rate.';
    }
    return 'Not enough data to estimate how long your balance will last.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0DCD4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            color: cs.onSurface.withValues(alpha: 0.45),
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _message(),
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyGroupsList extends StatelessWidget {
  const _MonthlyGroupsList({required this.groups, required this.appState});

  final List<MonthlyBankGroup> groups;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (groups.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE4E0D8)),
        ),
        child: Text(
          'No months to show after filtering this file.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _MonthCard(group: groups[i], appState: appState),
        ],
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.group, required this.appState});

  final MonthlyBankGroup group;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = formatYearMonthLabel(group.yearMonth);
    final totalColor = group.totalAmount < 0
        ? const Color(0xFFC41E3A)
        : group.totalAmount > 0
            ? const Color(0xFF1B7A4C)
            : cs.onSurface;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => MonthDetailScreen(
                appState: appState,
                group: group,
              ),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE4E0D8)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(group.totalAmount),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: totalColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'net',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.38),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.title});

  final ThemeData theme;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
      ),
    );
  }
}

class _ResponsiveMetricCard extends StatelessWidget {
  const _ResponsiveMetricCard({
    required this.label,
    required this.value,
    required this.large,
    this.valueColor,
    this.footnote,
  });

  final String label;
  final String value;
  final bool large;
  final Color? valueColor;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = valueColor ?? cs.onSurface;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final valueSize = large
            ? (w * 0.15).clamp(34.0, 72.0)
            : (w * 0.12).clamp(30.0, 58.0);
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: w >= 380 ? 28 : 20,
            vertical: large ? 32 : 28,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE0DCD4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 2.6,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.36),
                ),
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -2,
                    height: 1.02,
                    color: color,
                    fontSize: valueSize,
                  ),
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(height: 12),
                Text(
                  footnote!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.42),
                    letterSpacing: 0.2,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

