---
name: Keyword list refactor
overview: Refactor `suggestCategoryFromDescription` in [lib/spend_categories.dart](lib/spend_categories.dart) to use `const List<String>` keyword lists and a small private helper, preserving exact precedence (Zelle, credit card, Uber vs Uber Eats), and merge in US-general keyword expansions (Food chains, Shopping, Subscriptions, Transfer Out remittance).
todos:
  - id: add-lists-helper
    content: Add const keyword lists + _haystackContainsAny in spend_categories.dart
    status: completed
  - id: us-keywords
    content: Fold in expanded Food block, temu/shein/fragrancenet, suno/landr, remitly/verso per addendum
    status: completed
  - id: rewrite-suggest
    content: Rewrite suggestCategoryFromDescription to use lists + preserve order/special cases
    status: completed
  - id: verify-tests
    content: Run flutter test
    status: completed
isProject: false
---

# Refactor categorization keywords into const lists

## Goal

Keep **all logic in [lib/spend_categories.dart](lib/spend_categories.dart)** (no new files). Replace long `has('a') || has('b')` chains with **named const lists** and a tiny helper so adding keywords is a one-line edit to a list.

## Helper

Add a private function (top-level, next to other `bool` helpers after the new const lists), e.g.:

```dart
bool _haystackContainsAny(String haystackLower, List<String> needles) {
  for (final n in needles) {
    if (haystackLower.contains(n)) return true;
  }
  return false;
}
```

`needles` must stay **lowercase** (current `has()` contract). `suggestCategoryFromDescription` keeps `final h = description.toLowerCase();` and passes `h` into the helper.

## Const lists (grouped, named clearly)

Place a **single "suggestion keywords"** section after [kSelectableSpendCategories](lib/spend_categories.dart) (around lines 44-59) and before unrelated utilities like `mergedSortedCategories`, **or** immediately above `suggestCategoryFromDescription`—choose one consistent block so the file stays scannable.

Define lists that mirror **current** behavior, including splits required for **precedence** (same `if` order as today):

| List / notes | Purpose |
|--------------|---------|
| `incomePayrollKeywords` | `bom dough`, `indn:martins pedro`, `payroll`, `des:payroll` |
| Credit / Zelle / remittance | Keep **explicit** `if`s for Zelle received (`zelle` + `payment from` / `transfer from`), credit card phrases, Zelle `payment to` → `Transfer Out`. **Add** `remitly`, `verso` → **`Transfer Out`** in the same neighbourhood as the Zelle-out check (immediately after that `if`, or merged into one `Transfer Out` condition with comment "remittance / transfer services") so precedence stays above subscription/shopping inference. Short token **`verso`** may rarely false-positive—acceptable unless you later tighten with word boundaries. |
| `appleBillKeywords` | `apple com bill`, `apple.com/bill` (early Subscriptions, before DSW) |
| `shoesKeywords` | `dsw` |
| `pharmacyHeadKeywords` | `cvs` only — must stay **before** `pearl market` / quick food (same as now) |
| `groceryHeadKeywords` | `pearl market` |
| `coffeeQuickFoodKeywords` | `quick food mart`, `food mart` |
| `housingKeywords` | `rent`, `mortgage`, `landlord`, `lease` |
| `foodDeliveryAndChainKeywords` | **Expanded US chains:** existing needles plus `dominos`, `domino's`, `popeyes`, `papa john`, `pizzahut`, `taco bell`, `kfc`, `wendys`, `wendy's`, `burger king`, `subway` (all substring / lowercase like today) |
| `transportRideKeywords` | `lyft`, `bolt`, `taxi` — plus **explicit** Uber: `(has('uber') && !has('uber eats'))` stays next to this group (cannot fold Uber into the same static list without special case) |
| `shoppingBigBoxKeywords` | `amazon`, `walmart`, `target`, `costco`, **`temu`**, **`shein`**, **`fragrancenet`** |
| `foodGenericKeywords` | `starbucks`, `coffee`, `restaurant`, `cafe` |
| `groceryKeywords` | stop/shop variants, `market basket`, `shaw's`, `shaws`, `big y`, trader joe(s), `whole foods`, `star market` |
| `pharmacyTailKeywords` | `walgreens`, `rite aid`, `riteaid` only — **omit** redundant second `cvs` at the tail (unreachable today; removing it is behavior-neutral) |
| `subscriptionKeywords` | Existing streaming/software needles plus **`suno`**, **`landr`** (map to canonical **`Subscriptions`**; app has no separate "Software" bucket) |
| `transportFuelAndTransitKeywords` | `mbta`, `t-pass`, `shell`, `exxon`, `mobil` |
| `shoppingFashionDiscountKeywords` | `tj maxx`, `marshalls` |
| `billsUtilitiesKeywords` | `verizon`, `tmobile`, `comcast`, `xfinity`, `spectrum` |

Naming can be tweaked (e.g. `*_kw` suffix) but should read as **why the list exists** (early vs tail, or semantic group).

## `suggestCategoryFromDescription` body

- Keep the **same sequence** of checks: payroll → Zelle income → credit card → Zelle out → remitly/verso (Transfer Out) → early Apple → DSW → CVS head → pearl → quick food → housing → first Food block → Transportation (with Uber exception) → big-box shopping → generic food → grocery tail → pharmacy tail → subscriptions tail → MBTA/fuel → TJ/marshalls → bills.
- Replace each eligible `has('…') || …` block with `if (_haystackContainsAny(h, someList))`.
- Leave **compound** conditions as readable `if` + `&&` / `||` with `h.contains` or inline `!h.contains('uber eats')` for Uber.

## Tests

Run `flutter test`. Expect **new** coverage for expanded Food / Shopping / Subscriptions / Transfer Out needles if you add targeted `expect(suggestCategoryFromDescription(...))` lines (optional); at minimum no regressions.

## Addendum: US-general keywords (merged into refactor)

Single implementation pass should include:

1. **Food & Drink** (still **before** Transportation): replace the current first Food `if` with the expanded chain list from the product spec (`uber eats` … `subway`), keeping position in the cascade.
2. **Shopping:** add `temu`, `shein`, `fragrancenet` to the **early** big-box Shopping `if` (`amazon` / `walmart` / …), so they inherit the same precedence vs Food/Transport as today's big retailers.
3. **Subscriptions:** append `suno`, `landr` to the tail Subscriptions block (and to `subscriptionKeywords` when using lists).
4. **Transfers:** `remitly`, `verso` → **`Transfer Out`**, placed with the existing Zelle `payment to` logic per table above—**do not** move Zelle compound checks.

Everything else in `suggestCategoryFromDescription` stays as-is aside from list/helper refactor and these needles.

## Out of scope

No new classes, no new files, no changes to `spendGroupLabel` / `CategoryRule` / imports beyond what's already in this file.
