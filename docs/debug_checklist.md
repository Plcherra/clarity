# Debug checklist (manual sanity)

Use after imports, refactors, or when “counts feel wrong.”

## Environment

- [ ] `.env` contains `OPENAI_API_KEY` if testing AI flow (empty key → dialog should say to add key; see account/import flows).

## Debug build (inline line)

- [ ] On **Overview** in a **debug** build, the small `debug: reviewQueue=… · snapUncat=…` line under the title should match (`reviewQueue` is the banner/review source of truth; `snapUncat` is the snapshot field — if they diverge, investigate).

## Global Overview

- [ ] Note **uncategorized** number on dashboard attention card (from `buildDashboardSnapshot`, global scope).
- [ ] Tap through to **Review** — queue length should match that number (same `DashboardScope` + `uncategorizedBankStatementLines`).
- [ ] Change one category; return to Overview — count should drop unless row still resolves to Uncategorized.

## Month list vs detail

- [ ] Pick a month row with **N transactions** in the subtitle.
- [ ] Open detail — header should show **N transactions** and **N** line rows (same `MonthlyBankGroup`).

## Account vs global

- [ ] With **two accounts** and uncategorized only on the **non-active** account: Overview (global) should still show needs attention **> 0**; switching to **account-scoped** dashboard for empty account should show **0** for that account’s scope.

## Rules

- [ ] Open **Manage rules** — count matches persisted rules (e.g. after adding/removing one, count updates on return).

## Import + AI (optional)

- [ ] Import CSV with key present — AI flow opens when wired; accepting suggestions updates categories visible on dashboard/review.

## Code-level quick grep (developers)

If debugging drift:

- Confirm no new call sites use **`appState.monthlyGroups`** for **Overview** month cards or review (use snapshot / `transactionsForDashboardScope` instead).
- Confirm **`TransactionReviewScreen`** receives the same **`scope`** as the parent **`FinancialDashboardView`**.

## Automated tests

Run:

```bash
flutter test test/dashboard_scope_test.dart
```

Full suite: `flutter test`.
