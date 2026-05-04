import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_exceptions.dart';
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

  Future<List<Account>> fetchAccounts() async {
    final user = _currentUser;
    try {
      final rows = await _supabaseService.client
          .from('accounts')
          .select()
          .eq('user_id', user.id)
          .order('created_at');
      return rows.map<Account>(_accountFromJson).toList();
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

  Stream<List<Account>> watchAccounts() {
    final user = _currentUser;
    return _supabaseService.client
        .from('accounts')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .map((rows) => rows.map<Account>(_accountFromJson).toList());
  }

  Future<Account> createAccount(Account account) async {
    final user = _currentUser;
    try {
      final row = await _supabaseService.client
          .from('accounts')
          .insert({
            'user_id': user.id,
            'name': account.name.trim(),
            'type': _accountTypeToDatabaseValue(account.type),
            'institution': _nullableTrimmed(account.institution),
            'balance': account.currentBalance ?? 0,
            'currency': 'USD',
            'is_active': true,
          })
          .select()
          .single();
      return _accountFromJson(row);
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

  Future<Account> updateAccount(Account account) async {
    final user = _currentUser;
    try {
      final row = await _supabaseService.client
          .from('accounts')
          .update({
            'name': account.name.trim(),
            'type': _accountTypeToDatabaseValue(account.type),
            'institution': _nullableTrimmed(account.institution),
            'balance': account.currentBalance ?? 0,
            'currency': 'USD',
            'is_active': true,
          })
          .eq('user_id', user.id)
          .eq('id', account.id)
          .select()
          .single();
      return _accountFromJson(row);
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
}

Account _accountFromJson(Map<String, dynamic> json) {
  return Account(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    type: _accountTypeFromDatabaseValue(_string(json, 'type')),
    institution: _nullableString(json, 'institution'),
    currentBalance: _money(json, 'balance'),
  );
}

String _accountTypeToDatabaseValue(AccountType type) {
  return switch (type) {
    AccountType.checking => 'checking',
    AccountType.savings => 'savings',
    AccountType.creditCard => 'credit_card',
  };
}

AccountType _accountTypeFromDatabaseValue(String value) {
  return switch (value.trim().toLowerCase()) {
    'savings' => AccountType.savings,
    'credit_card' || 'creditcard' || 'credit card' => AccountType.creditCard,
    _ => AccountType.checking,
  };
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  return value?.toString() ?? '';
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final string = value is String ? value : value.toString();
  final trimmed = string.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _nullableTrimmed(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

double _money(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
