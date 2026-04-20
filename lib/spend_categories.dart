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
  return '${t.accountId}|${t.date.toIso8601String()}|${t.amount}|${t.description}|${ba ?? ''}';
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

// --- suggestCategoryFromDescription needles (lowercase substrings) ---

const List<String> incomePayrollKeywords = [
  'bom dough',
  'indn:martins pedro',
  'payroll',
  'des:payroll',
];

const List<String> appleBillKeywords = ['apple com bill', 'apple.com/bill'];

const List<String> shoesKeywords = ['dsw'];

const List<String> pharmacyHeadKeywords = ['cvs'];

const List<String> groceryHeadKeywords = ['pearl market'];

const List<String> coffeeQuickFoodKeywords = ['quick food mart', 'food mart'];

const List<String> housingKeywords = ['rent', 'mortgage', 'landlord', 'lease'];

const List<String> foodDeliveryAndChainKeywords = [
  'uber eats',
  'doordash',
  'grubhub',
  'starbucks',
  'dunkin',
  'chipotle',
  'mcdonald',
  'dominos',
  "domino's",
  'popeyes',
  'papa john',
  'pizzahut',
  'taco bell',
  'kfc',
  'wendys',
  "wendy's",
  'burger king',
  'subway',
];

const List<String> transportRideKeywords = ['lyft', 'bolt', 'taxi'];

const List<String> shoppingBigBoxKeywords = [
  'amazon',
  'walmart',
  'target',
  'costco',
  'temu',
  'shein',
  'fragrancenet',
];

const List<String> foodGenericKeywords = [
  'starbucks',
  'coffee',
  'restaurant',
  'cafe',
];

const List<String> groceryKeywords = [
  'stop and shop',
  'stop&shop',
  'market basket',
  "shaw's",
  'shaws',
  'big y',
  'trader joe',
  'traderjoes',
  'whole foods',
  'star market',
];

const List<String> pharmacyTailKeywords = ['walgreens', 'rite aid', 'riteaid'];

const List<String> subscriptionKeywords = [
  'netflix',
  'disney',
  'hulu',
  'spotify',
  'apple com bill',
  'apple.com/bill',
  'paramount',
  'max.com',
  'youtube premium',
  'suno',
  'landr',
];

const List<String> transportFuelAndTransitKeywords = [
  'mbta',
  't-pass',
  'shell',
  'exxon',
  'mobil',
];

const List<String> shoppingFashionDiscountKeywords = ['tj maxx', 'marshalls'];

const List<String> billsUtilitiesKeywords = [
  'verizon',
  'tmobile',
  'comcast',
  'xfinity',
  'spectrum',
];

bool _haystackContainsAny(String haystackLower, List<String> needles) {
  for (final n in needles) {
    if (haystackLower.contains(n)) return true;
  }
  return false;
}

String? _trySuggestIncomeTransfersAndPayments(String haystackLower) {
  bool has(String needle) => haystackLower.contains(needle);
  if (_haystackContainsAny(haystackLower, incomePayrollKeywords)) {
    return 'Income / Payroll';
  }
  if (has('zelle') && (has('payment from') || has('transfer from'))) {
    return 'Income / Zelle Received';
  }
  if (has('online banking payment to crd') || has('payment to crd')) {
    return 'Credit Card Payment';
  }
  if ((has('zelle') && has('payment to')) ||
      has('remitly') ||
      has('verso')) {
    return 'Transfer Out';
  }
  return null;
}

String? _trySuggestMerchantAnchors(String haystackLower) {
  if (_haystackContainsAny(haystackLower, appleBillKeywords)) {
    return 'Subscriptions';
  }
  if (_haystackContainsAny(haystackLower, shoesKeywords)) {
    return 'Shoes / Clothing';
  }
  if (_haystackContainsAny(haystackLower, pharmacyHeadKeywords)) {
    return 'Pharmacy / Health';
  }
  if (_haystackContainsAny(haystackLower, groceryHeadKeywords)) {
    return 'Grocery / Supermarket';
  }
  if (_haystackContainsAny(haystackLower, coffeeQuickFoodKeywords)) {
    return 'Coffee / Quick Food';
  }
  return null;
}

String? _trySuggestHousing(String haystackLower) {
  if (_haystackContainsAny(haystackLower, housingKeywords)) {
    return 'Housing';
  }
  return null;
}

String? _trySuggestFoodTransportShoppingMid(String haystackLower) {
  bool has(String needle) => haystackLower.contains(needle);
  if (_haystackContainsAny(haystackLower, foodDeliveryAndChainKeywords)) {
    return 'Food & Drink';
  }
  if ((has('uber') && !has('uber eats')) ||
      _haystackContainsAny(haystackLower, transportRideKeywords)) {
    return 'Transportation';
  }
  if (_haystackContainsAny(haystackLower, shoppingBigBoxKeywords)) {
    return 'Shopping';
  }
  if (_haystackContainsAny(haystackLower, foodGenericKeywords)) {
    return 'Food & Drink';
  }
  return null;
}

String? _trySuggestRemainingBuckets(String haystackLower) {
  if (_haystackContainsAny(haystackLower, groceryKeywords)) {
    return 'Grocery / Supermarket';
  }
  if (_haystackContainsAny(haystackLower, pharmacyTailKeywords)) {
    return 'Pharmacy / Health';
  }
  if (_haystackContainsAny(haystackLower, subscriptionKeywords)) {
    return 'Subscriptions';
  }
  if (_haystackContainsAny(haystackLower, transportFuelAndTransitKeywords)) {
    return 'Transportation';
  }
  if (_haystackContainsAny(haystackLower, shoppingFashionDiscountKeywords)) {
    return 'Shopping';
  }
  if (_haystackContainsAny(haystackLower, billsUtilitiesKeywords)) {
    return 'Bills & Utilities';
  }
  return null;
}

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
///
/// Resolution order matches the private `_trySuggest…` helpers (income/transfers
/// first, then merchant anchors, housing, food/transport/shopping mid-tier,
/// then remaining grocery/pharmacy/subscription/bills buckets).
String suggestCategoryFromDescription(String description) {
  final h = description.toLowerCase();
  return _trySuggestIncomeTransfersAndPayments(h) ??
      _trySuggestMerchantAnchors(h) ??
      _trySuggestHousing(h) ??
      _trySuggestFoodTransportShoppingMid(h) ??
      _trySuggestRemainingBuckets(h) ??
      'Uncategorized';
}

/// True for spend buckets that represent money in, not spending (case-insensitive).
bool isIncomeCategoryLabel(String label) =>
    label.trimLeft().toLowerCase().startsWith('income');

bool _categoryRuleWholeWord(String haystackLower, String tokenLower) {
  return RegExp(
    '\\b${RegExp.escape(tokenLower)}\\b',
    caseSensitive: false,
  ).hasMatch(haystackLower);
}

/// True if [description] matches a persisted category rule [pattern].
///
/// [pattern] must already be normalized like stored rules ([normalizeDescriptionForMatching]).
/// Comma-separated segments are **OR** alternatives. Each alternative matches if:
/// - the haystack contains it as a substring (legacy), or
/// - it has 2+ whitespace-separated tokens and **every** token appears as a whole word
///   (any order), or
/// - it is a single token of length ≥3 and its alphanumeric-only form is contained in the
///   alphanumeric-only haystack (e.g. `cashback` vs `cash back rewards`).
bool descriptionMatchesCategoryRule(String description, String pattern) {
  final haystack = normalizeDescriptionForMatching(description);
  final trimmed = pattern.trim();
  if (trimmed.isEmpty) return false;
  for (final rawAlt in trimmed.split(',')) {
    final alt = rawAlt.trim();
    if (alt.isEmpty) continue;
    if (_categoryRuleAlternativeMatches(haystack, alt)) return true;
  }
  return false;
}

bool _categoryRuleAlternativeMatches(String haystack, String alt) {
  if (haystack.contains(alt)) return true;
  final tokens = alt.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.length >= 2) {
    return tokens.every((t) => _categoryRuleWholeWord(haystack, t));
  }
  if (tokens.length == 1) {
    final altCompact = tokens[0].replaceAll(RegExp(r'[^a-z0-9]'), '');
    final hayCompact = haystack.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return altCompact.length >= 3 && hayCompact.contains(altCompact);
  }
  return false;
}

String? _firstMatchingCategoryRuleCanonical(
  String description,
  List<CategoryRule> rules,
) {
  for (final r in rules) {
    if (r.matchType != CategoryRule.matchTypeContains) continue;
    if (descriptionMatchesCategoryRule(description, r.pattern)) {
      return r.categoryCanonical;
    }
  }
  return null;
}

/// Resolves the label used for grouping spending (CSV category or keyword bucket).
///
/// Order: [Transaction.categoryId] (persisted manual choice), then [categoryOverrides]
/// for the same row key, then description rules, then heuristics / CSV category.
///
/// [categoryRules]: first list-order match on normalized description wins (see
/// [descriptionMatchesCategoryRule] for OR / multi-token / compact semantics). On **outflows**,
/// rules run before keyword suggestion so user rules override heuristics. On **inflows**,
/// rules run only after keyword suggestion and only when that suggestion is not an
/// [isIncomeCategoryLabel] (so payroll-style inflows stay income). Prefer
/// [AppState.effectiveSpendGroupLabel] at call sites that have app state.
String spendGroupLabel(
  Transaction t, {
  Map<String, String>? categoryOverrides,
  List<CategoryRule>? categoryRules,
}) {
  final saved = t.categoryId?.trim();
  if (saved != null && saved.isNotEmpty) {
    return saved;
  }
  final key = transactionCategoryKey(t);
  final manual = categoryOverrides?[key];
  if (manual != null && manual.trim().isNotEmpty) {
    return manual.trim();
  }
  if (isReturnedOrReversedDescription(t.description)) {
    return kIgnoredCategoryLabel;
  }
  final rules = categoryRules;
  if (rules != null && rules.isNotEmpty && t.isOutflow) {
    final fromRule = _firstMatchingCategoryRuleCanonical(t.description, rules);
    if (fromRule != null) return fromRule;
  }
  final suggested = suggestCategoryFromDescription(t.description);
  // Income from description always wins over generic bank CSV categories
  // (e.g. "Deposit", "Transfer", "Uncategorized") and over inflow-only rules below.
  if (isIncomeCategoryLabel(suggested)) {
    return suggested;
  }
  if (rules != null && rules.isNotEmpty && !t.isOutflow) {
    final fromRule = _firstMatchingCategoryRuleCanonical(t.description, rules);
    if (fromRule != null) return fromRule;
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
