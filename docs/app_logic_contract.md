# App Logic Contract

Short source of truth for data flow and categorization. If behavior diverges
from this file, fix the code or update this doc in the same change.

## 1. Where Transactions Live

- Authoritative store: Supabase `public.transactions`, accessed through
  [`TransactionService`](../lib/features/transactions/application/transaction_service.dart).
- Account-scoped rows: `TransactionService.fetchTransactions(accountId: id)`.
- Global rows: `TransactionService.fetchTransactions()` for the authenticated
  user.

Imports append into the relevant account with dedupe semantics from
[`TransactionWorkflowService`](../lib/features/transactions/application/transaction_workflow_service.dart).
CSV upload history and batch deletion use `transactions.import_id`.

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
- `uncategorizedTransactionsForDashboardScope` is the single list for the red
  needs-attention banner count and transaction review queue.
- `uncategorizedCountForDashboardScope` is
  `uncategorizedTransactionsForDashboardScope(...).length`.

The shared grouping primitive lives in
[`bank_statement_monthly.dart`](../lib/features/transactions/domain/bank_statement_monthly.dart).

## 4. Snapshot Vs Controller Data

- Cards, banner counts, statement-by-month rows, and dashboard review entry:
  use `buildDashboardSnapshot(...)` with `scopedTransactions` from
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
4. Merchant memory via `merchantCategoryMemory[transactionMerchantKeyLower(t)]`.
5. Built-in keyword suggestion from `suggestCategoryFromDescription`.
6. CSV category from `transaction.category`; if it is `uncategorized` or
   `other`, substitute the keyword suggestion.

Display-only layer: `spendGroupLabelForDisplay` =
`spendGroupLabel` + `applyCategoryDisplayRenames`. Anything that checks whether
a row is Uncategorized for UI/review counts should use the display label unless
pre-rename logic is intentional.

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

## 7. Needs Attention / Uncategorized

A row counts toward needs attention when:

1. It passes bank statement row filters from
   [`isBankStatementDataRow`](../lib/features/transactions/domain/bank_statement_monthly.dart).
2. Display category after renames equals `Uncategorized` case-insensitively.

The dashboard banner and transaction review queue must use the same
`DashboardScope` and uncategorized helper.

AI import is a separate path. Suggestions are pending until the user saves; saved
picks should flow through category assignments like any other categorization.
AI suggestions can be prefilled from merchant memory, and GPT is only called for
rows not already covered by merchant memory.

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

If you add spent-vs-budget indicators, align spend with the same dashboard scope
shown beside it, usually global Overview for category totals.

## Rule Of Thumb

One `DashboardScope`, one `transactionsForDashboardScope`, one
`buildDashboardSnapshot` for that scope. Reuse the same scoped data for review
and month drill-down.
