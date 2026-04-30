import '../../dashboard/domain/dashboard_snapshot.dart';
import '../data/budget_repository.dart';
import '../domain/budget_models.dart';
import 'budget_performance.dart';

class BudgetService {
  BudgetService({BudgetRepository? repository})
    : repository = repository ?? BudgetRepository();

  final BudgetRepository repository;

  Future<void> hydratePersistedBudgets({required DateTime reference}) {
    return repository.hydrate(reference: reference);
  }

  BudgetPeriodType get resolvedActiveBudgetPeriodType =>
      repository.resolvedActiveBudgetPeriodType;

  String get resolvedActiveBudgetPeriodKey =>
      repository.resolvedActiveBudgetPeriodKey;

  String activeBudgetYearMonth(DateTime spendReference) {
    return repository.budgetYearMonthKey(spendReference);
  }

  String budgetWeekStartKey(DateTime date) {
    return repository.budgetWeekStartKey(date);
  }

  String ensureCustomBudgetPeriod(DateTime start, DateTime end) {
    return repository.ensureCustomBudgetPeriod(start, end);
  }

  void setActiveBudgetPeriod({
    required BudgetPeriodType type,
    required String key,
  }) {
    repository.setActivePeriod(type, key);
  }

  List<String> budgetMonthsForPicker() {
    return repository.budgetMonthsForPicker();
  }

  List<String> budgetWeeksForPicker() {
    return repository.budgetWeeksForPicker();
  }

  List<String> customBudgetKeysForPicker() {
    return repository.customBudgetKeysForPicker();
  }

  BudgetPeriodRange? budgetPeriodRangeFor({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return repository.budgetPeriodRangeFor(
      periodType: periodType,
      periodKey: periodKey,
    );
  }

  String budgetPeriodLabel({
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return repository.budgetPeriodLabel(
      periodType: periodType,
      periodKey: periodKey,
    );
  }

  double? budgetForDisplayLabel({
    required String displayLabel,
    required BudgetPeriodType periodType,
    required String periodKey,
  }) {
    return repository.budgetForDisplayLabel(
      displayLabel: displayLabel,
      periodType: periodType,
      periodKey: periodKey,
    );
  }

  double? monthlyBudgetForDisplayLabel(
    String displayLabel, {
    String? yearMonth,
    required DateTime spendReference,
  }) {
    return budgetForDisplayLabel(
      displayLabel: displayLabel,
      periodType: BudgetPeriodType.monthly,
      periodKey: yearMonth ?? activeBudgetYearMonth(spendReference),
    );
  }

  Future<bool> commitBudgetDraft(
    BudgetPeriodType periodType,
    String periodKey,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) {
    return repository.commitBudgetDraft(
      periodType,
      periodKey,
      draftByNormalizedDisplayKey,
    );
  }

  Future<bool> commitMonthlyBudgetDraft(
    String yearMonth,
    Map<String, double?> draftByNormalizedDisplayKey,
  ) {
    return commitBudgetDraft(
      BudgetPeriodType.monthly,
      yearMonth,
      draftByNormalizedDisplayKey,
    );
  }

  BudgetPerformanceSnapshot budgetPerformanceForScope(
    DashboardScope scope, {
    required Iterable<String> customCategories,
    required Set<String> categoriesHiddenFromPicker,
    required Map<String, String> categoryDisplayRenames,
    required Map<String, double> Function(
      DashboardScope scope, {
      required DateTime start,
      required DateTime end,
    })
    spentByDisplayCategoryForScopeInRange,
    BudgetPeriodType? periodType,
    String? periodKey,
  }) {
    return buildBudgetPerformanceForScope(
      scope,
      budgets: repository,
      customCategories: customCategories,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
      categoryDisplayRenames: categoryDisplayRenames,
      spentByDisplayCategoryForScopeInRange:
          spentByDisplayCategoryForScopeInRange,
      periodType: periodType,
      periodKey: periodKey,
    );
  }
}
