# App logic contract (Clarity)

Short source of truth for data flow and categorization. **If behavior diverges from this file, fix the code or update this doc in the same change.**

## 1. Where transactions live

- **Authoritative store:** `AppState.transactionsByAccount` — map of account id → list of `Transaction`.
- **Active account slice:** `AppState.transactions` is the list for `activeAccountId` (convenience for account-scoped flows and CSV import targeting).
- **All rows:** `AppState.allTransactions` aggregates every account’s list for global metrics and matching (e.g. internal payment / financial role resolution).

Imports append into the relevant account (with dedupe semantics as implemented in `AppState`); this doc does not restate file formats.

## 2. Dashboard scope

Scope is explicit via [`DashboardScope`](../lib/dashboard_snapshot.dart):

| Scope | Transaction list |
|--------|------------------|
| `GlobalDashboardScope` | All imported rows: `allTransactions` |
| `AccountDashboardScope(accountId)` | `transactionsByAccount[accountId] ?? []` |

**Single helper:** [`AppState.transactionsForDashboardScope`](../lib/app_state.dart) — every screen that shows “for this dashboard” must use this for the same `scope` as the parent [`FinancialDashboardView`](../lib/screens/financial_dashboard_view.dart) / [`DashboardScreen`](../lib/screens/dashboard_screen.dart).

**Overview** uses `GlobalDashboardScope`. **Account detail** uses `AccountDashboardScope` for that account.

### 2b. Central query helpers ([`dashboard_queries.dart`](../lib/dashboard_queries.dart))

Prefer these when you need counts or month groups **without** building a full snapshot:

- **`monthlyGroupsForDashboardScope`** — matches [`DashboardSnapshot.monthlyGroups`](../lib/dashboard_snapshot.dart) for the same scope and state maps.
- **`uncategorizedTransactionsForDashboardScope`** — **single list** for the red “needs attention” banner count (`.length`) and [`TransactionReviewScreen`](../lib/screens/transaction_review_screen.dart). Do not use [`DashboardSnapshot.uncategorizedCount`](../lib/dashboard_snapshot.dart) for the banner (kept for other metrics / comparison in debug builds only).
- **`uncategorizedCountForDashboardScope`** — `uncategorizedTransactionsForDashboardScope(…).length` (same single source).

[`monthlyBankGroupsNewestFirstForScopedTransactions`](../lib/dashboard_snapshot.dart) is the shared primitive used by `buildDashboardSnapshot` and the query helper.

## 3. Snapshot vs `AppState` fields

- **Cards, banner counts, “Statement by month”, review entry from the dashboard:** Use [`buildDashboardSnapshot(...)`](../lib/dashboard_snapshot.dart) with `scopedTransactions:` from `transactionsForDashboardScope(scope)` — same scope as the UI.
- **`AppState.uncategorizedCount`, spend/income/leaks/top categories in `AppState`:** Computed in `_recomputeDerived` from **`allTransactionsForMetrics`** (all accounts), so they align with **global** totals, not the active account alone.
- **`AppState.monthlyGroups`:** Still built from **`activeAccountTransactions` only** (statement-style grouped months for the active account). **Do not** use it for Overview / global snapshot UI; use **`DashboardSnapshot.monthlyGroups`** from `buildDashboardSnapshot` for scoped dashboard views.

## 4. Effective category (canonical label)

Resolution order for **`spendGroupLabel`** ([`spend_categories.dart`](../lib/spend_categories.dart)) — used for logic, spend buckets, and rules:

1. **`transaction.categoryId`** (user-saved canonical category) if non-empty.
2. **Manual override** via `categoryOverrides[transactionCategoryKey(t)]`.
3. **Returned/reversed/NSF-style descriptions** → `Ignored` (dropped from normal spend charts per rules).
4. **First matching user `CategoryRule`** (outflows first; special case for inflow + income-from-keywords).
5. **`suggestCategoryFromDescription`** (built-in keywords) — may return an income label that overrides weaker CSV labels below.
6. **Inflow path:** Additional rule pass for non-outflows if needed.
7. **`transaction.category`** from CSV: if `uncategorized` / `other`, substitute keyword suggestion; else use raw CSV category.

**Display-only layer:** `spendGroupLabelForDisplay` = `spendGroupLabel` + `applyCategoryDisplayRenames`. Anything that checks “is this Uncategorized?” for **UI/review counts** should use the **display** label unless you intentionally want pre-rename logic.

**Central API on state:** [`AppState.effectiveSpendGroupLabel`](../lib/app_state.dart) delegates to `spendGroupLabel` with app maps/rules — prefer this when reasoning about “what category did we assign?”

**Display line for UI / Uncategorized checks:** [`AppState.effectiveCategoryDisplayLabel`](../lib/app_state.dart) — `spendGroupLabelForDisplay` with app maps (includes display renames).

## 4b. Central transaction resolution (single source)

All screens and metrics should resolve transactions via [`transaction_resolution.dart`](../lib/transaction_resolution.dart), which produces a `ResolvedTransaction`:

- `canonicalCategory` (exact `spendGroupLabel` output)
- `displayCategory` (canonical + `applyCategoryDisplayRenames`)
- `financialRole` (exact `effectiveFinancialRole` output, with global `allTransactions` context when needed)
- Inclusion flags used by consumers:
  - `countsAsSpend`
  - `countsAsIncome`
  - `needsCategorization`

Avoid new direct dashboard math from raw `t.amount` sign + category strings; prefer `ResolvedTransaction` or helpers built on it.

## 5. What “needs attention” / uncategorized means

A row counts toward **needs attention** when:

1. It passes **bank statement row** filters ([`isBankStatementDataRow`](../lib/bank_statement_monthly.dart) — drops empty, invalid amounts, summary/balance boilerplate descriptions).
2. **Display** category after renames equals **`Uncategorized`** (case-insensitive): `ResolvedTransaction.needsCategorization` (and any count should come from `.where((r) => r.needsCategorization)`).

**Review queue** for the in-app flow: [`uncategorizedBankStatementLines`](../lib/bank_statement_monthly.dart) on **`transactionsForDashboardScope(scope)`** with the same override/rename/rule maps — must match the banner for that **same `DashboardScope`**.

**AI import flow** (`AiCategorizationFlowScreen`): separate path; uses uncategorized **import** helpers where applicable — suggestions are not final until the user saves; saved picks should flow through `categoryId` / overrides like any other categorization.

## 6. Month list and month detail

- **Month rows** on the dashboard: counts and totals come from **`DashboardSnapshot.monthlyGroups`** (from `buildDashboardSnapshot`, which uses [`monthlyGroupsFromTransactions`](../lib/bank_statement_monthly.dart) on **scoped** transactions).
- **Month detail:** [`MonthDetailScreen`](../lib/screens/month_detail_screen.dart) takes a **`MonthlyBankGroup` passed from the tapped row** — it must **not** re-lookup month keys in `AppState.monthlyGroups` for Overview. The group’s `transactions` are the exact lines shown.

## 7. Money metrics (high level)

- **Spend / income / top categories / leaks** in the snapshot use **`scopedTransactions`** for the reference month, resolved through `ResolvedTransaction` (role resolution still uses global `allTransactions` for internal-payment matching).
- **Ignored** categories (and role-based exclusions) prevent lines from polluting expense/income where implemented in [`buildDashboardSnapshot`](../lib/dashboard_snapshot.dart).

## Budgets ([`BudgetsScreen`](../lib/screens/budgets_screen.dart))

- **Storage:** [`AppState.categoryMonthlyBudgetsByDisplayLower`](../lib/app_state.dart) — monthly caps keyed by **display** label (after renames). This is **global** user intent, not per-account.
- **Comparison:** If you add “spent vs budget” indicators, align **spend** with the same **dashboard scope** you show alongside (typically global Overview for a category total).

---

**Rule of thumb:** One **`DashboardScope`**, one **`transactionsForDashboardScope`**, one **`buildDashboardSnapshot`** for that scope — then reuse the same snapshot lines for review and month drill-down. Anything else is a footgun.
