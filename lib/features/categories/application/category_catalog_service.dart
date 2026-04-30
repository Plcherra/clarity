import '../../../core/storage/categories/category_catalog_storage.dart';
import '../../transactions/domain/spend_categories.dart';

class CategoryCatalogService {
  /// User-created category names (shown in the assignment sheet alongside built-ins).
  List<String> customCategories = const [];

  /// Lowercase base label -> user display name (renamed built-ins / display tweaks).
  /// Not cleared by CSV import.
  Map<String, String> categoryDisplayRenames = const {};

  /// Lowercase canonical labels removed from the picker (deleted built-ins).
  /// Not cleared by CSV import.
  Set<String> categoriesHiddenFromPicker = {};

  /// Built-in + custom categories shown in pickers.
  List<String> get allowedCategoryPickerLabels => categoryPickerCanonicals(
    customCategories: customCategories,
    hiddenLower: categoriesHiddenFromPicker,
  );

  /// Loads custom category names and picker metadata from disk.
  Future<void> hydratePersistedCategoryCatalog() async {
    try {
      final snap = await loadCategoryCatalog();
      customCategories = List<String>.from(snap.customCategories);
      categoryDisplayRenames = Map<String, String>.from(
        snap.categoryDisplayRenames,
      );
      categoriesHiddenFromPicker = Set<String>.from(
        snap.categoriesHiddenFromPicker,
      );
    } on Object {
      customCategories = const [];
      categoryDisplayRenames = const {};
      categoriesHiddenFromPicker = {};
    }
  }

  void persistCategoryCatalog() {
    saveCategoryCatalog(
      customCategories: customCategories,
      categoryDisplayRenames: categoryDisplayRenames,
      categoriesHiddenFromPicker: categoriesHiddenFromPicker,
    ).catchError((_) {});
  }
}
