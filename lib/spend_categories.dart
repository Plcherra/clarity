import 'models.dart';

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
List<String> categoryPickerCanonicals({
  required Iterable<String> customCategories,
  required Set<String> hiddenLower,
}) {
  final builtIns = kSelectableSpendCategories.where(
    (c) => !hiddenLower.contains(c.toLowerCase()),
  );
  final customs = customCategories.where(
    (c) => !hiddenLower.contains(c.trim().toLowerCase()),
  );
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
}) {
  final base = spendGroupLabel(t, categoryOverrides: categoryOverrides);
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
String spendGroupLabel(
  Transaction t, {
  Map<String, String>? categoryOverrides,
}) {
  final key = transactionCategoryKey(t);
  final manual = categoryOverrides?[key];
  if (manual != null && manual.trim().isNotEmpty) {
    return manual.trim();
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
