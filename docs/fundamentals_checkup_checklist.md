# Flutter/Dart Fundamentals Checkup Checklist

Use this checklist to review the project while learning how the app is built.
When we finish a step, mark it with `[x]` and add a short note if useful.

## Phase 1 - App Startup And Composition

- [x] Check `lib/main.dart`
- [x] Check `lib/app/bootstrap.dart`
- [x] Check `lib/app/app.dart`
- [x] Check `lib/app/app_state.dart`
- [x] Check `lib/app/ui_dependencies.dart`

Goal: understand how the app starts, what services are created, and how state
is passed into the UI.

Completed: app startup flows from `main()` to `bootstrap()`, then creates and
hydrates `AppState`, and finally renders `ClarityApp`. Feature UI receives
scoped controllers from `AppUiDependencies`.

## Phase 2 - Core Building Blocks

- [x] Check `lib/core/models/`
- [x] Check `lib/core/storage/`
- [x] Check `lib/core/formatting/`
- [x] Check `lib/core/constants/`
- [x] Confirm `core/` does not depend on feature UI

Goal: understand the shared models, storage helpers, formatting helpers, and
global constants.

Completed: `core/` contains shared models, storage adapters, formatting helpers,
IO helpers, and constants. It does not import feature UI or presentation code.

## Phase 3 - Feature Folder Structure

- [x] Check `lib/features/accounts/`
- [x] Check `lib/features/budgets/`
- [x] Check `lib/features/dashboard/`
- [x] Check `lib/features/categories/`
- [x] Check `lib/features/transactions/`
- [x] Check `lib/features/onboarding/`
- [x] Check `lib/features/shell/`

Goal: confirm each feature follows a clean structure:

- `presentation/` for screens and widgets
- `application/` for services and workflow logic
- `domain/` for pure business logic and models
- `data/` for repositories, parsing, storage, and external APIs

Completed: feature folders are broadly feature-first. Removed the empty
`rules` feature folder and moved the transaction category dropdown under
`transactions/presentation/widgets`. Remaining note: `budgets/application/
budget_performance.dart` may belong in `domain/` later.

## Phase 4 - State Management

- [x] Identify what `AppState` still owns
- [x] Identify what each UI controller owns
- [x] Check how dashboard screens listen for changes
- [x] Check how transaction screens listen for changes
- [x] Check how account screens listen for changes
- [x] Check how budget screens listen for changes
- [x] Confirm screens are not receiving full `AppState` unnecessarily

Goal: understand what causes the UI to rebuild and whether state is scoped to
the right feature.

Completed: `AppState` is still the composition root and compatibility facade,
but dashboard, transactions, accounts, budgets, and import AI status now rebuild
through scoped controllers in `AppUiDependencies`. `ClarityApp` still listens to
`AppState` for profile/onboarding routing, which is acceptable for now.

## Phase 5 - Data Flow Walkthroughs

- [x] Follow the "add account" flow
- [x] Follow the "import CSV" flow
- [x] Follow the "categorize transaction" flow
- [x] Follow the "delete transaction" flow
- [x] Follow the "save budget" flow
- [x] Follow the "dashboard refresh" flow

For each flow, trace:

```text
UI action
-> controller/view model
-> service
-> repository/storage
-> state update
-> UI refresh
```

Completed: feature screens call scoped controllers, controllers delegate through
`AppState`, services/repositories mutate data, then `AppState` refreshes scoped
UI controllers. The broadest remaining flow is CSV import because it still
coordinates accounts, transactions, dashboard aggregates, category catalog
persistence, and optional AI categorization follow-up.

## Phase 6 - Tests And Confidence

- [x] Check account tests
- [x] Check budget tests
- [x] Check dashboard tests
- [x] Check CSV/parser tests
- [x] Check transaction/category tests
- [x] Run `dart analyze`
- [x] Run focused tests for the feature being reviewed
- [x] Run full `flutter test`

Goal: learn what behavior is already protected and where test coverage is thin.

Completed: `dart analyze`, focused account/budget/dashboard/CSV/transaction
tests, and the full `flutter test` suite all pass. Coverage is strongest around
CSV parsing, dashboard scoping, budget refresh, transaction resolution, import
dedupe, and account upload UI. Cleanup note: debug CSV tests currently run as
normal tests, including one that depends on a local Downloads statement file on
this machine.

## Phase 7 - Notes And Cleanup Candidates

- [x] List confusing files or folders
- [x] List duplicated concepts
- [x] List places where naming is unclear
- [x] List places where UI knows too much about data logic
- [x] List places where services know too much about UI/state
- [x] Pick the next safest cleanup task

Goal: turn the review into small, safe follow-up improvements instead of a big
rewrite.

Completed: main cleanup candidates were:

- Stale docs referenced deleted `lib/screens/` paths and removed rules UI.
- Debug CSV tests ran in the normal test suite, including one that depended on a
  local Downloads statement file.
- `AppState` remains a compatibility facade behind scoped UI controllers.
- Several service callback names still said `notifyListeners`, even when the
  callback now triggers scoped controller refreshes.
- Budget repository comments described old `AppState` ownership.
- `OPENAI_API_KEY` is still read from app `.env`; this should move behind a
  backend/Supabase function before auth/API work.

Follow-up cleanup resolved the stale docs, guarded debug CSV tests, updated the
budget repository comment, and renamed obvious local refresh callbacks. Next:
make a small AppState cleanup plan, then clean CSV/import workflow, then plan
auth + Supabase + OpenAI API key together.
