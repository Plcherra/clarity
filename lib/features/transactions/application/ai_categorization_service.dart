import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/storage/ai/ai_suggestion_storage.dart';
import '../data/ai_categorization_service.dart' as data_ai;
import '../domain/spend_categories.dart';

class AiAutoApplyUndoResult {
  const AiAutoApplyUndoResult({
    required this.undone,
    required this.transactionCategoryAssignments,
    required this.categoryOverrides,
    required this.transactionsByAccount,
    required this.activeTransactions,
  });

  final int undone;
  final Map<String, String> transactionCategoryAssignments;
  final Map<String, String> categoryOverrides;
  final Map<String, List<Transaction>> transactionsByAccount;
  final List<Transaction> activeTransactions;
}

class AiCategorizationApplicationService {
  /// CSV import background AI job.
  bool importAiCategorizationRunning = false;
  int importAiProgressCompleted = 0;
  int importAiProgressTotal = 0;

  /// One-shot snack text for ImportAiStatusHost.
  String? importAiSnackMessage;

  // Bump to invalidate cached "empty" suggestions from earlier prompt iterations.
  static const int _aiPromptVersion = 2;

  bool needsImportAiAfterCsvUpload(
    String accountId, {
    required List<Transaction> Function(String accountId)
    uncategorizedImportedRowsForAccount,
  }) {
    return uncategorizedImportedRowsForAccount(accountId.trim()).isNotEmpty;
  }

  String? consumeImportAiSnackMessage() {
    final m = importAiSnackMessage;
    importAiSnackMessage = null;
    return m;
  }

  /// Runs after CSV import: merchant memory first, then GPT in batches.
  Future<void> startBackgroundImportAiCategorization(
    String accountId, {
    required bool importAiEngineConfigured,
    required List<Transaction> Function(String accountId)
    uncategorizedImportedRowsForAccount,
    required Map<String, String> merchantCategoryMemory,
    required Future<void> Function(Map<String, String> prefilled)
    applyPrefilledMerchantChunks,
    required List<String> allowedCategoryPickerLabels,
    required List<AiAppliedCategoryChange> Function(Map<String, String>)
    applyCategoriesWithMerchantLearning,
    required VoidCallback notifyListeners,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final id = accountId.trim();
    if (id.isEmpty) return;
    if (importAiCategorizationRunning) return;

    var unc = uncategorizedImportedRowsForAccount(id);
    final prefilled = <String, String>{};
    for (final t in unc) {
      final k = transactionCategoryKey(t);
      final mk = transactionMerchantKeyLower(t).trim().toLowerCase();
      if (mk.isEmpty) continue;
      final memo = merchantCategoryMemory[mk];
      if (memo != null && memo.trim().isNotEmpty) {
        prefilled[k] = memo.trim();
      }
    }
    await applyPrefilledMerchantChunks(prefilled);

    unc = uncategorizedImportedRowsForAccount(id);
    if (unc.isEmpty) {
      importAiSnackMessage = 'Transactions categorized successfully';
      notifyListeners();
      return;
    }

    if (!importAiEngineConfigured) {
      return;
    }

    importAiCategorizationRunning = true;
    importAiProgressCompleted = 0;
    importAiProgressTotal = unc.length;
    notifyListeners();

    final service = data_ai.AICategorizationService();
    try {
      await service.suggestCategories(
        transactions: unc,
        allowedCategoryIds: allowedCategoryPickerLabels,
        onBatchProgress: (completed, total) {
          importAiProgressCompleted = completed;
          importAiProgressTotal = total;
          notifyListeners();
        },
        onPartialBatch: (partial) async {
          final toApply = <String, String>{};
          for (final e in partial.entries) {
            final v = e.value?.trim();
            if (v != null && v.isNotEmpty) {
              toApply[e.key] = v;
            }
          }
          if (toApply.isNotEmpty) {
            applyCategoriesWithMerchantLearning(toApply);
          }
          await Future<void>.delayed(Duration.zero);
        },
      );
      importAiSnackMessage = 'Transactions categorized successfully';
    } on data_ai.MissingOpenAiApiKeyException {
      importAiSnackMessage =
          'Add OPENAI_API_KEY to your .env file to use AI categorization.';
    } catch (e) {
      importAiSnackMessage = 'Could not categorize transactions: $e';
    } finally {
      service.close();
      importAiCategorizationRunning = false;
      notifyListeners();
    }
  }

  Future<({int applied, int queuedForReview})>
  autoCategorizeGlobalUncategorized({
    required data_ai.AICategorizationService service,
    required List<String> allowedCategoryPickerLabels,
    required List<Transaction> uncategorizedImportedRowsGlobal,
    required Map<String, String> transactionCategoryAssignments,
    required Map<String, AiCategorySuggestion> aiCategorySuggestions,
    required void Function(Map<String, AiCategorySuggestion> suggestions)
    setAiCategorySuggestions,
    required Future<void> Function() persistAiCategorySuggestions,
    required void Function(Map<String, String> keyToCanonicalCategory)
    bulkSetCategoryOverrides,
    double autoApplyConfidenceThreshold = 0.90,
  }) async {
    final allowed = allowedCategoryPickerLabels;
    final unc = uncategorizedImportedRowsGlobal;
    if (unc.isEmpty) return (applied: 0, queuedForReview: 0);

    final expectedKeys = unc.map(transactionCategoryKey).toSet();

    // Never override manual choices.
    final toFetch = <Transaction>[];
    for (final t in unc) {
      final k = transactionCategoryKey(t);
      final alreadyAssigned = transactionCategoryAssignments[k]?.trim();
      if (alreadyAssigned != null && alreadyAssigned.isNotEmpty) continue;

      final cached = aiCategorySuggestions[k];
      if (cached != null && cached.promptVersion == _aiPromptVersion) {
        final cat = cached.suggestedCanonical?.trim();
        final hasUsefulSuggestion =
            cat != null && cat.isNotEmpty && cached.confidence > 0.0;
        if (hasUsefulSuggestion) continue;
      }
      toFetch.add(t);
    }

    if (kDebugMode) {
      debugPrint(
        '[Clarity][AI] uncategorized=${unc.length} toFetch=${toFetch.length} '
        'allowed=${allowed.length} promptV=$_aiPromptVersion',
      );
    }

    var nextSuggestions = aiCategorySuggestions;
    if (toFetch.isNotEmpty) {
      final fetched = await service.suggestCategoriesWithConfidence(
        transactions: toFetch,
        allowedCategoryIds: allowed,
        promptVersion: _aiPromptVersion,
      );
      if (fetched.isNotEmpty) {
        nextSuggestions = {...nextSuggestions, ...fetched};
        setAiCategorySuggestions(nextSuggestions);
        await persistAiCategorySuggestions();
      }
      if (kDebugMode) {
        debugPrint('[Clarity][AI] fetched=${fetched.length}');
      }
    }

    final apply = <String, String>{};
    final batch = <AiAppliedCategoryChange>[];
    var review = 0;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final k in expectedKeys) {
      final alreadyAssigned = transactionCategoryAssignments[k]?.trim();
      if (alreadyAssigned != null && alreadyAssigned.isNotEmpty) continue;

      final s = nextSuggestions[k];
      if (s == null || s.promptVersion != _aiPromptVersion) continue;
      final cat = s.suggestedCanonical?.trim();
      if (cat == null || cat.isEmpty) continue;
      if (!allowed.contains(cat)) continue;

      if (s.confidence >= autoApplyConfidenceThreshold) {
        apply[k] = cat;
        batch.add(
          AiAppliedCategoryChange(
            key: k,
            previousCategoryId: null,
            newCategoryId: cat,
            appliedAtIso: nowIso,
          ),
        );
      } else {
        review += 1;
      }
    }

    if (apply.isNotEmpty) {
      bulkSetCategoryOverrides(apply);
      await saveLastAiApplyBatch(batch);
    }

    return (applied: apply.length, queuedForReview: review);
  }

  Future<AiAutoApplyUndoResult> undoLastAiAutoApply({
    required Map<String, String> transactionCategoryAssignments,
    required Map<String, String> categoryOverrides,
    required Map<String, List<Transaction>> transactionsByAccount,
    required String? activeAccountId,
  }) async {
    final batch = await loadLastAiApplyBatch();
    if (batch.isEmpty) {
      return AiAutoApplyUndoResult(
        undone: 0,
        transactionCategoryAssignments: transactionCategoryAssignments,
        categoryOverrides: categoryOverrides,
        transactionsByAccount: transactionsByAccount,
        activeTransactions: activeAccountId == null
            ? const []
            : List.unmodifiable(
                transactionsByAccount[activeAccountId] ?? const [],
              ),
      );
    }

    final nextAssign = Map<String, String>.from(transactionCategoryAssignments);
    final nextOv = Map<String, String>.from(categoryOverrides);

    var undone = 0;
    for (final c in batch) {
      final current = nextAssign[c.key]?.trim();
      if (current == null || current.isEmpty) continue;
      if (current != c.newCategoryId) continue;

      if (c.previousCategoryId == null ||
          c.previousCategoryId!.trim().isEmpty) {
        nextAssign.remove(c.key);
        nextOv.remove(c.key);
      } else {
        nextAssign[c.key] = c.previousCategoryId!.trim();
        nextOv[c.key] = c.previousCategoryId!.trim();
      }
      undone += 1;
    }

    Transaction applyCategory(Transaction x) {
      final k = transactionCategoryKey(x);
      final cat = nextAssign[k];
      return Transaction(
        date: x.date,
        description: x.description,
        amount: x.amount,
        accountId: x.accountId,
        category: x.category,
        balanceAfter: x.balanceAfter,
        categoryId: cat,
        importId: x.importId,
        fingerprint: x.fingerprint,
        financialRole: x.financialRole,
      );
    }

    final nextByAccount = <String, List<Transaction>>{};
    for (final e in transactionsByAccount.entries) {
      nextByAccount[e.key] = List.unmodifiable(
        e.value.map(applyCategory).toList(),
      );
    }

    final activeTransactions = activeAccountId == null
        ? const <Transaction>[]
        : List<Transaction>.unmodifiable(
            nextByAccount[activeAccountId] ?? const <Transaction>[],
          );

    await saveLastAiApplyBatch(const []);
    return AiAutoApplyUndoResult(
      undone: undone,
      transactionCategoryAssignments: nextAssign,
      categoryOverrides: nextOv,
      transactionsByAccount: nextByAccount,
      activeTransactions: activeTransactions,
    );
  }
}
