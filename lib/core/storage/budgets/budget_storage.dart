import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'budget_keys.dart';

/// SharedPreferences key for the JSON map of category budgets.
const String kCategoryMonthlyBudgetsPrefsKey = 'category_monthly_budgets_v1';

/// Loads persisted monthly budgets.
///
/// Keys are [budgetDisplayKey] outputs; values are non-negative amounts.
/// Malformed JSON or unknown entry shapes are skipped (best-effort).
Future<Map<String, double>> loadBudgets() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kCategoryMonthlyBudgetsPrefsKey);
  if (raw == null || raw.isEmpty) return {};

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return {};
  }
  if (decoded is! Map) return {};

  final out = <String, double>{};
  for (final e in decoded.entries) {
    final k = e.key;
    if (k is! String) continue;
    final key = budgetDisplayKey(k);
    if (key.isEmpty) continue;
    final v = e.value;
    final amount = switch (v) {
      int i => i.toDouble(),
      double d => d,
      _ => null,
    };
    if (amount == null || !amount.isFinite || amount < 0) continue;
    out[key] = amount;
  }
  return out;
}

/// Persists the full monthly budget map (persist-then-commit at call sites).
///
/// [budgets] keys must already be [budgetDisplayKey] outputs.
Future<void> saveBudgets(Map<String, double> budgets) async {
  final prefs = await SharedPreferences.getInstance();
  final serializable = <String, double>{};
  for (final e in budgets.entries) {
    final k = budgetDisplayKey(e.key);
    if (k.isEmpty) continue;
    final v = e.value;
    if (!v.isFinite || v < 0) continue;
    serializable[k] = v;
  }
  final json = jsonEncode(serializable);
  await prefs.setString(kCategoryMonthlyBudgetsPrefsKey, json);
}

