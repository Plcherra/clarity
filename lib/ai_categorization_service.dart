import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'models.dart';
import 'spend_categories.dart';

const String _openAiChatCompletionsUrl =
    'https://api.openai.com/v1/chat/completions';

const String openAiModel = 'gpt-4o-mini';

const int _defaultBatchSize = 32;

/// Thrown when `OPENAI_API_KEY` from `.env` is missing or empty.
class MissingOpenAiApiKeyException implements Exception {
  @override
  String toString() =>
      'OpenAI API key is not configured. Add OPENAI_API_KEY to the `.env` file '
      'in the project root (see README or team docs).';
}

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

class AICategorizationService {
  AICategorizationService({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// Sequential batches; returns one map entry per [transactions] key (may be null).
  Future<Map<String, String?>> suggestCategories({
    required List<Transaction> transactions,
    required List<String> allowedCategoryIds,
    void Function(int completed, int total)? onBatchProgress,
  }) async {
    if (Constants.openAIKey.isEmpty) {
      throw MissingOpenAiApiKeyException();
    }
    if (transactions.isEmpty) return {};
    final allowed = List<String>.from(allowedCategoryIds);
    final batches = <List<Transaction>>[];
    for (var i = 0; i < transactions.length; i += _defaultBatchSize) {
      batches.add(
        transactions.sublist(
          i,
          i + _defaultBatchSize > transactions.length
              ? transactions.length
              : i + _defaultBatchSize,
        ),
      );
    }
    final out = <String, String?>{};
    var done = 0;
    for (final batch in batches) {
      final partial = await _suggestBatch(
        batch: batch,
        allowedCategoryIds: allowed,
      );
      out.addAll(partial);
      done += batch.length;
      onBatchProgress?.call(done, transactions.length);
    }
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

    final body = jsonEncode({
      'model': openAiModel,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    });

    final res = await _client.post(
      Uri.parse(_openAiChatCompletionsUrl),
      headers: {
        'Authorization': 'Bearer ${Constants.openAIKey}',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FormatException(
        'OpenAI request failed (${res.statusCode}): ${res.body}',
      );
    }

    final outer = jsonDecode(res.body);
    if (outer is! Map<String, dynamic>) {
      throw const FormatException('OpenAI envelope is not a JSON object.');
    }
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
    final content = msg['content'];
    if (content is! String || content.isEmpty) {
      throw const FormatException('OpenAI message content is empty.');
    }

    final parsed = parseSuggestionsFromResponseContent(
      content,
      allowedCategoryIds,
      expectedKeys,
    );
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
