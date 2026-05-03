# AppState Dedicated Cleanup Plan

Historical plan. `lib/app/app_state.dart` has since been deleted and replaced
by `lib/app/app_composition.dart`, `AuthController`, `ProfileController`, and
scoped UI controllers. Keep this file as cleanup history, not current
architecture guidance.

Original plan goal: shrink `lib/app/app_state.dart` into a thin composition
root while preserving the current public API until tests and UI no longer
needed it.

Audit at the time:

- `AppState` is 427 lines.
- It creates and wires feature services.
- It still exposes compatibility getters/setters, startup hydration, budget
  mutations, account mutations, and refresh coordination.
- Feature UI mostly listens to scoped controllers in `AppUiDependencies`, not
  directly to all of `AppState`.
- `ClarityApp` still listens to `AppState` for profile/onboarding routing.
- `bootstrap()` still calls individual hydration methods on `AppState`.

## AppState Responsibilities At The Time

### Service Composition

- `transactionService`
- `categoryService`
- `categoryCatalogService`
- `merchantService`
- `profileService`
- `budgetService`
- `accountService`
- `aiCategorizationService`
- `_dashboard`
- `_dashboardRefresh`
- `categoryWorkflowService`
- `transactionWorkflowService`
- `ui`

Keep this role for now. This is the part that is appropriate for a composition
root.

### App Shell / Profile State

- `localProfile`
- `hydrateLocalProfile`
- `setLocalProfile`
- `_notifyProfileChanged`

This can stay until auth/profile work begins. Later, auth should own session
state and profile should own profile state.

### Startup Hydration

- `hydratePersistedBudgets`
- `hydratePersistedCategoryCatalog`
- `hydratePersistedAccounts`
- `hydratePersistedTransactions`
- `dedupePersistedTransactionsIfNeeded`
- `hydrateTransactionCategoryAssignments`
- `hydrateAiCategorySuggestions`
- `hydrateMerchantCategoryMemory`

These are bootstrap orchestration methods. They are good candidates for a small
startup/hydration coordinator, but do not move them until we decide the startup
shape.

### Compatibility Getters / Setters

Account and transaction state:

- `activeAccountId`
- `accounts`
- `transactionsByAccount`
- `allTransactions`
- `transactions`

Dashboard state:

- `totalBalance`
- `spentThisMonth`
- `incomeThisMonth`
- `availableThisMonth`
- `uncategorizedCount`
- `topCategories`
- `biggestLeaksThisMonth`
- `burnRunwayDays`
- `monthlyGroups`
- `spendReference`

Category and AI state:

- `categoryOverrides`
- `transactionCategoryAssignments`
- `aiCategorySuggestions`
- `merchantCategoryMemory`
- `customCategories`
- `categoryDisplayRenames`
- `categoriesHiddenFromPicker`

Most of these are delegates kept only where integration tests or workflow
coordination still use them directly.

### Cross-Feature Coordination

Dashboard refresh:

- `refreshAllState`
- `_syncDashboardAfterTransactionWorkflow`
- `_notifyDashboardAndBudgetsChanged`
- `_notifyCategoryCatalogChanged`
- `_notifyAccountsChanged`
- `_notifyTransactionDataChanged`
- `_notifyImportAiStatusChanged`

Transactions and CSV:

- moved to `TransactionWorkflowService`

Category / merchant learning:

- moved to `CategoryWorkflowService`

AI import:

- moved to `TransactionWorkflowService`

Budget / dashboard queries:

- `setActiveBudgetPeriod`
- `commitBudgetDraft`

Reset:

- `clear`

These are the main areas to shrink. They should move only one workflow at a
time.

## Phase 1 - Remove Stale AppState Comments

- [x] Update the top class comment so it says composition/root facade, not data
      owner.
- [x] Remove leftover `Rules feature removed` comments if they no longer help.
- [x] Fix the `effectiveSpendGroupLabel` comment that still mentions rules.
- [x] Reword `refreshAllState` from "single source of truth" to compatibility
      refresh delegate.

Why first: safest cleanup. No behavior change.

Completed: comments now describe `AppState` as a composition root /
compatibility facade. Removed stale rules notes and reworded refresh/category
comments without changing behavior.

## Phase 2 - Extract Startup Hydration Coordinator

- [x] Create a small coordinator only if it makes the code clearer.
- [x] Keep public hydration methods on `AppState` temporarily.
- [x] Move the hydration order knowledge out of `bootstrap()`.
- [x] Make one method responsible for startup hydration, for example
      `hydrateAppStateForStartup(appState)` or an `AppHydrationService`.
- [x] Preserve current order:
      budgets -> category catalog -> accounts -> transactions -> transaction
      assignments -> AI suggestions -> dedupe -> profile -> merchant memory.

Why next: startup is easy to reason about and has low UI risk.

Completed: added `lib/app/app_hydration.dart` with
`hydrateAppStateForStartup(appState)`. `bootstrap()` now creates `AppState` and
calls that single startup hydration function. Existing `AppState` hydration
methods remain public compatibility delegates.

## Phase 3 - Reduce UI Controller Dependence On Full AppState

- [x] Keep `AppUiDependencies` public shape unchanged.
- [x] Identify controller methods that can call services directly.
- [x] Start with read-only controller methods:
      `DashboardUiController.buildSnapshot`,
      `transactionsForDashboardScope`,
      `uncategorizedQueue`,
      `AccountUiController.buildSnapshotForAccount`,
      budget query methods.
- [x] Do not move mutation workflows yet.
- [x] Keep `AppState` as a fallback facade while controllers are converted.

Why next: this reduces the biggest remaining coupling without changing feature
behavior.

Completed: `AppUiDependencies` now builds controllers from explicit
`AppUiControllerBindings`. UI controllers no longer import, store, or depend on
the full `AppState` type. Read paths use services directly; mutation paths use
callbacks into the existing compatibility facade until later workflow phases.

## Phase 4 - Move Dashboard Refresh Facade

- [x] Keep `refreshAllState()` public on `AppState` temporarily.
- [x] Move the refresh wiring into a small dashboard refresh coordinator or into
      `DashboardService` if the dependencies stay reasonable.
- [x] Keep notifications in `AppState` until controllers no longer depend on it.
- [x] Remove duplicate recompute wiring between `refreshAllState` and
      `_syncDashboardAfterTransactionWorkflow` if possible.

Why next: many workflows depend on refresh. Clean this before CSV import.

Completed: added `lib/app/dashboard_refresh_coordinator.dart`.
Dashboard refresh and workflow recompute wiring now live in the coordinator.
`AppState` no longer exposes `refreshAllState()`; workflow services call the
coordinator directly while notification callbacks still originate from
`AppState`.

## Phase 5 - Reduce Test Dependence On AppState

- [x] Convert dashboard query tests to use domain/service helpers directly where
      practical.
- [x] Convert budget performance tests to use `BudgetService` /
      `DashboardService` where practical.
- [x] Keep integration tests that intentionally exercise full app coordination:
      CSV import, delete refresh, onboarding routing.
- [x] Avoid rewriting every test at once.

Why next: tests currently preserve the broad public API. Reducing test usage lets
us safely delete compatibility delegates later.

Completed: converted pure dashboard/query tests away from `AppState`:
`dashboard_queries_test.dart`, `budget_performance_scope_test.dart`, and
`transaction_resolution_alignment_test.dart`. The service-level
`transactionsForDashboardScope` test in `dashboard_scope_test.dart` now uses
`DashboardService` directly. Workflow/UI tests still use `AppState` where they
intentionally cover full app coordination.

## Phase 5b - Remove Moved AppState Query Delegates

- [x] Remove read/query delegates whose callers now use services/controllers.
- [x] Remove App UI bindings for read-only callbacks that can be computed from
      injected services.
- [x] Move dashboard refresh transaction resolution out of `AppState`.
- [x] Keep integration workflow methods that are still intentionally exercised
      through `AppState`.

Completed: removed `AppState` wrappers for transaction resolution, dashboard
scope queries, budget performance/spend queries, import AI status reads,
uncategorized queue reads, import batch reads, budget period key helpers, and
other moved read delegates. `AppUiDependencies` and
`DashboardRefreshCoordinator` now use their injected services directly for those
paths.

## Phase 6 - Move Remaining Category / Merchant Coordination

- [x] Review `applyCategoriesWithMerchantLearning`.
- [x] Review `_applyCategoryAssignments`.
- [x] Review `undoCategoryApplyBatch`.
- [x] Review `setCategoryOverride`.
- [x] Review `bulkSetCategoryOverrides`.
- [x] Review `createCategoryAndAssign`.
- [x] Review `deleteCategory`.
- [x] Review `renameCategory`.
- [x] Move only if the target service can own the workflow without depending on
      the whole app.

Why after tests: this area touches transactions, merchant memory, category
catalog, dashboard refresh, and persistence.

Completed: added `CategoryWorkflowService` for category assignment, merchant
learning, undo, create, delete, and rename coordination. `AppState` no longer
contains those workflow methods, and `TransactionUiController` now uses the
workflow service directly. Removed the old `CategoryService` workflow wrappers
so `CategoryService` keeps the lower-level category mutation helpers while the
new workflow service owns cross-service coordination.

## Phase 7 - Move CSV / Import Coordination

- [x] Review `loadFromCsv`.
- [x] Review `deleteTransaction`.
- [x] Review `clearTransactionsForAccount`.
- [x] Review `deleteTransactionsForImportBatch`.
- [x] Review `needsImportAiAfterCsvUpload`.
- [x] Review `startBackgroundImportAiCategorization`.
- [x] Review `autoCategorizeGlobalUncategorized`.
- [x] Decide whether this belongs in a transaction workflow coordinator before
      changing code.

Why late: CSV/import is the broadest workflow and easiest place to accidentally
rebuild the god object under another name.

Completed: added `TransactionWorkflowService` in the transactions application
layer for CSV import, transaction deletion, import batch deletion, import AI,
global AI categorization, and AI undo coordination. `AppState` no longer exposes
those workflow methods, UI controllers call the transaction workflow service
directly, and tests that still need integration behavior use
`state.transactionWorkflowService`. Removed the old transaction `*Workflow`
helpers from `TransactionService` so the coordination logic exists in one place.
`AppState` was 427 lines after Phase 7.

## Phase 8 - Remove Compatibility Delegates

- [x] Remove getters/setters that are no longer used by UI controllers or tests.
- [x] Keep service fields only if they are intentional composition-root access.
- [x] Keep `AppState` public methods only for app-shell/profile/startup or
      clearly documented temporary compatibility.
- [x] Re-run import searches after each removal.

Completed: removed the broad compatibility getter/setter facade for accounts,
transactions, dashboard derived fields, category state, AI suggestion state, and
merchant memory. Integration tests now read/write through feature services or
scoped UI snapshots instead of `AppState` delegates. `AppState` is now 294
lines and still owns startup hydration, profile/onboarding routing,
account/budget mutation callbacks, service composition, and refresh
coordination.

Target final shape:

- creates services
- exposes `ui`
- coordinates startup hydration
- owns only app-shell/profile routing state until auth replaces it
- has no feature business rules
- has no broad feature data ownership

## Verification After Each Phase

- [ ] `dart analyze`
- [ ] focused tests for touched area
- [ ] full `flutter test` after any behavior-affecting phase
- [ ] `git diff --check`

## Recommended First Implementation Step

Start with Phase 1 only. It is low risk, confirms the plan, and removes
misleading comments before deeper refactors.
