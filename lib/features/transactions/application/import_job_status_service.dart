import 'package:flutter/foundation.dart';

import '../data/csv_import_service.dart';

class ImportJobStatusService {
  bool importRunning = false;
  int importProgressCompleted = 0;
  int importProgressTotal = 100;
  String importProgressMessage = 'Uploading transactions...';

  String? importSnackMessage;
  String? persistentImportMessage;
  bool persistentImportMessageIsError = false;

  void applyCsvImportProgress(
    CsvImportProgress progress, {
    required VoidCallback notifyStatusChanged,
  }) {
    importProgressCompleted = (progress.value * 100).round().clamp(0, 100);
    importProgressTotal = 100;
    importProgressMessage = progress.message;

    switch (progress.stage) {
      case CsvImportStage.complete:
        importRunning = false;
        final result = progress.result;
        importSnackMessage = result == null || result.aiSucceeded
            ? 'Import complete.'
            : 'Imported ${result.insertedCount} transactions. AI failed; marked them Unknown.';
        persistentImportMessage = result == null || result.aiSucceeded
            ? null
            : 'Imported ${result.insertedCount} transactions, but AI categorization failed. Saved rows were assigned to Unknown.';
        persistentImportMessageIsError = result != null && !result.aiSucceeded;
      case CsvImportStage.failed:
        importRunning = false;
        importSnackMessage = progress.message;
        persistentImportMessage = progress.message;
        persistentImportMessageIsError = true;
      case CsvImportStage.parsing:
      case CsvImportStage.savingTransactions:
      case CsvImportStage.categorizingWithAi:
      case CsvImportStage.applyingCategories:
      case CsvImportStage.refreshing:
        importRunning = true;
        importSnackMessage = null;
        persistentImportMessage = null;
        persistentImportMessageIsError = false;
    }

    notifyStatusChanged();
  }

  String? consumeImportSnackMessage() {
    final message = importSnackMessage;
    importSnackMessage = null;
    return message;
  }

  void dismissPersistentImportMessage({
    required VoidCallback notifyStatusChanged,
  }) {
    persistentImportMessage = null;
    persistentImportMessageIsError = false;
    notifyStatusChanged();
  }

  void clear({required VoidCallback notifyStatusChanged}) {
    importRunning = false;
    importProgressCompleted = 0;
    importProgressTotal = 100;
    importProgressMessage = 'Uploading transactions...';
    importSnackMessage = null;
    persistentImportMessage = null;
    persistentImportMessageIsError = false;
    notifyStatusChanged();
  }
}
