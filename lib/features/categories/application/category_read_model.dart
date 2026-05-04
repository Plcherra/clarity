import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_records.dart';
import '../../transactions/domain/spend_categories.dart';
import '../data/category_service.dart';

final class CategoryReadModel extends ChangeNotifier {
  CategoryReadModel({required CategoryService categoryService})
    : _categoryService = categoryService;

  final CategoryService _categoryService;
  StreamSubscription<List<CategoryRecord>>? _subscription;
  List<CategoryRecord> _categories = const [];

  List<CategoryRecord> get categories => List.unmodifiable(_categories);

  List<String> get customCategories {
    final builtIns = {
      for (final category in kSelectableSpendCategories)
        category.trim().toLowerCase(),
    };
    final names = <String>[];
    final seen = <String>{};
    for (final category in _categories) {
      final name = category.name.trim();
      final key = name.toLowerCase();
      if (name.isEmpty || builtIns.contains(key) || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      names.add(name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List.unmodifiable(names);
  }

  Map<String, String> get categoryDisplayRenames => const {};

  Set<String> get categoriesHiddenFromPicker => const {};

  List<String> get allowedCategoryPickerLabels => categoryPickerCanonicals(
    customCategories: customCategories,
    hiddenLower: categoriesHiddenFromPicker,
  );

  Future<void> refresh() async {
    _setCategories(await _categoryService.fetchCategories());
  }

  void startWatching({required void Function() onChanged}) {
    if (_subscription != null) return;
    _subscription = _categoryService.watchCategories().listen((categories) {
      _setCategories(categories);
      onChanged();
    });
  }

  void stopWatching() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _setCategories(const []);
  }

  CategoryRecord? categoryById(String? id) {
    final key = id?.trim();
    if (key == null || key.isEmpty) return null;
    for (final category in _categories) {
      if (category.id == key) return category;
    }
    return null;
  }

  CategoryRecord? categoryByName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final category in _categories) {
      if (category.name.trim().toLowerCase() == key) return category;
    }
    return null;
  }

  String? categoryNameForId(String? id) => categoryById(id)?.name;

  Future<CategoryRecord> ensureExpenseCategory(String name) async {
    final trimmed = name.trim();
    final existing = categoryByName(trimmed);
    if (existing != null) return existing;
    final created = await _categoryService.createCategory(
      name: trimmed,
      type: 'expense',
    );
    _setCategories([..._categories, created]);
    return created;
  }

  void _setCategories(List<CategoryRecord> categories) {
    _categories = List.unmodifiable(categories);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
