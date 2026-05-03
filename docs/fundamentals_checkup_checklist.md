# Flutter/Dart Fundamentals Checkup Checklist

Use this checklist to review the project while learning how the app is built.
When we finish a step, mark it with `[x]` and add a short note if useful.

## Phase 1 - App Startup And Composition

- [x] Check `lib/main.dart`
- [x] Check `lib/app/bootstrap.dart`
- [x] Check `lib/app/app.dart`
- [x] Check `lib/app/app_composition.dart`
- [x] Check `lib/app/ui_dependencies.dart`

Goal: understand how the app starts, what services are created, and how state
is passed into the UI.

Completed: app startup flows from `main()` to `bootstrap()`, loads `.env`,
initializes Supabase, creates `AppComposition`, hydrates startup/profile state,
and finally renders `ClarityApp`. Feature UI receives scoped controllers from
`AppUiDependencies`.

## Phase 2 - Core Building Blocks

- [x] Check `lib/core/models/`
- [x] Check `lib/core/storage/`
- [x] Check `lib/core/formatting/`
- [x] Check `lib/core/constants/`
- [x] Confirm `core/` does not depend on feature UI

Goal: understand the shared models, storage helpers, formatting helpers, and
global constants.

Completed: `core/` contains shared models, Supabase boundaries, formatting
helpers, IO helpers, and some legacy storage adapters. It does not import
feature UI or presentation code. Legacy storage adapters are temporary cleanup
candidates, not the authoritative data path for Supabase tables.

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

- [x] Identify what `AppComposition` owns
- [x] Identify what each UI controller owns
- [x] Check how dashboard screens listen for changes
- [x] Check how transaction screens listen for changes
- [x] Check how account screens listen for changes
- [x] Check how budget screens listen for changes
- [x] Confirm screens are not receiving broad app composition objects unnecessarily

Goal: understand what causes the UI to rebuild and whether state is scoped to
the right feature.

Completed: `AppComposition` is the composition root. Dashboard, transactions,
accounts, budgets, and import AI status rebuild through scoped controllers in
`AppUiDependencies`. `ClarityApp` listens to `AuthController` and
`ProfileController` for auth/profile routing.

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
-> workflow/service
-> Supabase table service or pure domain helper
-> scoped notification/listenable
-> UI refresh
```

Completed: feature screens call scoped controllers, controllers delegate to
workflow/table services, Supabase services mutate remote data, then app-level
notifications refresh scoped UI controllers. The broadest remaining flow is CSV
import because it coordinates accounts, transactions, dashboard aggregates,
category catalog compatibility state, and optional AI categorization follow-up.

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

Completed: `flutter analyze` and full `flutter test` pass. Current baseline
coverage includes CSV parsing, OpenAI proxy payload behavior, and auth/profile
routing. Supabase table-service behavior still needs local-Supabase integration
tests.

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
- `AppState` has been deleted; `AppComposition` is now the composition root.
- Several service callback names still said `notifyListeners`, even when the
  callback now triggers scoped controller refreshes.
- Budget repository comments described old ownership.
- `OPENAI_API_KEY` now belongs behind the Supabase Edge Function; Flutter `.env`
  should only contain public Supabase client config.

Follow-up cleanup resolved the stale docs, guarded debug CSV tests, updated the
budget repository comment, and renamed obvious local refresh callbacks. Next:
continue replacing local compatibility helpers, then verify auth + Supabase +
secure AI proxy behavior.
