import 'category_description_normalize.dart';
import 'category_rule.dart';
import 'models.dart';

/// System category for returned / reversed / NSF lines (not in normal picker or budgets).
const String kIgnoredCategoryLabel = 'Ignored';

bool isIgnoredCategoryLabel(String label) =>
    label.trim().toLowerCase() == kIgnoredCategoryLabel.toLowerCase();

bool _descWordMatch(String haystackLower, String wordLower) {
  return RegExp(
    '\\b${RegExp.escape(wordLower)}\\b',
    caseSensitive: false,
  ).hasMatch(haystackLower);
}

/// Bank-style lines to drop from spending, income rollups, and category charts.
///
/// Matched on the raw description (case-insensitive). Checked after manual overrides,
/// before saved [categoryRules] and keyword/CSV inference.
///
/// Phrase substrings use plain [String.contains]. Short tokens use whole-word
/// matching so descriptions like `Transfer` do not match `NSF`.
bool isReturnedOrReversedDescription(String description) {
  final h = description.toLowerCase();
  if (h.contains('returned item')) return true;
  if (h.contains('insufficient funds')) return true;
  if (_descWordMatch(h, 'reversal')) return true;
  if (_descWordMatch(h, 'reversed')) return true;
  if (_descWordMatch(h, 'refunded')) return true;
  if (_descWordMatch(h, 'returned')) return true;
  if (_descWordMatch(h, 'nsf')) return true;
  if (_descWordMatch(h, 'return')) return true;
  return false;
}

/// Stable key for [Transaction] rows when applying manual category overrides.
String transactionCategoryKey(Transaction t) {
  final ba = t.balanceAfter;
  return '${t.date.toIso8601String()}|${t.amount}|${t.description}|${ba ?? ''}';
}

/// All built-in categories users can assign (excludes `Uncategorized`; order is pick-list order).
const List<String> kSelectableSpendCategories = [
  'Coffee / Quick Food',
  'Credit Card Payment',
  'Food & Drink',
  'Grocery / Supermarket',
  'Housing',
  'Income / Payroll',
  'Income / Zelle Received',
  'Pharmacy / Health',
  'Shoes / Clothing',
  'Shopping',
  'Subscriptions',
  'Transfer Out',
  'Transportation',
];

bool isBuiltInSpendCategory(String name) =>
    kSelectableSpendCategories.contains(name);

/// Built-in names plus [custom], sorted case-insensitively, deduped.
List<String> mergedSortedCategories(Iterable<String> custom) {
  final set = <String>{...kSelectableSpendCategories, ...custom};
  final out = set.toList();
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

/// Picker list: built-ins and custom, excluding [hiddenLower] (deleted from picker).
///
/// The system-only [kIgnoredCategoryLabel] is never shown (budget vs actual / assignment).
List<String> categoryPickerCanonicals({
  required Iterable<String> customCategories,
  required Set<String> hiddenLower,
}) {
  bool visible(String c) {
    final k = c.trim().toLowerCase();
    if (k.isEmpty) return false;
    if (isIgnoredCategoryLabel(c)) return false;
    return !hiddenLower.contains(k);
  }

  final builtIns = kSelectableSpendCategories.where(visible);
  final customs = customCategories.where(visible);
  final set = <String>{...builtIns, ...customs};
  final out = set.toList();
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

/// Applies user display renames (keys = lowercase base label from [spendGroupLabel]).
String applyCategoryDisplayRenames(
  String label,
  Map<String, String> renamesLowerToDisplay,
) {
  if (renamesLowerToDisplay.isEmpty) return label;
  final k = label.trim().toLowerCase();
  return renamesLowerToDisplay[k] ?? label;
}

/// [spendGroupLabel] plus optional display renames for UI and grouping.
String spendGroupLabelForDisplay(
  Transaction t, {
  Map<String, String>? categoryOverrides,
  Map<String, String>? categoryDisplayRenamesLower,
  List<CategoryRule>? categoryRules,
}) {
  final base = spendGroupLabel(
    t,
    categoryOverrides: categoryOverrides,
    categoryRules: categoryRules,
  );
  return applyCategoryDisplayRenames(base, categoryDisplayRenamesLower ?? {});
}

/// Simple keyword-based category from free-text (e.g. merchant / description).
String suggestCategoryFromDescription(String description) {
  final h = description.toLowerCase();

  bool has(String needle) => h.contains(needle);

  // Payroll / employer ACH (check first; matches real bank description text).
  if (has('bom dough') || has('indn:martins pedro')) {
    return 'Income / Payroll';
  }
  if (has('payroll') || has('des:payroll')) {
    return 'Income / Payroll';
  }
  if (has('zelle') && (has('payment from') || has('transfer from'))) {
    return 'Income / Zelle Received';
  }
  if (has('online banking payment to crd') || has('payment to crd')) {
    return 'Credit Card Payment';
  }
  if (has('zelle') && has('payment to')) {
    return 'Transfer Out';
  }
  if (has('apple com bill') || has('apple.com/bill')) {
    return 'Subscriptions';
  }
  if (has('dsw')) {
    return 'Shoes / Clothing';
  }
  if (has('cvs')) {
    return 'Pharmacy / Health';
  }
  if (has('pearl market')) {
    return 'Grocery / Supermarket';
  }
  if (has('quick food mart') || has('food mart')) {
    return 'Coffee / Quick Food';
  }

  if (has('rent') || has('mortgage') || has('landlord') || has('lease')) {
    return 'Housing';
  }
  if (has('uber') || has('lyft') || has('bolt') || has('taxi')) {
    return 'Transportation';
  }
  if (has('amazon') || has('walmart') || has('target') || has('costco')) {
    return 'Shopping';
  }
  if (has('starbucks') ||
      has('coffee') ||
      has('restaurant') ||
      has('cafe')) {
    return 'Food & Drink';
  }
  return 'Uncategorized';
}

/// True for spend buckets that represent money in, not spending (case-insensitive).
bool isIncomeCategoryLabel(String label) =>
    label.trimLeft().toLowerCase().startsWith('income');

/// Resolves the label used for grouping spending (CSV category or keyword bucket).
///
/// [categoryOverrides] maps [transactionCategoryKey] to a chosen label (manual categorization).
///
/// [categoryRules]: first list-order match on normalized description wins; only applied
/// to outflow rows ([Transaction.isOutflow]). Prefer [AppState.effectiveSpendGroupLabel]
/// at call sites that have app state.
String spendGroupLabel(
  Transaction t, {
  Map<String, String>? categoryOverrides,
  List<CategoryRule>? categoryRules,
}) {
  final key = transactionCategoryKey(t);
  final manual = categoryOverrides?[key];
  if (manual != null && manual.trim().isNotEmpty) {
    return manual.trim();
  }
  if (isReturnedOrReversedDescription(t.description)) {
    return kIgnoredCategoryLabel;
  }
  if (categoryRules != null &&
      categoryRules.isNotEmpty &&
      t.isOutflow) {
    final haystack = normalizeDescriptionForMatching(t.description);
    for (final r in categoryRules) {
      if (r.matchType != CategoryRule.matchTypeContains) continue;
      if (haystack.contains(r.pattern)) {
        return r.categoryCanonical;
      }
    }
  }
  final suggested = suggestCategoryFromDescription(t.description);
  // Income from description always wins over generic bank CSV categories
  // (e.g. "Deposit", "Transfer", "Uncategorized").
  if (isIncomeCategoryLabel(suggested)) {
    return suggested;
  }
  final raw = t.category?.trim();
  if (raw != null && raw.isNotEmpty) {
    final o = raw.toLowerCase();
    if (o == 'uncategorized' || o == 'other') {
      return suggested;
    }
    return raw;
  }
  return suggested;
}
