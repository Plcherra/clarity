import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kProfilePrefsKey = 'profile_v1';

class LocalProfile {
  const LocalProfile({
    required this.displayName,
    required this.createdAtUtcIso,
    this.email,
    this.avatarUrl,
  });

  final String displayName;
  final String createdAtUtcIso;
  final String? email;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'createdAtUtcIso': createdAtUtcIso,
    if (email != null) 'email': email,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  static LocalProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['displayName'];
    final created = raw['createdAtUtcIso'];
    if (name is! String || name.trim().isEmpty) return null;
    if (created is! String || created.trim().isEmpty) return null;
    final email = raw['email'];
    final avatarUrl = raw['avatarUrl'];
    return LocalProfile(
      displayName: name.trim(),
      createdAtUtcIso: created.trim(),
      email: email is String && email.trim().isNotEmpty ? email.trim() : null,
      avatarUrl: avatarUrl is String && avatarUrl.trim().isNotEmpty
          ? avatarUrl.trim()
          : null,
    );
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
