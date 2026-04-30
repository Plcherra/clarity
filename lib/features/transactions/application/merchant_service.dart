import '../../../core/models/models.dart';
import '../../../core/storage/transactions/merchant_category_memory_storage.dart';
import '../domain/spend_categories.dart';

class MerchantService {
  /// Per-user merchant -> canonical category “silent memory” (keys are lowercase merchant keys).
  Map<String, String> merchantCategoryMemory = const {};

  Future<void> hydrateMerchantCategoryMemory(String userNamespace) async {
    try {
      merchantCategoryMemory = await loadMerchantCategoryMemory(userNamespace);
    } on Object {
      merchantCategoryMemory = {};
    }
  }

  void _persistMerchantCategoryMemory(String userNamespace) {
    saveMerchantCategoryMemory(
      userNamespace,
      merchantCategoryMemory,
    ).catchError((_) {});
  }

  Future<void> applyPrefilledMerchantChunks(
    Map<String, String> prefilled, {
    required List<AiAppliedCategoryChange> Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
  }) async {
    if (prefilled.isEmpty) return;
    final entries = prefilled.entries.toList();
    const chunkSize = 80;
    for (var i = 0; i < entries.length; i += chunkSize) {
      final slice = Map<String, String>.fromEntries(
        entries.skip(i).take(chunkSize),
      );
      applyCategoriesWithMerchantLearning(slice);
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Applies explicit category assignments, then learns merchant memory and backfills
  /// similar merchants. Returns the backfill batch for UI undo.
  List<AiAppliedCategoryChange> applyCategoriesWithMerchantLearning(
    Map<String, String> keyToCanonicalCategory, {
    required List<Transaction> allTransactions,
    required Map<String, String> transactionCategoryAssignments,
    required void Function(Map<String, String>) applyCategoryAssignments,
    required String userNamespace,
  }) {
    applyCategoryAssignments(keyToCanonicalCategory);
    return _learnAndBackfillMerchantMemory(
      keyToCanonicalCategory,
      allTransactions: allTransactions,
      transactionCategoryAssignments: transactionCategoryAssignments,
      applyCategoryAssignments: applyCategoryAssignments,
      userNamespace: userNamespace,
    );
  }

  /// Learns merchant memory from explicit user picks, and backfills matching rows.
  ///
  /// Returns a batch of category changes that can be undone.
  List<AiAppliedCategoryChange> _learnAndBackfillMerchantMemory(
    Map<String, String> keyToCanonicalCategory, {
    required List<Transaction> allTransactions,
    required Map<String, String> transactionCategoryAssignments,
    required void Function(Map<String, String>) applyCategoryAssignments,
    required String userNamespace,
  }) {
    if (keyToCanonicalCategory.isEmpty) return const [];

    // Map merchantKeyLower -> chosen category (last write wins within this save).
    final merchantUpdates = <String, String>{};
    final txByKey = <String, Transaction>{};
    for (final t in allTransactions) {
      txByKey[transactionCategoryKey(t)] = t;
    }
    for (final e in keyToCanonicalCategory.entries) {
      final t = txByKey[e.key];
      if (t == null) continue;
      final mk = transactionMerchantKeyLower(t).trim().toLowerCase();
      if (mk.isEmpty) continue;
      merchantUpdates[mk] = e.value.trim();
    }
    if (merchantUpdates.isEmpty) return const [];

    // Persist merchant memory.
    final nextMemory = Map<String, String>.from(merchantCategoryMemory);
    for (final e in merchantUpdates.entries) {
      final k = e.key.trim().toLowerCase();
      final v = e.value.trim();
      if (k.isEmpty || v.isEmpty) continue;
      nextMemory[k] = v;
    }
    merchantCategoryMemory = nextMemory;
    _persistMerchantCategoryMemory(userNamespace);

    // Backfill: apply to all matching transactions (with undo info).
    final toApply = <String, String>{};
    final undo = <AiAppliedCategoryChange>[];
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final t in allTransactions) {
      final mk = transactionMerchantKeyLower(t).trim().toLowerCase();
      final target = merchantUpdates[mk];
      if (target == null || target.isEmpty) continue;

      final key = transactionCategoryKey(t);
      if (keyToCanonicalCategory.containsKey(key)) {
        continue; // already set explicitly in this save
      }

      final current = transactionCategoryAssignments[key]?.trim();
      if (current != null && current == target) continue;

      toApply[key] = target;
      undo.add(
        AiAppliedCategoryChange(
          key: key,
          previousCategoryId: current,
          newCategoryId: target,
          appliedAtIso: nowIso,
        ),
      );
    }

    if (toApply.isEmpty) return const [];
    applyCategoryAssignments(toApply);
    return undo;
  }
}
