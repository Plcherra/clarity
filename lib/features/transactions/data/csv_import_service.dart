import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase/supabase_records.dart';
import '../../accounts/data/account_service.dart';
import '../../categories/data/category_service.dart';
import '../../categories/domain/category_normalization.dart';
import '../domain/spend_categories.dart';
import '../domain/transaction_fingerprint.dart';
import 'csv_parser.dart';
import 'openai_proxy_client.dart';
import 'transaction_service.dart';

const int _categorizationRequestBatchSize = 100;

typedef _FetchAccounts = Future<List<Account>> Function();
typedef _FetchTransactions =
    Future<List<TransactionRecord>> Function({String? accountId});
typedef _CreateTransactions =
    Future<List<TransactionRecord>> Function(
      List<TransactionCreateInput> transactions,
    );
typedef _FetchCategories = Future<List<CategoryRecord>> Function();
typedef _CreateCategory =
    Future<CategoryRecord> Function({
      required String name,
      required String type,
      String? color,
      String? icon,
    });
typedef _UpdateTransactionsCategory =
    Future<void> Function({
      required List<String> ids,
      required String categoryId,
    });
typedef _CategorizeTransactions =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

enum CsvImportStage {
  parsing,
  savingTransactions,
  categorizingWithAi,
  applyingCategories,
  refreshing,
  complete,
  failed,
}

class CsvImportBatchSummary {
  const CsvImportBatchSummary({
    required this.importId,
    required this.transactionCount,
    required this.importedAtUtc,
  });

  final String importId;
  final int transactionCount;
  final DateTime? importedAtUtc;
}

class CsvImportResult {
  const CsvImportResult({
    required this.accountId,
    required this.importId,
    required this.parsedCount,
    required this.insertedCount,
    required this.skippedDuplicateCount,
    required this.categorizedCount,
    required this.aiSucceeded,
    required this.aiErrorMessage,
    required this.spendReference,
    required this.diagnostics,
  });

  final String accountId;
  final String importId;
  final int parsedCount;
  final int insertedCount;
  final int skippedDuplicateCount;
  final int categorizedCount;
  final bool aiSucceeded;
  final String? aiErrorMessage;
  final DateTime spendReference;
  final CsvParseDiagnostics? diagnostics;
}

class CsvImportProgress {
  const CsvImportProgress({
    required this.stage,
    required this.value,
    required this.message,
    this.result,
    this.error,
  });

  factory CsvImportProgress.complete(CsvImportResult result) =>
      CsvImportProgress(
        stage: CsvImportStage.complete,
        value: 1,
        message: result.aiSucceeded
            ? 'Import complete.'
            : 'Imported transactions and marked uncategorized rows Unknown.',
        result: result,
      );

  factory CsvImportProgress.failed(Object error) => CsvImportProgress(
    stage: CsvImportStage.failed,
    value: 1,
    message: 'Could not import this CSV: $error',
    error: error,
  );

  final CsvImportStage stage;
  final double value;
  final String message;
  final CsvImportResult? result;
  final Object? error;
}

class CsvImportService {
  CsvImportService({
    required AccountService accountService,
    required TransactionService transactionService,
    required CategoryService categoryService,
    required OpenAiProxyClient openAiClient,
  }) : this._(
         fetchAccounts: accountService.fetchAccounts,
         fetchTransactions: transactionService.fetchTransactions,
         createTransactions: transactionService.createTransactions,
         fetchCategories: categoryService.fetchCategories,
         createCategory: categoryService.createCategory,
         updateTransactionsCategory:
             transactionService.updateTransactionsCategory,
         isAiConfigured: () => openAiClient.isConfigured,
         categorizeTransactions: openAiClient.categorizeTransactions,
       );

  @visibleForTesting
  CsvImportService.test({
    required Future<List<Account>> Function() fetchAccounts,
    required Future<List<TransactionRecord>> Function({String? accountId})
    fetchTransactions,
    required Future<List<TransactionRecord>> Function(
      List<TransactionCreateInput> transactions,
    )
    createTransactions,
    required Future<List<CategoryRecord>> Function() fetchCategories,
    required Future<CategoryRecord> Function({
      required String name,
      required String type,
      String? color,
      String? icon,
    })
    createCategory,
    required Future<void> Function({
      required List<String> ids,
      required String categoryId,
    })
    updateTransactionsCategory,
    required bool Function() isAiConfigured,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> body)
    categorizeTransactions,
  }) : this._(
         fetchAccounts: fetchAccounts,
         fetchTransactions: fetchTransactions,
         createTransactions: createTransactions,
         fetchCategories: fetchCategories,
         createCategory: createCategory,
         updateTransactionsCategory: updateTransactionsCategory,
         isAiConfigured: isAiConfigured,
         categorizeTransactions: categorizeTransactions,
       );

  CsvImportService._({
    required _FetchAccounts fetchAccounts,
    required _FetchTransactions fetchTransactions,
    required _CreateTransactions createTransactions,
    required _FetchCategories fetchCategories,
    required _CreateCategory createCategory,
    required _UpdateTransactionsCategory updateTransactionsCategory,
    required bool Function() isAiConfigured,
    required _CategorizeTransactions categorizeTransactions,
  }) : _fetchAccounts = fetchAccounts,
       _fetchTransactions = fetchTransactions,
       _createTransactions = createTransactions,
       _fetchCategories = fetchCategories,
       _createCategory = createCategory,
       _updateTransactionsCategory = updateTransactionsCategory,
       _isAiConfigured = isAiConfigured,
       _categorizeTransactions = categorizeTransactions;

  final _FetchAccounts _fetchAccounts;
  final _FetchTransactions _fetchTransactions;
  final _CreateTransactions _createTransactions;
  final _FetchCategories _fetchCategories;
  final _CreateCategory _createCategory;
  final _UpdateTransactionsCategory _updateTransactionsCategory;
  final bool Function() _isAiConfigured;
  final _CategorizeTransactions _categorizeTransactions;

  Stream<CsvImportProgress> importAndCategorize(
    File csvFile, {
    required String accountId,
    Future<void> Function(CsvImportResult result)? refreshAfterImport,
  }) async* {
    final id = accountId.trim();
    try {
      if (id.isEmpty) {
        throw const FormatException('An account must be selected.');
      }

      yield const CsvImportProgress(
        stage: CsvImportStage.parsing,
        value: 0.02,
        message: 'Reading CSV...',
      );
      final utf8Text = utf8.decode(
        await csvFile.readAsBytes(),
        allowMalformed: true,
      );
      final parsed = parseBankCsv(utf8Text);

      final accounts = await _fetchAccounts();
      if (!accounts.any((account) => account.id == id)) {
        throw const FormatException('Unknown account.');
      }

      final importId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      final spendReference = DateTime.now();

      yield CsvImportProgress(
        stage: CsvImportStage.savingTransactions,
        value: 0.12,
        message: 'Checking existing transactions...',
      );
      final existingRecords = await _fetchTransactions(accountId: id);
      final existingFingerprints = {
        for (final record in existingRecords)
          transactionFingerprint(_transactionFromRecord(record)),
      };
      final unknownCategoryId = await _ensureUnknownCategoryId();

      final rowsToInsert = <TransactionCreateInput>[];
      var skippedDuplicateCount = 0;
      for (final transaction in parsed.transactions) {
        final stamped = Transaction(
          date: transaction.date,
          description: transaction.description,
          amount: transaction.amount,
          accountId: id,
          category: transaction.category,
          balanceAfter: transaction.balanceAfter,
        );
        final fingerprint = transactionFingerprint(stamped);
        if (existingFingerprints.contains(fingerprint)) {
          skippedDuplicateCount += 1;
          continue;
        }
        existingFingerprints.add(fingerprint);
        rowsToInsert.add(
          TransactionCreateInput(
            accountId: id,
            categoryId: unknownCategoryId,
            amount: stamped.amount.abs(),
            type: stamped.amount < 0 ? 'expense' : 'income',
            description: stamped.description,
            date: stamped.date,
            merchant: stamped.description,
            importedFromCsv: true,
            importId: importId,
          ),
        );
      }

      yield CsvImportProgress(
        stage: CsvImportStage.savingTransactions,
        value: 0.28,
        message: 'Saving transactions...',
      );
      final insertedRecords = await _createTransactions(rowsToInsert);

      var aiSucceeded = true;
      String? aiErrorMessage;
      var suggestedCategoryByTransactionId = <String, String>{};

      if (insertedRecords.isNotEmpty) {
        yield CsvImportProgress(
          stage: CsvImportStage.categorizingWithAi,
          value: 0.55,
          message: 'Categorizing with AI...',
        );
        final suggestions = <String, String>{};
        final aiErrors = <Object>[];
        final batches = _chunks(
          insertedRecords,
          _categorizationRequestBatchSize,
        );
        for (var i = 0; i < batches.length; i += 1) {
          final batch = batches[i];
          try {
            suggestions.addAll(await _categorizeInsertedRows(batch));
          } on Object catch (error) {
            aiErrors.add(error);
          }
          final completed = i + 1;
          yield CsvImportProgress(
            stage: CsvImportStage.categorizingWithAi,
            value: 0.55 + (completed / batches.length) * 0.25,
            message:
                'Categorizing with AI... $completed/${batches.length} batches',
          );
        }
        suggestedCategoryByTransactionId = suggestions;
        if (aiErrors.isNotEmpty) {
          aiSucceeded = false;
          aiErrorMessage = '${aiErrors.first}';
        }

        yield CsvImportProgress(
          stage: CsvImportStage.applyingCategories,
          value: 0.82,
          message: aiSucceeded
              ? 'Applying categories...'
              : 'AI failed. Marking transactions Unknown...',
        );
        try {
          await _applyCategories(
            insertedRecords,
            suggestedCategoryByTransactionId,
          );
        } on Object catch (error) {
          aiSucceeded = false;
          aiErrorMessage ??= '$error';
        }
      }

      final result = CsvImportResult(
        accountId: id,
        importId: importId,
        parsedCount: parsed.transactions.length,
        insertedCount: insertedRecords.length,
        skippedDuplicateCount: skippedDuplicateCount,
        categorizedCount: insertedRecords.length,
        aiSucceeded: aiSucceeded,
        aiErrorMessage: aiErrorMessage,
        spendReference: spendReference,
        diagnostics: parsed.diagnostics,
      );
      if (refreshAfterImport != null) {
        yield const CsvImportProgress(
          stage: CsvImportStage.refreshing,
          value: 0.96,
          message: 'Refreshing dashboard...',
        );
        await refreshAfterImport(result);
      }
      yield CsvImportProgress.complete(result);
    } on Object catch (error) {
      yield CsvImportProgress.failed(error);
      rethrow;
    }
  }

  Future<Map<String, String>> _categorizeInsertedRows(
    List<TransactionRecord> records,
  ) async {
    if (!_isAiConfigured()) {
      throw const OpenAiProxyUnavailableException();
    }
    final response = await _categorizeTransactions({
      'allowedCategories': kSelectableSpendCategories,
      'transactions': [
        for (final record in records)
          {
            'key': record.id,
            'date': record.date.toIso8601String().split('T').first,
            'amount': _signedAmount(record),
            'description': record.description ?? record.merchant ?? '',
          },
      ],
    });
    final suggestions = _parseCategorizationResponse(response);
    final errors = response['errors'];
    if (errors is List && errors.isNotEmpty) {
      final hasNonUnknownSuggestion = suggestions.values.any(
        (categoryName) =>
            normalizedCategoryKey(categoryName) !=
            normalizedCategoryKey(kUnknownCategoryName),
      );
      if (!hasNonUnknownSuggestion) {
        throw FormatException(
          'AI categorization failed for all chunks: ${errors.first}',
        );
      }
    }
    return suggestions;
  }

  Map<String, String> _parseCategorizationResponse(
    Map<String, dynamic> response,
  ) {
    final rawSuggestions = response['suggestions'];
    if (rawSuggestions is! List) {
      throw const FormatException(
        'AI categorization response missing suggestions.',
      );
    }
    final out = <String, String>{};
    final duplicateKeys = <String>{};
    for (final suggestion in rawSuggestions) {
      if (suggestion is! Map) continue;
      final key = suggestion['key'];
      final categoryName = suggestion['categoryName'];
      if (key is! String || key.trim().isEmpty) continue;
      final cleanedKey = key.trim();
      if (out.containsKey(cleanedKey)) {
        duplicateKeys.add(cleanedKey);
        out[cleanedKey] = kUnknownCategoryName;
        continue;
      }
      if (categoryName is! String || categoryName.trim().isEmpty) {
        out[cleanedKey] = kUnknownCategoryName;
        continue;
      }
      final normalized = normalizeCategoryName(categoryName);
      out[cleanedKey] = normalized?.displayName ?? kUnknownCategoryName;
    }
    for (final key in duplicateKeys) {
      out[key] = kUnknownCategoryName;
    }
    return out;
  }

  Future<void> _applyCategories(
    List<TransactionRecord> insertedRecords,
    Map<String, String> suggestedCategoryByTransactionId,
  ) async {
    if (insertedRecords.isEmpty) return;
    final categoryNames = <String>{kUnknownCategoryName};
    for (final record in insertedRecords) {
      final name = suggestedCategoryByTransactionId[record.id]?.trim();
      categoryNames.add(
        name == null || name.isEmpty ? kUnknownCategoryName : name,
      );
    }
    final categoryIdByName = await _ensureCategories(categoryNames);
    final unknownCategoryId =
        categoryIdByName[normalizedCategoryKey(kUnknownCategoryName)];
    if (unknownCategoryId == null || unknownCategoryId.trim().isEmpty) {
      throw StateError('Could not resolve the Unknown category.');
    }
    final idsByCategoryId = <String, List<String>>{};
    for (final record in insertedRecords) {
      if (record.categoryId == null || record.categoryId!.trim().isEmpty) {
        throw StateError(
          'Inserted transaction is missing the Unknown fallback category.',
        );
      }
      final name =
          suggestedCategoryByTransactionId[record.id]?.trim() ??
          kUnknownCategoryName;
      final normalizedName = name.isEmpty ? kUnknownCategoryName : name;
      final normalizedCategory = normalizeCategoryName(normalizedName);
      final categoryId =
          categoryIdByName[normalizedCategory?.normalizedName] ??
          unknownCategoryId;
      if (record.categoryId == categoryId) continue;
      idsByCategoryId.putIfAbsent(categoryId, () => <String>[]).add(record.id);
    }
    for (final entry in idsByCategoryId.entries) {
      await _updateTransactionsCategory(
        ids: entry.value,
        categoryId: entry.key,
      );
    }
  }

  Future<Map<String, String>> _ensureCategories(
    Set<String> categoryNames,
  ) async {
    final existing = await _fetchCategories();
    final out = <String, String>{
      for (final category in existing)
        categoryRecordKey(
          name: category.name,
          normalizedName: category.normalizedName,
        ): category.id,
    };
    for (final rawName in categoryNames) {
      final normalized =
          normalizeCategoryName(rawName) ??
          normalizeCategoryName(kUnknownCategoryName);
      if (normalized == null) {
        throw StateError('Could not normalize the Unknown category.');
      }
      final key = normalized.normalizedName;
      if (out.containsKey(key)) continue;
      final created = await _createCategory(
        name: normalized.displayName,
        type: 'expense',
      );
      out[key] = created.id;
    }
    return out;
  }

  Future<String> _ensureUnknownCategoryId() async {
    final categoryIdByName = await _ensureCategories({kUnknownCategoryName});
    final unknownCategoryId =
        categoryIdByName[normalizedCategoryKey(kUnknownCategoryName)];
    if (unknownCategoryId == null || unknownCategoryId.trim().isEmpty) {
      throw StateError('Could not resolve the Unknown category.');
    }
    return unknownCategoryId;
  }
}

List<List<T>> _chunks<T>(List<T> items, int size) {
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    final end = i + size > items.length ? items.length : i + size;
    out.add(items.sublist(i, end));
  }
  return out;
}

Transaction _transactionFromRecord(TransactionRecord record) {
  return Transaction(
    date: record.date,
    description: record.description ?? record.merchant ?? '',
    amount: _signedAmount(record),
    accountId: record.accountId,
    categoryId: record.categoryId,
    importId: record.importId ?? (record.importedFromCsv ? 'csv' : null),
    fingerprint: record.id,
    financialRole: record.type.trim().toLowerCase() == 'income'
        ? FinancialRole.income
        : FinancialRole.expense,
  );
}

double _signedAmount(TransactionRecord record) {
  return switch (record.type.trim().toLowerCase()) {
    'expense' => -record.amount.abs(),
    'income' => record.amount.abs(),
    _ => record.amount,
  };
}
