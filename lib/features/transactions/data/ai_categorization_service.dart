import 'dart:async';
import 'dart:convert';

import '../../../core/models/models.dart';
import '../domain/spend_categories.dart';
import 'openai_proxy_client.dart';

export 'openai_proxy_client.dart'
    show OpenAiProxyClient, OpenAiProxyUnavailableException;

const String openAiModel = 'gpt-4o-mini';

const int kAiCategorizationBatchSize = 200;
const int kAiCategorizationMaxConcurrency = 4;

/// Maps model output to an allowed canonical label, or null (leave uncategorized).
String? normalizeSuggestionToAllowed(
  String? raw,
  List<String> allowedCanonicals,
) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  for (final a in allowedCanonicals) {
    if (a.trim().toLowerCase() == lower) return a;
  }
  return null;
}

/// POST body is parsed; expects `choices[0].message.content` JSON with `suggestions` array.
Map<String, String?> parseSuggestionsFromResponseContent(
  String messageContent,
  List<String> allowedCanonicals,
  Set<String> expectedKeys,
) {
  final decoded = jsonDecode(messageContent);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('OpenAI response JSON is not an object.');
  }
  final rawList = decoded['suggestions'];
  if (rawList is! List) {
    throw const FormatException('OpenAI response missing suggestions array.');
  }
  final out = <String, String?>{};
  for (final e in rawList) {
    if (e is! Map) continue;
    final key = e['key'];
    final cat = e['categoryId'];
    if (key is! String || key.isEmpty) continue;
    if (!expectedKeys.contains(key)) continue;
    if (cat is! String) {
      out[key] = null;
      continue;
    }
    out[key] = normalizeSuggestionToAllowed(cat, allowedCanonicals);
  }
  return out;
}

/// Strips optional ```json … ``` wrappers some models emit around JSON.
String unwrapOpenAiMessageContent(String raw) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    final nl = s.indexOf('\n');
    if (nl != -1) {
      s = s.substring(nl + 1);
    }
    if (s.endsWith('```')) {
      s = s.substring(0, s.lastIndexOf('```')).trim();
    }
  }
  return s;
}

class AICategorizationService {
  AICategorizationService({OpenAiProxyClient? openAiClient})
    : _client = openAiClient ?? SupabaseOpenAiProxyClient();

  final OpenAiProxyClient _client;

  /// Parallel batches; returns one map entry per [transactions] key (may be null).
  Future<Map<String, String?>> suggestCategories({
    required List<Transaction> transactions,
    required List<String> allowedCategoryIds,
    void Function(int completed, int total)? onBatchProgress,
    Future<void> Function(Map<String, String?>)? onPartialBatch,
  }) async {
    if (!_client.isConfigured) {
      throw const OpenAiProxyUnavailableException();
    }
    if (transactions.isEmpty) return {};
    if (allowedCategoryIds.isEmpty) {
      throw const FormatException(
        'No categories are available to assign. Check category settings in the app.',
      );
    }
    final allowed = List<String>.from(allowedCategoryIds);
    final batches = <List<Transaction>>[];
    for (var i = 0; i < transactions.length; i += kAiCategorizationBatchSize) {
      batches.add(
        transactions.sublist(
          i,
          i + kAiCategorizationBatchSize > transactions.length
              ? transactions.length
              : i + kAiCategorizationBatchSize,
        ),
      );
    }
    final out = <String, String?>{};
    var completed = 0;
    var nextBatchIndex = 0;

    Future<void> worker() async {
      while (true) {
        final batchIndex = nextBatchIndex;
        if (batchIndex >= batches.length) return;
        nextBatchIndex += 1;

        final batch = batches[batchIndex];
        final partial = await _suggestBatch(
          batch: batch,
          allowedCategoryIds: allowed,
        );
        out.addAll(partial);
        if (onPartialBatch != null) {
          await onPartialBatch(partial);
          await Future<void>.delayed(Duration.zero);
        }
        completed += batch.length;
        onBatchProgress?.call(completed, transactions.length);
      }
    }

    final workerCount = batches.length < kAiCategorizationMaxConcurrency
        ? batches.length
        : kAiCategorizationMaxConcurrency;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    for (final t in transactions) {
      final k = transactionCategoryKey(t);
      out.putIfAbsent(k, () => null);
    }
    return out;
  }

  Future<Map<String, String?>> _suggestBatch({
    required List<Transaction> batch,
    required List<String> allowedCategoryIds,
  }) async {
    if (batch.isEmpty) return {};
    final expectedKeys = batch.map(transactionCategoryKey).toSet();
    final lines = <Map<String, dynamic>>[];
    for (final t in batch) {
      lines.add({
        'key': transactionCategoryKey(t),
        'date': t.date.toIso8601String(),
        'amount': t.amount,
        'description': t.description,
        if (t.category != null && t.category!.trim().isNotEmpty)
          'bankCategory': t.category,
      });
    }
    final allowedJson = jsonEncode(allowedCategoryIds);
    final linesJson = jsonEncode(lines);
    final system =
        'You categorize bank transactions. Respond with JSON only using this '
        'exact shape: {"suggestions":[{"key":"<copied from input>","categoryId":"..."}]} '
        'Each categoryId MUST be exactly one string from the allowed list (character-for-character match). '
        'Return exactly one suggestion object per input line (same key). '
        'If uncertain, pick the closest allowed category.';
    final user =
        'Allowed categories (JSON array): $allowedJson\n\n'
        'Transactions (JSON array of objects with key, date, amount, description, optional bankCategory):\n'
        '$linesJson';

    final body = <String, dynamic>{
      'model': openAiModel,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    };

    final outer = await _client.createChatCompletion(body);
    final choices = outer['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('OpenAI response has no choices.');
    }
    final first = choices.first;
    if (first is! Map) {
      throw const FormatException('OpenAI choice is not an object.');
    }
    final msg = first['message'];
    if (msg is! Map) {
      throw const FormatException('OpenAI message is not an object.');
    }
    final contentRaw = msg['content'];
    if (contentRaw is! String || contentRaw.isEmpty) {
      throw const FormatException('OpenAI message content is empty.');
    }
    final content = unwrapOpenAiMessageContent(contentRaw);

    Map<String, String?> parsed;
    try {
      parsed = parseSuggestionsFromResponseContent(
        content,
        allowedCategoryIds,
        expectedKeys,
      );
    } on FormatException catch (e) {
      throw FormatException('Could not parse AI category JSON: ${e.message}');
    }
    final out = <String, String?>{};
    for (final t in batch) {
      final k = transactionCategoryKey(t);
      out[k] = parsed[k];
    }
    return out;
  }

  void close() {
    _client.close();
  }
}
