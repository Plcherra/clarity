import '../../../core/storage/profile/profile_storage.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export '../../../core/storage/profile/profile_storage.dart' show LocalProfile;

class ProfileService {
  ProfileService({SupabaseService? supabaseService})
    : _supabaseService = supabaseService;

  final SupabaseService? _supabaseService;

  LocalProfile? localProfile;

  Future<void> hydrateLocalProfile() async {
    try {
      localProfile = await loadLocalProfile();
    } on Object {
      localProfile = null;
    }
  }

  Future<void> setLocalProfile(LocalProfile profile) async {
    await saveLocalProfile(profile);
    localProfile = profile;
  }

  Future<void> hydrateProfileForUser(User? user) async {
    if (user == null) {
      localProfile = null;
      return;
    }

    final remote = await fetchProfileForUser(user);
    localProfile = remote;
  }

  Future<LocalProfile?> fetchProfileForUser(User user) async {
    final supabase = _supabaseService;
    if (supabase == null || !supabase.isConfigured) return null;

    final row = await supabase.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return _profileFromRow(row, fallbackEmail: user.email);
  }

  Future<void> upsertProfileForUser({
    required User user,
    required LocalProfile profile,
  }) async {
    final supabase = _supabaseService;
    if (supabase == null || !supabase.isConfigured) {
      await setLocalProfile(profile);
      return;
    }

    final row = await supabase.client
        .from('profiles')
        .upsert({
          'id': user.id,
          'email': user.email ?? profile.email,
          'full_name': profile.displayName,
          'avatar_url': profile.avatarUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    localProfile = _profileFromRow(row, fallbackEmail: user.email);
  }

  String userNamespaceForMerchantMemory() {
    final created = localProfile?.createdAtUtcIso.trim();
    if (created != null && created.isNotEmpty) return created;
    return 'anon';
  }

  LocalProfile _profileFromRow(
    Map<String, dynamic> row, {
    required String? fallbackEmail,
  }) {
    final name = row['full_name'];
    final createdAt = row['created_at'];
    final email = row['email'];
    final avatarUrl = row['avatar_url'];
    return LocalProfile(
      displayName: name is String ? name.trim() : '',
      createdAtUtcIso: createdAt is String && createdAt.trim().isNotEmpty
          ? createdAt.trim()
          : DateTime.now().toUtc().toIso8601String(),
      email: email is String && email.trim().isNotEmpty
          ? email.trim()
          : fallbackEmail,
      avatarUrl: avatarUrl is String && avatarUrl.trim().isNotEmpty
          ? avatarUrl.trim()
          : null,
    );
  }
}
