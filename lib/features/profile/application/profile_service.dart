import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_exceptions.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../../core/supabase/supabase_service.dart';

final class ProfileService {
  ProfileService({required SupabaseService supabaseService})
    : _supabaseService = supabaseService;

  final SupabaseService _supabaseService;

  User get _currentUser {
    final user = _supabaseService.auth.currentUser;
    if (user == null) throw const SupabaseAuthRequiredException();
    return user;
  }

  Future<ProfileRecord?> fetchCurrentProfile() async {
    final user = _currentUser;
    try {
      final row = await _supabaseService.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return ProfileRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'profiles',
        action: 'fetchCurrentProfile',
        message: 'Could not fetch the current profile.',
        cause: e,
      );
    }
  }

  Future<ProfileRecord> upsertCurrentProfile({
    String? email,
    String? fullName,
    String? avatarUrl,
  }) async {
    final user = _currentUser;
    try {
      final row = await _supabaseService.client
          .from('profiles')
          .upsert({
            'id': user.id,
            'email': email ?? user.email,
            'full_name': fullName,
            'avatar_url': avatarUrl,
          })
          .select()
          .single();
      return ProfileRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'profiles',
        action: 'upsertCurrentProfile',
        message: 'Could not upsert the current profile.',
        cause: e,
      );
    }
  }

  Future<ProfileRecord> updateCurrentProfile({
    String? email,
    String? fullName,
    String? avatarUrl,
  }) async {
    final user = _currentUser;
    final payload = <String, dynamic>{};
    if (email != null) payload['email'] = email;
    if (fullName != null) payload['full_name'] = fullName;
    if (avatarUrl != null) payload['avatar_url'] = avatarUrl;
    if (payload.isEmpty) {
      throw const SupabaseDataException(
        table: 'profiles',
        action: 'updateCurrentProfile',
        message: 'At least one profile field is required.',
      );
    }

    try {
      final row = await _supabaseService.client
          .from('profiles')
          .update(payload)
          .eq('id', user.id)
          .select()
          .single();
      return ProfileRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'profiles',
        action: 'updateCurrentProfile',
        message: 'Could not update the current profile.',
        cause: e,
      );
    }
  }

  Stream<ProfileRecord?> watchCurrentProfile() {
    final user = _currentUser;
    return _supabaseService.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .map(
          (rows) => rows.isEmpty ? null : ProfileRecord.fromJson(rows.first),
        );
  }
}
