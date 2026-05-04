import 'package:flutter/material.dart';

import 'budget_category_row.dart';
import 'budgets_viewmodel.dart';

class BudgetCategoryList extends StatelessWidget {
  const BudgetCategoryList({
    super.key,
    required this.items,
    required this.controllers,
    required this.focusNodes,
    required this.onTrackCategoryCount,
    required this.budgetedCategoryCount,
    required this.onCategoryValueChanged,
  });

  final List<BudgetCategoryListItemData> items;
  final Map<String, TextEditingController> controllers;
  final Map<String, FocusNode> focusNodes;
  final int onTrackCategoryCount;
  final int budgetedCategoryCount;
  final ValueChanged<String> onCategoryValueChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.11)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.018),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                Text(
                  'Categories',
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$onTrackCategoryCount/$budgetedCategoryCount on track',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No categories yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.56),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: cs.outline.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final controller = controllers[item.canonical];
                      final focusNode = focusNodes[item.canonical];
                      if (controller == null || focusNode == null) {
                        return const SizedBox.shrink();
                      }
                      final indicatorColor = !item.hasBudget
                          ? cs.onSurface.withValues(alpha: 0.32)
                          : item.isOverspent
                          ? const Color(0xFFC41E3A)
                          : const Color(0xFF1B7A4C);
                      final statusColor = item.isOverspent
                          ? const Color(0xFFC41E3A)
                          : cs.onSurface.withValues(alpha: 0.58);
                      return BudgetCategoryRowTile(
                        displayLabel: item.displayLabel,
                        controller: controller,
                        focusNode: focusNode,
                        indicatorColor: indicatorColor,
                        statusText: item.statusText,
                        statusColor: statusColor,
                        onValueChanged: onCategoryValueChanged,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
