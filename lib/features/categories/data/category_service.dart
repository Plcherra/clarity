import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_exceptions.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../../core/supabase/supabase_service.dart';
import '../domain/category_normalization.dart';

final class CategoryService {
  CategoryService({required SupabaseService supabaseService})
    : _supabaseService = supabaseService;

  final SupabaseService _supabaseService;

  User get _currentUser {
    final user = _supabaseService.auth.currentUser;
    if (user == null) throw const SupabaseAuthRequiredException();
    return user;
  }

  Future<List<CategoryRecord>> fetchCategories() async {
    final user = _currentUser;
    try {
      final rows = await _supabaseService.client
          .from('categories')
          .select()
          .eq('user_id', user.id)
          .order('name');
      return rows.map(CategoryRecord.fromJson).toList();
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'categories',
        action: 'fetchCategories',
        message: 'Could not fetch categories.',
        cause: e,
      );
    }
  }

  Future<CategoryRecord> createCategory({
    required String name,
    required String type,
    String? color,
    String? icon,
  }) async {
    final user = _currentUser;
    final normalized = normalizeCategoryName(name);
    if (normalized == null) {
      throw const SupabaseDataException(
        table: 'categories',
        action: 'createCategory',
        message: 'Category name is invalid.',
      );
    }
    final existing = await _fetchCategoryByNormalizedName(
      userId: user.id,
      normalizedName: normalized.normalizedName,
    );
    if (existing != null) return existing;

    try {
      final row = await _supabaseService.client
          .from('categories')
          .insert({
            'user_id': user.id,
            'name': normalized.displayName,
            'normalized_name': normalized.normalizedName,
            'type': type,
            'color': color,
            'icon': icon,
          })
          .select()
          .single();
      return CategoryRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      final afterConflict = await _fetchCategoryByNormalizedName(
        userId: user.id,
        normalizedName: normalized.normalizedName,
      );
      if (afterConflict != null) return afterConflict;
      throw SupabaseDataException(
        table: 'categories',
        action: 'createCategory',
        message: 'Could not create category.',
        cause: e,
      );
    }
  }

  Future<CategoryRecord> updateCategory(
    String id, {
    String? name,
    String? type,
    String? color,
    String? icon,
  }) async {
    final user = _currentUser;
    final payload = <String, dynamic>{};
    if (name != null) {
      final normalized = normalizeCategoryName(name);
      if (normalized == null) {
        throw const SupabaseDataException(
          table: 'categories',
          action: 'updateCategory',
          message: 'Category name is invalid.',
        );
      }
      payload['name'] = normalized.displayName;
      payload['normalized_name'] = normalized.normalizedName;
    }
    if (type != null) payload['type'] = type;
    if (color != null) payload['color'] = color;
    if (icon != null) payload['icon'] = icon;
    if (payload.isEmpty) {
      throw const SupabaseDataException(
        table: 'categories',
        action: 'updateCategory',
        message: 'At least one category field is required.',
      );
    }

    try {
      final row = await _supabaseService.client
          .from('categories')
          .update(payload)
          .eq('user_id', user.id)
          .eq('id', id)
          .select()
          .single();
      return CategoryRecord.fromJson(row);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'categories',
        action: 'updateCategory',
        message: 'Could not update category.',
        cause: e,
      );
    }
  }

  Future<void> deleteCategory(String id) async {
    final user = _currentUser;
    try {
      await _supabaseService.client
          .from('categories')
          .delete()
          .eq('user_id', user.id)
          .eq('id', id);
    } on SupabaseDataException {
      rethrow;
    } on Object catch (e) {
      throw SupabaseDataException(
        table: 'categories',
        action: 'deleteCategory',
        message: 'Could not delete category.',
        cause: e,
      );
    }
  }

  Stream<List<CategoryRecord>> watchCategories() {
    final user = _currentUser;
    return _supabaseService.client
        .from('categories')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .map((rows) => rows.map(CategoryRecord.fromJson).toList());
  }

  Future<CategoryRecord?> _fetchCategoryByNormalizedName({
    required String userId,
    required String normalizedName,
  }) async {
    final rows = await _supabaseService.client
        .from('categories')
        .select()
        .eq('user_id', userId)
        .eq('normalized_name', normalizedName)
        .limit(1);
    if (rows.isEmpty) return null;
    return CategoryRecord.fromJson(rows.first);
  }
}
