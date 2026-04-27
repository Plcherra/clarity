import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _kMerchantCategoryMemoryPrefsKeyPrefix =
    'merchant_category_memory_v1:';

String merchantCategoryMemoryPrefsKeyForUserNamespace(String userNamespace) {
  final ns = userNamespace.trim();
  if (ns.isEmpty) return '${_kMerchantCategoryMemoryPrefsKeyPrefix}anon';
  return '$_kMerchantCategoryMemoryPrefsKeyPrefix$ns';
}

Future<Map<String, String>> loadMerchantCategoryMemory(String userNamespace) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(merchantCategoryMemoryPrefsKeyForUserNamespace(userNamespace));
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
    final key = k.trim().toLowerCase();
    final val = v.trim();
    if (key.isEmpty || val.isEmpty) continue;
    out[key] = val;
  }
  return out;
}

Future<void> saveMerchantCategoryMemory(
  String userNamespace,
  Map<String, String> map,
) async {
  final prefs = await SharedPreferences.getInstance();
  final serializable = <String, String>{};
  for (final e in map.entries) {
    final k = e.key.trim().toLowerCase();
    final v = e.value.trim();
    if (k.isEmpty || v.isEmpty) continue;
    serializable[k] = v;
  }
  await prefs.setString(
    merchantCategoryMemoryPrefsKeyForUserNamespace(userNamespace),
    jsonEncode(serializable),
  );
}

