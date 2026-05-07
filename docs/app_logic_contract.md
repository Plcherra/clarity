# App Logic Contract

Short source of truth for data flow and categorization. If behavior diverges
from this file, fix the code or update this doc in the same change.

CSV import, automatic AI categorization, Budget category visibility, and
merchant learning are defined in
[`csv_import_ai_categorization.md`](csv_import_ai_categorization.md).

## 1. Where Transactions Live

- Authoritative store: Supabase `public.transactions`, accessed through
  [`TransactionService`](../lib/features/transactions/data/transaction_service.dart).
- Account-scoped rows: `TransactionService.fetchTransactions(accountId: id)`.
- Global rows: `TransactionService.fetchTransactions()` for the authenticated
  user.

Imports append non-duplicate rows into the relevant account. CSV upload history
and batch deletion use `transactions.import_id`.

## 2. Dashboard Scope

Scope is explicit via
[`DashboardScope`](../lib/features/dashboard/domain/dashboard_snapshot.dart):

| Scope | Transaction list |
|-------|------------------|
| `GlobalDashboardScope` | All authenticated user's transaction rows |
| `AccountDashboardScope(accountId)` | Rows filtered by `account_id` |

Single helper:
[`DashboardService.transactionsForDashboardScope`](../lib/features/dashboard/application/dashboard_service.dart).
Every screen that shows dashboard data should use the same scope as its parent
[`FinancialDashboardView`](../lib/features/dashboard/presentation/financial_dashboard_view.dart)
or [`DashboardScreen`](../lib/features/dashboard/presentation/dashboard_screen.dart).

Overview uses `GlobalDashboardScope`. Account detail uses
`AccountDashboardScope` for that account.

## 3. Central Query Helpers

Prefer
[`dashboard_queries.dart`](../lib/features/dashboard/domain/dashboard_queries.dart)
when you need counts or month groups without building a full snapshot:

- `monthlyGroupsForDashboardScope` matches `DashboardSnapshot.monthlyGroups`
  for the same scope and state maps.
- Uncategorized helpers can still be useful for diagnostics or fallback
  categorization, but they must not reintroduce a user-facing review queue.

The shared grouping primitive lives in
[`bank_statement_monthly.dart`](../lib/features/transactions/domain/bank_statement_monthly.dart).

## 4. Snapshot Vs Controller Data

- Cards and statement-by-month rows use `buildDashboardSnapshot(...)` with
  `scopedTransactions` from
  `transactionsForDashboardScope(scope)`.
- Derived dashboard values are managed by
  [`DashboardService`](../lib/features/dashboard/application/dashboard_service.dart)
  and snapshot helpers.
- Use `DashboardSnapshot.monthlyGroups` for dashboard month cards and month
  detail navigation.

## 5. Effective Category

Resolution order for `spendGroupLabel`
([`spend_categories.dart`](../lib/features/transactions/domain/spend_categories.dart)):

1. `transaction.categoryId` if non-empty.
2. Manual override via `categoryOverrides[transactionCategoryKey(t)]`.
3. Returned/reversed/NSF-style descriptions -> `Ignored`.
4. Supabase-backed learned merchant mapping when implemented.
5. Built-in keyword suggestion from `suggestCategoryFromDescription`.
6. CSV category from `transaction.category`; if it is `uncategorized` or
   `other`, substitute the keyword suggestion.

Display-only layer: `spendGroupLabelForDisplay` =
`spendGroupLabel` + `applyCategoryDisplayRenames`.

Application services and UI controllers should call
transaction resolution helpers directly instead of adding app-level query
wrappers.

## 6. Central Transaction Resolution

All screens and metrics should resolve transactions through
[`transaction_resolution.dart`](../lib/features/transactions/domain/transaction_resolution.dart),
which produces a `ResolvedTransaction`:

- `canonicalCategory`
- `displayCategory`
- `financialRole`
- `countsAsSpend`
- `countsAsIncome`
- `needsCategorization`

Avoid new dashboard math from raw `Transaction.amount` sign plus category
strings. Prefer `ResolvedTransaction` or helpers built on it.

## 7. Import Categorization

CSV import should categorize all inserted rows automatically. The normal import
flow must not create a required review queue. If AI fails, inserted rows remain
saved and receive the fallback `Unknown` category.

Manual category corrections should eventually update learned merchant mappings
in Supabase and backfill matching past transactions.

## 8. Month List And Month Detail

- Dashboard month rows come from `DashboardSnapshot.monthlyGroups`.
- [`MonthDetailScreen`](../lib/features/dashboard/presentation/month_detail_screen.dart)
  receives the tapped `MonthlyBankGroup`; it must not re-lookup by month key in
  separate global state for Overview.

## 9. Money Metrics

Spend, income, top categories, and leaks in the snapshot use scoped
transactions for the reference month, resolved through `ResolvedTransaction`.
Role resolution still uses global `allTransactions` context for internal
payment matching.

Ignored categories and role-based exclusions prevent rows from polluting expense
and income metrics where implemented in
[`buildDashboardSnapshot`](../lib/features/dashboard/domain/dashboard_snapshot.dart).

## 10. Budgets

[`BudgetsScreen`](../lib/features/budgets/presentation/budgets_screen.dart)
uses [`BudgetUiController`](../lib/app/ui_dependencies.dart), which delegates to
Supabase-backed `BudgetService` and `BudgetWorkflowService`.

Budget amounts are keyed by normalized display label for monthly, weekly, and
custom periods. The current database stores one row per user/category display
label, period, and period start date.

Budget category choices should be activity-driven. The Budget page should show
categories that have transactions for the relevant period/scope, plus any
existing budget rows needed for continuity, rather than a full empty static
category list.

If you add spent-vs-budget indicators, align spend with the same dashboard scope
shown beside it, usually global Overview for category totals.

## Rule Of Thumb

One `DashboardScope`, one `transactionsForDashboardScope`, one
`buildDashboardSnapshot` for that scope. Reuse the same scoped data for review
and month drill-down.
