import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'category_rule.dart';

const String kCategoryRulesPrefsKey = 'category_rules_v1';

Future<List<CategoryRule>> loadCategoryRules() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kCategoryRulesPrefsKey);
  if (raw == null || raw.isEmpty) return [];

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return [];
  }
  if (decoded is! List) return [];

  final out = <CategoryRule>[];
  for (final e in decoded) {
    final r = CategoryRule.fromJson(e);
    if (r != null) out.add(r);
  }
  return out;
}

Future<void> saveCategoryRules(List<CategoryRule> rules) async {
  final prefs = await SharedPreferences.getInstance();
  final json = jsonEncode(rules.map((r) => r.toJson()).toList());
  await prefs.setString(kCategoryRulesPrefsKey, json);
}
