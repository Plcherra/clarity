# Category rules v1 (auto-categorization from description)

## Problem

Manual `categoryOverrides` are keyed per transaction (`transactionCategoryKey`). Assigning one row does not help the next import or sibling rows with the same merchant text.

## Approach

Evaluate **persisted user rules** inside the same decision path as today’s effective category (conceptually: one central API wrapping what `spendGroupLabel` does), **without** materializing matches into `categoryOverrides`.

## Locked v1 policies

### Rule ordering

- **List order wins:** iterate rules in list order; **first match** applies.
- **New rules append** to the end of the list (deterministic, easy to explain).
- Do **not** rely on `createdAt` for match precedence (timestamp may still be stored for future UI / debugging).

### Duplicate patterns

- Rules are **unique by normalized pattern** (after `normalizeDescriptionForMatching` on the pattern string only, or equivalent single normalizer for patterns).
- Saving a rule whose pattern already exists **updates** that rule’s target category (and optionally `createdAt` / `id` policy: keep stable `id` on update, or document replace-in-place).

### Pattern validation

- **Minimum length 3** characters after trim/normalization.
- Reject empty or too-short patterns in the “Save rule?” dialog (and in `AppState` mutation guard).

### Income / outflow

- **Rules apply only to spending (outflow) rows:** `Transaction.isOutflow` / `amount < 0` (align with existing `isOutflow` on `Transaction`).
- **Skip rule matching** for non-outflow (income, credits, etc.) so Zelle/Venmo-style descriptions on incoming money do not get spend categories by accident.
- Document: manual override can still categorize any row; this gate is **rules only**.

### Precedence (unchanged from prior plan, now explicit)

1. **Manual** `categoryOverrides[transactionCategoryKey(t)]` if set and non-empty — always wins.
2. **First matching user rule** (outflow-only, normalized description `contains` normalized pattern).
3. **Existing built-in logic** (`spendGroupLabel` remainder: income handling, CSV category, `suggestCategoryFromDescription`, etc.).

### Central API (required)

- Do **not** thread `categoryRules` through every call site by hand long-term.
- Add **one** entry point, e.g. on `AppState`:

  - `String effectiveSpendGroupLabel(Transaction t)`  
    (name can vary; must be the single door for “effective category before display renames” if that’s how call sites work today.)

- Internally it composes: overrides → rules → rest of `spendGroupLabel` logic (either by calling a refactored internal function or inlining the ordered steps once).
- **Refactor all current `spendGroupLabel` usages** that need app state to go through this API (or a thin static helper that takes `overrides + rules + t` if some layers stay pure).

### Normalization

- One helper: **`normalizeDescriptionForMatching(String s)`** — trim, lowercase, collapse internal whitespace to a single space.
- Apply to **both** transaction description and stored pattern before `contains`.

### “Save rule?” dialog — pattern suggestion (humble v1)

- Prefill **editable** text; do not over-fit bank noise.
- Acceptable v1 heuristics: first **1–3 meaningful tokens**, or a tiny strip of known boilerplate prefixes — **must remain editable**.
- Examples to sanity-check in QA: `NERO CAMBRIDGE` → `nero`; long Pearl St strings → `pearl st market`; ATM/withdrwl lines → user often must edit — that is OK.

## Data model

- `id` (stable; on “update by pattern” keep same `id` if practical)
- `pattern` — stored **normalized** (or raw + normalize on read; pick one and document)
- `matchType` — v1: `'contains'` only
- `categoryCanonical` — picker canonical string (same as today’s override target)
- `createdAt` — optional metadata; **not** used for match order

## Persistence

- Separate prefs key (e.g. `category_rules_v1`), JSON list.
- **Not** cleared on `loadFromCsv`; **not** cleared with `categoryOverrides` reset.
- **`clear()`:** keep rules (same intent as budgets) unless product later adds “factory reset.”

## Bootstrap

- Hydrate rules alongside budgets in `main()` (`ensureInitialized` → `AppState` → await hydrations → `runApp`).

## UX

- After successful manual category pick in [`lib/widgets/transaction_category_dropdown.dart`](lib/widgets/transaction_category_dropdown.dart): optional dialog **“Save a rule for similar transactions?”** with editable pattern + Save / Not now.
- Same affordance after `createCategoryAndAssign` when appropriate.

## Implementation order

1. `CategoryRule` model + `normalizeDescriptionForMatching`
2. Storage helper (load/save JSON)
3. `AppState`: field, hydrate, `addOrUpdateRuleByPattern` (enforce unique pattern + min length), persist
4. **Central** `effectiveSpendGroupLabel` (or chosen name) composing override → rules → existing logic
5. Refactor all call sites to use the central API (no stray `spendGroupLabel(..., rules: …)` drift)
6. Post-assign “Save rule?” dialog
7. QA: repeated merchants, re-import, income rows untouched by rules, override still wins

## QA checklist

- Rule applies to many rows + future import without prefs override explosion
- Duplicate pattern save updates category, does not duplicate
- Pattern length &lt; 3 rejected
- Income / inflow row: rule does not apply; manual override still can
- Manual override on one row beats rule for that row
- Deleting a rule (future) or clearing: document v1 if delete is deferred
