# Debug checklist (manual sanity)

Use after imports, refactors, or when “counts feel wrong.”

## Environment

- [ ] `.env` contains `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- [ ] Supabase has the `call-openai` Edge Function deployed and the server-side `OPENAI_API_KEY` secret set if testing AI categorization.
- [ ] Supabase migrations have been applied with `supabase db push`.

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

## Import + AI (optional)

- [ ] Import CSV while signed in — rows appear for the selected account and
      dashboard totals refresh.
- [ ] Delete a CSV upload from account detail — only rows with that upload's
      `import_id` are deleted.
- [ ] AI after import currently shows a temporary disabled message until
      category assignments are fully Supabase-backed.

## Code-level quick grep (developers)

If debugging drift:

- Confirm no new call sites use global mutable state month groups for
  **Overview** month cards or review. Use snapshot /
  `transactionsForDashboardScope` instead.
- Confirm **`TransactionReviewScreen`** receives the same **`scope`** as the parent **`FinancialDashboardView`**.

## Automated tests

Run:

```bash
flutter test
```
