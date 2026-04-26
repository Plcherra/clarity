import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';

const String kAiCategorySuggestionsPrefsKey = 'ai_category_suggestions_v1';
const String kLastAiApplyBatchPrefsKey = 'ai_last_apply_batch_v1';

Future<Map<String, AiCategorySuggestion>> loadAiCategorySuggestions() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kAiCategorySuggestionsPrefsKey);
  if (raw == null || raw.isEmpty) return {};

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return {};
  }
  if (decoded is! Map) return {};

  final out = <String, AiCategorySuggestion>{};
  for (final e in decoded.entries) {
    final k = e.key;
    final v = e.value;
    if (k is! String || v is! Map) continue;
    try {
      out[k] = AiCategorySuggestion.fromJson(Map<String, dynamic>.from(v));
    } on Object {
      // Best-effort.
    }
  }
  return out;
}

Future<void> saveAiCategorySuggestions(Map<String, AiCategorySuggestion> map) async {
  final prefs = await SharedPreferences.getInstance();
  final serializable = <String, Object?>{};
  for (final e in map.entries) {
    final k = e.key.trim();
    if (k.isEmpty) continue;
    serializable[k] = e.value.toJson();
  }
  await prefs.setString(kAiCategorySuggestionsPrefsKey, jsonEncode(serializable));
}

Future<List<AiAppliedCategoryChange>> loadLastAiApplyBatch() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kLastAiApplyBatchPrefsKey);
  if (raw == null || raw.isEmpty) return const [];

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return const [];
  }
  if (decoded is! List) return const [];

  final out = <AiAppliedCategoryChange>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    try {
      out.add(AiAppliedCategoryChange.fromJson(Map<String, dynamic>.from(e)));
    } on Object {
      // Best-effort.
    }
  }
  return out;
}

Future<void> saveLastAiApplyBatch(List<AiAppliedCategoryChange> batch) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    kLastAiApplyBatchPrefsKey,
    jsonEncode(batch.map((e) => e.toJson()).toList()),
  );
}

