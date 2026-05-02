import '../domain/budget_models.dart';
import 'budget_service.dart';

class BudgetWorkflowService {
  BudgetWorkflowService({
    required this.budgetService,
    required this.notifyDashboardAndBudgetsChanged,
    required this.refreshAllState,
  });

  final BudgetService budgetService;
  final void Function() notifyDashboardAndBudgetsChanged;
  final void Function() refreshAllState;

  void setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    budgetService.setActiveBudgetPeriod(type: type, key: key);
    notifyDashboardAndBudgetsChanged();
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) async {
    final ok = await budgetService.commitBudgetDraft(
      periodType,
      periodKey,
      draftByNormalizedDisplayKey,
    );
    if (ok) refreshAllState();
    return ok;
  }
}
