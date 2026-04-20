import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kCategoryCatalogPrefsKey = 'category_catalog_v1';

/// User-defined category names, display renames, and picker-hidden built-ins.
Future<({
  List<String> customCategories,
  Map<String, String> categoryDisplayRenames,
  Set<String> categoriesHiddenFromPicker,
})> loadCategoryCatalog() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kCategoryCatalogPrefsKey);
  if (raw == null || raw.isEmpty) {
    return (
      customCategories: <String>[],
      categoryDisplayRenames: <String, String>{},
      categoriesHiddenFromPicker: <String>{},
    );
  }

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return (
      customCategories: <String>[],
      categoryDisplayRenames: <String, String>{},
      categoriesHiddenFromPicker: <String>{},
    );
  }
  if (decoded is! Map) {
    return (
      customCategories: <String>[],
      categoryDisplayRenames: <String, String>{},
      categoriesHiddenFromPicker: <String>{},
    );
  }

  final customRaw = decoded['custom'];
  final renamesRaw = decoded['renames'];
  final hiddenRaw = decoded['hidden'];

  final custom = <String>[];
  if (customRaw is List) {
    for (final e in customRaw) {
      if (e is String && e.trim().isNotEmpty) custom.add(e.trim());
    }
  }

  final renames = <String, String>{};
  if (renamesRaw is Map) {
    for (final e in renamesRaw.entries) {
      final k = e.key;
      final v = e.value;
      if (k is String && v is String && k.isNotEmpty && v.isNotEmpty) {
        renames[k.trim().toLowerCase()] = v.trim();
      }
    }
  }

  final hidden = <String>{};
  if (hiddenRaw is List) {
    for (final e in hiddenRaw) {
      if (e is String && e.trim().isNotEmpty) {
        hidden.add(e.trim().toLowerCase());
      }
    }
  }

  return (
    customCategories: custom,
    categoryDisplayRenames: renames,
    categoriesHiddenFromPicker: hidden,
  );
}

Future<void> saveCategoryCatalog({
  required List<String> customCategories,
  required Map<String, String> categoryDisplayRenames,
  required Set<String> categoriesHiddenFromPicker,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final map = <String, dynamic>{
    'custom': customCategories,
    'renames': categoryDisplayRenames,
    'hidden': categoriesHiddenFromPicker.toList(),
  };
  await prefs.setString(kCategoryCatalogPrefsKey, jsonEncode(map));
}
