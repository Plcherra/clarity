# Permanent Workflow Cleanup Plan

Use this plan before auth and API key work. The goal is to make extracted
services permanent, not temporary routes back into old helpers.

## Phase 1 - Account Workflow

- [x] Move `deleteAccountWorkflow` out of `AccountService`.
- [x] Create `lib/features/accounts/application/account_workflow_service.dart`.
- [x] Keep `AccountService` focused on account state and persistence.
- [x] Wire UI account deletion to `AccountWorkflowService`.
- [x] Remove AppState account deletion coordination.
- [x] Verify with `dart analyze` and focused tests.

Completed: added `AccountWorkflowService` for account deletion coordination.
`AccountService` now only removes and persists the account row plus transaction
map slice, while the workflow service updates transaction metadata and refreshes
state. `AppState` creates the account workflow service and no longer exposes
`deleteAccount`.

## Phase 2 - Budget Workflow

- [x] Move `setActiveBudgetPeriod` coordination out of `AppState`.
- [x] Move `commitBudgetDraft` coordination out of `AppState`.
- [x] Create `lib/features/budgets/application/budget_workflow_service.dart`.
- [x] Keep `BudgetService` focused on budget state and persistence.
- [x] Wire budget UI mutations to `BudgetWorkflowService`.
- [x] Verify with `dart analyze` and focused tests.

Completed: added `BudgetWorkflowService` for budget period selection and budget
draft commits. `AppState` creates the workflow service and no longer exposes
budget mutation methods. `BudgetUiController` now delegates budget mutations to
the workflow service directly.

## Phase 3 - Startup Hydration

- [x] Move startup hydration order out of `AppState`.
- [x] Keep existing service hydration methods in their feature services.
- [x] Create or expand an app-level startup coordinator.
- [x] Make `bootstrap()` call the startup coordinator instead of many AppState
      hydration delegates.
- [x] Verify with `dart analyze` and focused tests.

Completed: added `AppStartupService` for startup hydration order and deleted the
old `app_hydration.dart` wrapper. `AppState` no longer exposes individual
startup hydration delegates. `bootstrap()` now calls
`appState.startupService.hydrateForStartup()`.

## Phase 4 - Refresh Permanence

- [x] Keep `DashboardRefreshCoordinator` temporarily as app-level coordination.
- [x] Audit every `refreshAllState()` caller.
- [ ] Replace broad refresh calls with scoped controller/service refreshes where
      practical.
- [x] Remove `refreshAllState()` from public AppState usage.

Completed: `DashboardRefreshCoordinator` now owns the refresh-and-notify path.
Workflow services receive the coordinator callback directly, tests call the
coordinator instead of `AppState.refreshAllState()`, and `AppState` no longer
exposes a public refresh delegate. Broad refresh remains centralized in the
coordinator until scoped controller refreshes are designed.

## Phase 5 - Profile/Auth Boundary

- [x] Keep `localProfile`, `setLocalProfile`, and onboarding routing until auth
      starts.
- [ ] Move session/profile state into auth/profile controllers during auth work.
- [x] Stop passing full `AppState` into onboarding; use narrow callbacks until
      auth/profile has a permanent owner.

Completed: `OnboardingScreen` no longer imports or receives full `AppState`.
It accepts only a `saveLocalProfile` callback and `AppUiDependencies` for the
post-onboarding shell route. Full auth/session ownership is intentionally left
for the auth feature.
