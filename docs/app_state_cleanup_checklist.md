# AppState Cleanup Checklist

Use this as the working tracker for shrinking `lib/app/app_state.dart`.
When a step is completed, mark it with `[x]` and add a short note if needed.

## Phase 1 - Quick Wins

- [x] Remove `AppState` import from `dashboard/domain/dashboard_queries.dart`
- [x] Remove `AppState` import from `budgets/application/budget_performance.dart`
- [x] Move profile state into `ProfileService`
- [x] Move profile hydration/save methods out of `AppState`

Completed: dashboard queries and budget performance no longer import
`AppState`; profile persistence now delegates to `ProfileService`.

## Phase 2 - Budget Cleanup

- [x] Create `BudgetService`
- [x] Move budget helper methods out of `AppState`
- [x] Stop exposing `appState.budgets` directly
- [x] Update `BudgetsViewModel` to use `BudgetService`

Completed: budget repository access now lives behind `BudgetService`; `AppState`
keeps only delegating budget methods and budget feature code uses the service.

## Phase 3 - Dashboard State Cleanup

- [x] Move dashboard derived fields out of `AppState`
- [x] Move `_recomputeDerived` into dashboard/service layer
- [x] Move dashboard spend helper methods out of `AppState`
- [x] Keep `refreshAllState()` temporarily as a delegate

Completed: dashboard derived values and recompute/refresh coordination now live
in `DashboardService`; `AppState` keeps compatibility getters and delegating
dashboard helper methods.

## Phase 4 - Transaction Workflow Cleanup

- [x] Move `loadFromCsv` workflow out of `AppState`
- [x] Move transaction delete/clear coordination out of `AppState`
- [x] Move import batch delete coordination out of `AppState`
- [x] Move AI-after-import coordination out of `AppState`

Completed: transaction import, delete/clear, import-batch delete, and
AI-after-import workflows now delegate to `TransactionService`; `AppState`
keeps compatibility methods and supplies dashboard/notification callbacks.

## Phase 5 - Category Workflow Cleanup

- [x] Move `setCategoryOverride` coordination out of `AppState`
- [x] Move `bulkSetCategoryOverrides` coordination out of `AppState`
- [x] Move `createCategoryAndAssign` coordination out of `AppState`
- [x] Move `deleteCategory` / `renameCategory` coordination out of `AppState`

Completed: category assignment, creation, delete, and rename workflows now
delegate to `CategoryService`; `AppState` keeps compatibility methods and
passes catalog/transaction/dashboard callbacks.

## Phase 6 - UI Dependency Cleanup

- [x] Stop passing full `AppState` into dashboard screens
- [x] Stop passing full `AppState` into transaction screens/widgets
- [x] Stop passing full `AppState` into account screens
- [x] Stop passing full `AppState` into budget screens

Completed: feature UI now receives narrow controllers from `AppUiDependencies`
instead of taking `AppState` directly; controllers temporarily delegate to
`AppState` while Phase 7 removes the remaining composition-root coupling.

## Phase 7 - Final Shrink

- [x] Keep `AppState` only as a thin composition root
- [x] Remove direct feature logic from `AppState`
- [x] Replace broad `notifyListeners()` with scoped listenables/controllers
- [ ] Delete `AppState` if it becomes unnecessary

Completed: feature UI now listens to scoped controllers, AppState no longer
broadcasts every feature data mutation through `notifyListeners()`, and account
delete coordination moved behind `AccountService`. AppState remains as the
bootstrap/test compatibility facade, so deletion is intentionally deferred.
