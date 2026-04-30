import 'package:flutter/material.dart';

import '../../../app_state.dart';

class BudgetsHeader extends StatelessWidget {
  const BudgetsHeader({
    super.key,
    required this.selectedType,
    required this.selectedPeriodKey,
    required this.keys,
    required this.monthlyLabel,
    required this.weeklyLabel,
    required this.weeklyRangeLabel,
    required this.customStartLabel,
    required this.customEndLabel,
    required this.onPeriodTypeChanged,
    required this.onPickMonthly,
    required this.onPickWeekly,
    required this.onPickCustomStart,
    required this.onPickCustomEnd,
    required this.compactButtonStyle,
  });

  final BudgetPeriodType selectedType;
  final String selectedPeriodKey;
  final List<String> keys;
  final String monthlyLabel;
  final String weeklyLabel;
  final String weeklyRangeLabel;
  final String customStartLabel;
  final String customEndLabel;
  final ValueChanged<BudgetPeriodType> onPeriodTypeChanged;
  final VoidCallback onPickMonthly;
  final VoidCallback onPickWeekly;
  final VoidCallback onPickCustomStart;
  final VoidCallback onPickCustomEnd;
  final ButtonStyle compactButtonStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.012),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<BudgetPeriodType>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment<BudgetPeriodType>(
                value: BudgetPeriodType.monthly,
                label: Text('Monthly'),
              ),
              ButtonSegment<BudgetPeriodType>(
                value: BudgetPeriodType.weekly,
                label: Text('Weekly'),
              ),
              ButtonSegment<BudgetPeriodType>(
                value: BudgetPeriodType.custom,
                label: Text('Custom'),
              ),
            ],
            selected: {selectedType},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              onPeriodTypeChanged(selection.first);
            },
          ),
          const SizedBox(height: 10),
          if (selectedType == BudgetPeriodType.monthly)
            keys.isEmpty
                ? Text(
                    'No months available.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  )
                : OutlinedButton.icon(
                    style: compactButtonStyle,
                    onPressed: onPickMonthly,
                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                    label: Text(monthlyLabel),
                  ),
          if (selectedType == BudgetPeriodType.weekly) ...[
            OutlinedButton.icon(
              style: compactButtonStyle,
              onPressed: onPickWeekly,
              icon: const Icon(Icons.date_range_rounded, size: 16),
              label: Text(weeklyLabel),
            ),
            const SizedBox(height: 6),
            Text(
              weeklyRangeLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.58),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (selectedType == BudgetPeriodType.custom)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: compactButtonStyle,
                    onPressed: onPickCustomStart,
                    icon: const Icon(Icons.calendar_today_rounded, size: 15),
                    label: Text(
                      customStartLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: compactButtonStyle,
                    onPressed: onPickCustomEnd,
                    icon: const Icon(Icons.event_rounded, size: 15),
                    label: Text(
                      customEndLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
