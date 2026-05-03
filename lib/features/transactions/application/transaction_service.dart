import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_exceptions.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../../core/supabase/supabase_service.dart';

final class TransactionService {
  TransactionService({required SupabaseService supabaseService})
    : _supabaseService = supabaseService;

  final SupabaseService _supabaseService;

  User get _currentUser {
    final user = _supabaseService.auth.currentUser;
    if (user == null) throw const SupabaseAuthRequiredException();
    return user;
  }

  Future<List<TransactionRecord>> fetchTransactions({
    String? accountId,
    String? categoryId,
    String? importId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final user = _currentUser;
    try {
      dynamic query = _supabaseService.client
          .from('transactions')
          .select()
          .eq('user_id', user.id);

      if (accountId != null) {
        query = query.eq('account_id', accountId);
      }
      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }
      if (importId != null) {
        query = query.eq('import_id', importId);
      }
      if (startDate != null) {
        query = query.gte('date', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lte('date', _dateOnly(endDate));
      }

      final rows = await query.order('date', ascending: false);
      return rows.map<TransactionRecord>(TransactionRecord.fromJson).toList();
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'transactions',
        action: 'fetchTransactions',
        message: 'Could not fetch transactions.',
        cause: e,
      );
    }
  }

  Future<TransactionRecord> createTransaction({
    required String accountId,
    String? categoryId,
    required double amount,
    required String type,
    String? description,
    required DateTime date,
    String? merchant,
    bool importedFromCsv = false,
    String? importId,
  }) async {
    final user = _currentUser;
    try {
      final row = await _supabaseService.client
          .from('transactions')
          .insert({
            'user_id': user.id,
            'account_id': accountId,
            'category_id': categoryId,
            'amount': amount,
            'type': type,
            'description': description,
            'date': _dateOnly(date),
            'merchant': merchant,
            'imported_from_csv': importedFromCsv,
            'import_id': importId,
          })
          .select()
          .single();
      return TransactionRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'transactions',
        action: 'createTransaction',
        message: 'Could not create transaction.',
        cause: e,
      );
    }
  }

  Future<TransactionRecord> updateTransaction(
    String id, {
    String? accountId,
    String? categoryId,
    double? amount,
    String? type,
    String? description,
    DateTime? date,
    String? merchant,
    bool? importedFromCsv,
    String? importId,
  }) async {
    final user = _currentUser;
    final payload = <String, dynamic>{};
    if (accountId != null) payload['account_id'] = accountId;
    if (categoryId != null) payload['category_id'] = categoryId;
    if (amount != null) payload['amount'] = amount;
    if (type != null) payload['type'] = type;
    if (description != null) payload['description'] = description;
    if (date != null) payload['date'] = _dateOnly(date);
    if (merchant != null) payload['merchant'] = merchant;
    if (importedFromCsv != null) {
      payload['imported_from_csv'] = importedFromCsv;
    }
    if (importId != null) payload['import_id'] = importId;
    if (payload.isEmpty) {
      throw const SupabaseDataException(
        table: 'transactions',
        action: 'updateTransaction',
        message: 'At least one transaction field is required.',
      );
    }

    try {
      final row = await _supabaseService.client
          .from('transactions')
          .update(payload)
          .eq('user_id', user.id)
          .eq('id', id)
          .select()
          .single();
      return TransactionRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'transactions',
        action: 'updateTransaction',
        message: 'Could not update transaction.',
        cause: e,
      );
    }
  }

  Future<void> deleteTransaction(String id) async {
    final user = _currentUser;
    try {
      await _supabaseService.client
          .from('transactions')
          .delete()
          .eq('user_id', user.id)
          .eq('id', id);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'transactions',
        action: 'deleteTransaction',
        message: 'Could not delete transaction.',
        cause: e,
      );
    }
  }

  Stream<List<TransactionRecord>> watchTransactions({String? accountId}) {
    final user = _currentUser;
    return _supabaseService.client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .map((rows) {
          final filtered = accountId == null
              ? rows
              : rows.where((row) => row['account_id'] == accountId);
          return filtered.map(TransactionRecord.fromJson).toList();
        });
  }
}

String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;
