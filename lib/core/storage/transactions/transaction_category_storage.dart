import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists manual category choices keyed by [transactionCategoryKey].
const String kTransactionCategoryAssignmentsPrefsKey =
    'transaction_category_assignments_v1';

/// Loads persisted transaction -> category assignments (best-effort).
Future<Map<String, String>> loadTransactionCategoryAssignments() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kTransactionCategoryAssignmentsPrefsKey);
  if (raw == null || raw.isEmpty) return {};

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return {};
  }
  if (decoded is! Map) return {};

  final out = <String, String>{};
  for (final e in decoded.entries) {
    final k = e.key;
    final v = e.value;
    if (k is! String || v is! String) continue;
    final key = k.trim();
    final val = v.trim();
    if (key.isEmpty || val.isEmpty) continue;
    out[key] = val;
  }
  return out;
}

Future<void> saveTransactionCategoryAssignments(Map<String, String> map) async {
  final prefs = await SharedPreferences.getInstance();
  final serializable = <String, String>{};
  for (final e in map.entries) {
    final k = e.key.trim();
    final v = e.value.trim();
    if (k.isEmpty || v.isEmpty) continue;
    serializable[k] = v;
  }
  await prefs.setString(
    kTransactionCategoryAssignmentsPrefsKey,
    jsonEncode(serializable),
  );
}

