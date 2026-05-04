import '../domain/budget_models.dart';
import '../data/budget_service.dart';

class BudgetWorkflowService {
  BudgetWorkflowService({
    required this.budgetService,
    required this.notifyDashboardAndBudgetsChanged,
    required this.refreshAllState,
  });

  final BudgetService budgetService;
  final void Function() notifyDashboardAndBudgetsChanged;
  final Future<void> Function() refreshAllState;

  Future<void> setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) async {
    notifyDashboardAndBudgetsChanged();
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    var changed = false;
    final existing = await budgetService.fetchBudgets();
    for (final entry in draftByNormalizedDisplayKey.entries) {
      final name = entry.key.trim();
      if (name.isEmpty) continue;

      final existingBudget = existing.where((budget) {
        return budget.name.trim().toLowerCase() == name.toLowerCase() &&
            budget.period == _periodToDatabaseValue(periodType) &&
            _sameDate(budget.startDate, _startDateFor(periodType, periodKey));
      }).firstOrNull;

      final amount = entry.value;
      if (amount == null) {
        if (existingBudget != null) {
          await budgetService.deleteBudget(existingBudget.id);
          changed = true;
        }
        continue;
      }

      if (existingBudget == null) {
        await budgetService.createBudget(
          name: name,
          amount: amount,
          period: _periodToDatabaseValue(periodType),
          startDate: _startDateFor(periodType, periodKey),
        );
      } else {
        await budgetService.updateBudget(existingBudget.id, amount: amount);
      }
      changed = true;
    }

    if (changed) {
      await refreshAllState();
      notifyDashboardAndBudgetsChanged();
    }
    return changed;
  }
}

String _periodToDatabaseValue(BudgetPeriodType periodType) {
  return switch (periodType) {
    BudgetPeriodType.monthly => 'monthly',
    BudgetPeriodType.weekly => 'weekly',
    BudgetPeriodType.custom => 'custom',
  };
}

DateTime? _startDateFor(BudgetPeriodType periodType, String periodKey) {
  if (periodType == BudgetPeriodType.monthly) {
    final parts = periodKey.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    return DateTime(year, month);
  }
  final parts = periodKey.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

bool _sameDate(DateTime? a, DateTime? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
