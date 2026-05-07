# Debug checklist (manual sanity)

Use after imports, refactors, or when “counts feel wrong.”

Current CSV/AI product contract:
[`csv_import_ai_categorization.md`](csv_import_ai_categorization.md).

## Environment

- [ ] `.env` contains `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- [ ] Supabase has the `categorize-transactions` Edge Function deployed and
      the server-side `OPENAI_API_KEY` secret set if testing AI categorization.
- [ ] Supabase migrations have been applied with `supabase db push`.

## CSV Import + AI

- [ ] Select a CSV file and confirm progress appears immediately.
- [ ] Confirm progress moves through parsing, saving, AI categorization,
      applying categories, and refreshing.
- [ ] Confirm the import completes with no review queue or "transactions need
      attention" card.
- [ ] Confirm every newly inserted row has a category. If AI fails, rows should
      be assigned to `Unknown`.
- [ ] Confirm imported months include the full CSV date range, not only the
      newest 1000 rows.
- [ ] Confirm AI-created categories appear in category pickers after import.
- [ ] Delete a CSV upload from account detail and confirm only rows with that
      upload's `import_id` are deleted.

## Budgets

- [ ] Fresh users should not see stale imported categories in Budgets before
      upload.
- [ ] After upload, Budgets should show only categories that have transactions
      for the current budget period/scope.
- [ ] Empty categories should not appear by default.

## Manual Category Learning

- [ ] Manually change a merchant category.
- [ ] Confirm matching past transactions with the same or similar merchant are
      updated.
- [ ] Re-import a file with the same merchant pattern and confirm the learned
      category is reused.

## Month List Vs Detail

- [ ] Pick a month row with **N transactions** in the subtitle.
- [ ] Open detail and confirm the header and row list represent the same month
      group.

## Code-level quick grep (developers)

If debugging drift:

- Confirm no new call sites use global mutable state month groups for Overview
  month cards. Use snapshot data for the active dashboard scope.
- Confirm no user-facing review queue has been reintroduced.
- Confirm no app-data path uses SharedPreferences.

## Automated tests

Run:

```bash
flutter test
```
