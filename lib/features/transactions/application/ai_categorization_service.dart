import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../data/ai_categorization_service.dart' as data_ai;
import '../domain/spend_categories.dart';

class AiCategorizationApplicationService {
  /// CSV import background AI job.
  bool importAiCategorizationRunning = false;
  int importAiProgressCompleted = 0;
  int importAiProgressTotal = 0;

  /// One-shot snack text for ImportAiStatusHost.
  String? importAiSnackMessage;

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
    required void Function(Map<String, String>) applyCategories,
    required VoidCallback notifyStatusChanged,
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
      notifyStatusChanged();
      return;
    }

    if (!importAiEngineConfigured) {
      return;
    }

    importAiCategorizationRunning = true;
    importAiProgressCompleted = 0;
    importAiProgressTotal = unc.length;
    notifyStatusChanged();

    final service = data_ai.AICategorizationService();
    try {
      await service.suggestCategories(
        transactions: unc,
        allowedCategoryIds: allowedCategoryPickerLabels,
        onBatchProgress: (completed, total) {
          importAiProgressCompleted = completed;
          importAiProgressTotal = total;
          notifyStatusChanged();
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
            applyCategories(toApply);
          }
          await Future<void>.delayed(Duration.zero);
        },
      );
      importAiSnackMessage = 'Transactions categorized successfully';
    } on data_ai.OpenAiProxyUnavailableException {
      importAiSnackMessage =
          'Sign in and configure the Supabase AI Edge Function secret to use AI categorization.';
    } catch (e) {
      importAiSnackMessage = 'Could not categorize transactions: $e';
    } finally {
      service.close();
      importAiCategorizationRunning = false;
      notifyStatusChanged();
    }
  }
}
