# CSV Import And AI Categorization

This is the product and engineering source of truth for CSV import,
automatic AI categorization, category creation, budget category visibility, and
merchant-learning behavior.

If code behavior diverges from this document, update the code or update this
document in the same change.

## Product Principle

CSV import should require near-zero effort from the user.

The user chooses an account and selects a CSV file. After that, Clarity owns the
whole workflow:

1. Parse the CSV.
2. Save all non-duplicate transactions.
3. Categorize every imported transaction with AI.
4. Create missing categories when the AI needs them.
5. Apply categories to transactions in Supabase.
6. Refresh dashboard, account, transaction, and budget views.

The user should not need to review a queue after import. Manual correction is
still supported, but it happens after the app has already done the best
automatic categorization it can.

## User Experience Contract

### Upload Flow

The upload experience must be one continuous job:

| Stage | User-facing behavior |
|-------|----------------------|
| Parsing | Progress starts immediately after file selection. |
| Saving transactions | UI explains that transactions are being imported. |
| Categorizing with AI | UI explains that AI is categorizing transactions. |
| Applying categories | UI explains that categories are being saved. |
| Refreshing | Dashboard and budget data refresh before the job finishes. |
| Complete | The user lands on updated financial data. |
| Failed | A persistent error explains what failed and what was saved. |

The progress UI should not feel like separate upload and AI tasks. It should be
one import job with clear status text.

### Review Queue

There is no user-facing "transactions need attention" or mandatory review queue
for the normal CSV import flow.

Every newly inserted transaction must end the import job with a category:

- an AI-selected category
- a learned merchant category
- or `Unknown` if AI fails or cannot produce a valid category

`Unknown` is a real per-user Supabase category row, not a local placeholder.

## Data Ownership

Supabase is the only source of truth for imported financial data.

| Data | Supabase source |
|------|-----------------|
| Accounts | `accounts` |
| Transactions | `transactions` |
| Category rows | `categories` |
| Transaction category assignment | `transactions.category_id` |
| Budget rows | `budgets` |
| CSV upload grouping | `transactions.import_id` |
| Future merchant learning | Supabase table, not local storage |

CSV parsing can remain local in Dart, but persisted app data must be written
through Supabase-backed services.

## AI Categorization Contract

The Flutter app should make one categorization request for one import job. The
Supabase Edge Function can split a large import internally into smaller OpenAI
requests, then merge the results into one response.

For a large CSV, such as about 1500 transactions, the Edge Function should chunk
internally. Flutter should not fetch only the newest 1000 rows or lose older
months due to pagination limits.

The categorization response should map each inserted transaction to a category
name:

```json
{
  "suggestions": [
    {
      "key": "transaction-id",
      "categoryName": "Food & Drink"
    }
  ]
}
```

Rules:

- AI may create new category names on the user's first upload.
- Returned categories must be normalized before saving.
- Missing, empty, invalid, or duplicate suggestions fall back to `Unknown`.
- AI failure does not roll back saved transactions.
- Imported rows must remain queryable even when categorization fails.

## Category Creation

Built-in categories can remain static app constants, but the AI is allowed to
create user-owned Supabase categories when the default list is not enough.

Category creation rules:

- Category names are scoped to the authenticated user.
- The app should avoid creating duplicates that differ only by case or spacing.
- New categories created during import should immediately be usable anywhere a
category can be selected.
- Category assignment should be applied with grouped Supabase updates, not one
transaction at a time.

## Budget Page Contract

The Budget page should show categories that actually have transaction activity.

Required behavior:

- Before the user's first import, the Budget page should not show stale or empty
  imported categories.
- After import, categories assigned by AI should appear automatically in the
  Budget page when they have matching transactions.
- Empty categories should not be shown by default.
- The Budget page should use Supabase transactions and categories for the
  authenticated user only.
- Existing budget rows can still exist for previously configured categories,
  but the default category list should be activity-driven.

This means the Budget page must not be driven by a full static category list or
old local category catalog state.

## Manual Correction And Merchant Learning

When a user manually corrects a transaction category, Clarity should learn that
merchant pattern and apply it broadly.

Example:

If the user changes a Dunkin transaction to `Coffee`, the system should update
past and future matching merchants such as:

- `Dunkin`
- `DD`
- `Dunkin Donuts`
- `Dunkin' Donuts`

Required behavior:

1. Normalize the merchant name.
2. Store the learned mapping in Supabase.
3. Update matching past transactions for the authenticated user.
4. Apply the learned category automatically to future imports.
5. Prefer the learned merchant category over a fresh AI guess.

The matching system should support exact normalized names first, then explicit
aliases or similarity rules. It should not rely on local storage.

Suggested future table shape:

```sql
merchant_category_memory (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  merchant_normalized text not null,
  merchant_aliases text[] not null default '{}',
  category_id uuid references public.categories(id) on delete set null,
  confidence numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, merchant_normalized)
)
```

## Error Handling

CSV parse, account validation, or transaction save failure should stop the
import and show a persistent failure state.

AI failure should not stop the transaction import. Instead:

- saved transactions remain saved
- all newly inserted rows receive `Unknown`
- the final result records `aiSucceeded = false`
- the error message remains visible long enough to read

The user should never be left wondering whether a file is still importing,
whether AI is still running, or whether data was partially saved.

## Acceptance Criteria

Use these checks before considering the feature complete:

- A fresh user can upload a CSV with no prior local data.
- The provided large CSV parses all rows, including older months.
- Imports over 1000 rows do not drop older transactions.
- All newly inserted transactions end with a non-null `category_id`.
- AI-created categories appear in category selectors after import.
- The Budget page shows only categories with transactions for the relevant
  period/scope.
- No "transactions need attention" queue appears after successful import.
- Manual category correction updates matching past transactions.
- A future import uses learned merchant mappings before or instead of AI.
- If AI fails, transactions are saved and assigned to `Unknown`.

## Developer Notes

- Keep the public import flow simple. Prefer one high-level import service over
  UI code coordinating parsing, saving, AI, and category updates separately.
- Keep pagination explicit anywhere existing transactions are fetched for
  duplicate detection or dashboard refresh.
- Keep OpenAI secrets only in Supabase Edge Function secrets.
- Do not reintroduce SharedPreferences for categories, merchant memory, AI
  suggestions, transaction overrides, or import tracking.
- Historical manual test reports can describe old failures, but this document
  defines the current target behavior.
