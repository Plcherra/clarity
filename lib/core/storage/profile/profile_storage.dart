import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kProfilePrefsKey = 'profile_v1';

class LocalProfile {
  const LocalProfile({required this.displayName, required this.createdAtUtcIso});

  final String displayName;
  final String createdAtUtcIso;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'createdAtUtcIso': createdAtUtcIso,
  };

  static LocalProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['displayName'];
    final created = raw['createdAtUtcIso'];
    if (name is! String || name.trim().isEmpty) return null;
    if (created is! String || created.trim().isEmpty) return null;
    return LocalProfile(displayName: name.trim(), createdAtUtcIso: created.trim());
  }
}

Future<LocalProfile?> loadLocalProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kProfilePrefsKey);
  if (raw == null || raw.trim().isEmpty) return null;
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return null;
  }
  return LocalProfile.fromJson(decoded);
}

Future<void> saveLocalProfile(LocalProfile profile) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kProfilePrefsKey, jsonEncode(profile.toJson()));
}

Future<void> clearLocalProfile() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kProfilePrefsKey);
}

