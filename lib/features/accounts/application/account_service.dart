import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_exceptions.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../../core/supabase/supabase_service.dart';

final class AccountService {
  AccountService({required SupabaseService supabaseService})
    : _supabaseService = supabaseService;

  final SupabaseService _supabaseService;

  User get _currentUser {
    final user = _supabaseService.auth.currentUser;
    if (user == null) throw const SupabaseAuthRequiredException();
    return user;
  }

  Future<List<AccountRecord>> fetchAccounts() async {
    final user = _currentUser;
    try {
      final rows = await _supabaseService.client
          .from('accounts')
          .select()
          .eq('user_id', user.id)
          .order('created_at');
      return rows.map(AccountRecord.fromJson).toList();
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'accounts',
        action: 'fetchAccounts',
        message: 'Could not fetch accounts.',
        cause: e,
      );
    }
  }

  Future<AccountRecord> createAccount({
    required String name,
    required String type,
    double balance = 0,
    String currency = 'USD',
    bool isActive = true,
  }) async {
    final user = _currentUser;
    try {
      final row = await _supabaseService.client
          .from('accounts')
          .insert({
            'user_id': user.id,
            'name': name,
            'type': type,
            'balance': balance,
            'currency': currency,
            'is_active': isActive,
          })
          .select()
          .single();
      return AccountRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'accounts',
        action: 'createAccount',
        message: 'Could not create account.',
        cause: e,
      );
    }
  }

  Future<AccountRecord> updateAccount(
    String id, {
    String? name,
    String? type,
    double? balance,
    String? currency,
    bool? isActive,
  }) async {
    final user = _currentUser;
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (type != null) payload['type'] = type;
    if (balance != null) payload['balance'] = balance;
    if (currency != null) payload['currency'] = currency;
    if (isActive != null) payload['is_active'] = isActive;
    if (payload.isEmpty) {
      throw const SupabaseDataException(
        table: 'accounts',
        action: 'updateAccount',
        message: 'At least one account field is required.',
      );
    }

    try {
      final row = await _supabaseService.client
          .from('accounts')
          .update(payload)
          .eq('user_id', user.id)
          .eq('id', id)
          .select()
          .single();
      return AccountRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'accounts',
        action: 'updateAccount',
        message: 'Could not update account.',
        cause: e,
      );
    }
  }

  Future<void> deleteAccount(String id) async {
    final user = _currentUser;
    try {
      await _supabaseService.client
          .from('accounts')
          .delete()
          .eq('user_id', user.id)
          .eq('id', id);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'accounts',
        action: 'deleteAccount',
        message: 'Could not delete account.',
        cause: e,
      );
    }
  }

  Stream<List<AccountRecord>> watchAccounts() {
    final user = _currentUser;
    return _supabaseService.client
        .from('accounts')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .map((rows) => rows.map(AccountRecord.fromJson).toList());
  }
}
