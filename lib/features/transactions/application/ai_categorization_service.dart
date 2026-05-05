import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../data/ai_categorization_service.dart' as data_ai;
import '../domain/spend_categories.dart';

class AiCategorizationApplicationService {
  /// Unified CSV import progress: upload first, then AI categorization.
  bool importAiCategorizationRunning = false;
  int importAiProgressCompleted = 0;
  int importAiProgressTotal = 100;
  String importProgressMessage = 'Uploading transactions...';
  bool _aiCategorizationRunning = false;

  /// One-shot snack text for ImportAiStatusHost.
  String? importAiSnackMessage;

  void startCsvImportProgress({required VoidCallback notifyStatusChanged}) {
    importAiCategorizationRunning = true;
    importAiProgressCompleted = 0;
    importAiProgressTotal = 100;
    importProgressMessage = 'Uploading transactions...';
    importAiSnackMessage = null;
    notifyStatusChanged();
  }

  void updateCsvUploadProgress({
    required int processedRows,
    required int totalRows,
    required VoidCallback notifyStatusChanged,
  }) {
    importAiCategorizationRunning = true;
    importAiProgressTotal = 100;
    importProgressMessage = 'Uploading transactions...';
    if (totalRows <= 0) {
      importAiProgressCompleted = 50;
    } else {
      importAiProgressCompleted = ((processedRows / totalRows) * 50)
          .round()
          .clamp(0, 50);
    }
    notifyStatusChanged();
  }

  void finishCsvImportProgress({
    required VoidCallback notifyStatusChanged,
    String fallbackSnackMessage = 'Import complete.',
  }) {
    importAiProgressCompleted = 100;
    importAiProgressTotal = 100;
    importProgressMessage = 'Import complete.';
    importAiCategorizationRunning = false;
    importAiSnackMessage ??= fallbackSnackMessage;
    notifyStatusChanged();
  }

  void stopCsvImportProgress({required VoidCallback notifyStatusChanged}) {
    importAiCategorizationRunning = false;
    notifyStatusChanged();
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
    pendingImportedRowsForAccount,
    required Map<String, String> merchantCategoryMemory,
    required Future<void> Function(Map<String, String> prefilled)
    applyPrefilledMerchantChunks,
    required List<String> allowedCategoryPickerLabels,
    required Future<void> Function(Map<String, String>) applyCategories,
    required VoidCallback notifyStatusChanged,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final id = accountId.trim();
    if (id.isEmpty) return;
    if (_aiCategorizationRunning) return;

    var unc = pendingImportedRowsForAccount(id);
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

    unc = pendingImportedRowsForAccount(id);
    if (unc.isEmpty) {
      importAiSnackMessage = 'Transactions categorized successfully';
      notifyStatusChanged();
      return;
    }

    if (!importAiEngineConfigured) {
      importAiSnackMessage =
          'Sign in and configure the Supabase AI Edge Function secret to use AI categorization.';
      notifyStatusChanged();
      return;
    }

    _aiCategorizationRunning = true;
    importAiCategorizationRunning = true;
    importProgressMessage = 'Categorizing with AI...';
    importAiProgressCompleted = 50;
    importAiProgressTotal = 100;
    notifyStatusChanged();

    final service = data_ai.AICategorizationService();
    try {
      await service.suggestCategories(
        transactions: unc,
        allowedCategoryIds: allowedCategoryPickerLabels,
        onBatchProgress: (completed, total) {
          importProgressMessage = 'Categorizing with AI...';
          importAiProgressCompleted = total > 0
              ? (50 + ((completed / total) * 50).round()).clamp(50, 99)
              : 50;
          importAiProgressTotal = 100;
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
            await applyCategories(toApply);
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
      _aiCategorizationRunning = false;
      notifyStatusChanged();
    }
  }
}
