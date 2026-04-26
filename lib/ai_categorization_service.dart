import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'core/constants/constants.dart';
import 'core/models/models.dart';
import 'spend_categories.dart';

const String _openAiChatCompletionsUrl =
    'https://api.openai.com/v1/chat/completions';

const String openAiModel = 'gpt-4o-mini';

const int _defaultBatchSize = 32;

/// Wall-clock limit per OpenAI HTTP request (large batches can be slow).
const Duration _openAiRequestTimeout = Duration(seconds: 120);

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

Map<String, AiCategorySuggestion> parseSuggestionsWithConfidenceFromResponseContent(
  String messageContent,
  List<String> allowedCanonicals,
  Set<String> expectedKeys,
  int promptVersion,
) {
  final decoded = jsonDecode(messageContent);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('OpenAI response JSON is not an object.');
  }
  final rawList = decoded['suggestions'];
  if (rawList is! List) {
    throw const FormatException('OpenAI response missing suggestions array.');
  }

  final out = <String, AiCategorySuggestion>{};
  final nowIso = DateTime.now().toUtc().toIso8601String();
  for (final e in rawList) {
    if (e is! Map) continue;
    final key = e['key'];
    if (key is! String || key.isEmpty) continue;
    if (!expectedKeys.contains(key)) continue;

    final cat = e['categoryId'];
    final confidence = e['confidence'];
    final rationale = e['rationale'];

    final normalized = cat is String
        ? normalizeSuggestionToAllowed(cat, allowedCanonicals)
        : null;
    final conf = confidence is num ? confidence.toDouble() : 0.0;

    out[key] = AiCategorySuggestion(
      transactionKey: key,
      suggestedCanonical: normalized,
      confidence: conf.clamp(0.0, 1.0),
      rationale: rationale is String ? rationale : null,
      createdAtIso: nowIso,
      model: openAiModel,
      promptVersion: promptVersion,
    );
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
    if (allowedCategoryIds.isEmpty) {
      throw const FormatException(
        'No categories are available to assign. Check category settings in the app.',
      );
    }
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

  Future<Map<String, AiCategorySuggestion>> suggestCategoriesWithConfidence({
    required List<Transaction> transactions,
    required List<String> allowedCategoryIds,
    required int promptVersion,
    void Function(int completed, int total)? onBatchProgress,
  }) async {
    if (Constants.openAIKey.isEmpty) {
      throw MissingOpenAiApiKeyException();
    }
    if (transactions.isEmpty) return {};
    if (allowedCategoryIds.isEmpty) {
      throw const FormatException(
        'No categories are available to assign. Check category settings in the app.',
      );
    }

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

    final out = <String, AiCategorySuggestion>{};
    var done = 0;
    for (final batch in batches) {
      final partial = await _suggestBatchWithConfidence(
        batch: batch,
        allowedCategoryIds: allowed,
        promptVersion: promptVersion,
      );
      out.addAll(partial);
      done += batch.length;
      onBatchProgress?.call(done, transactions.length);
    }
    for (final t in transactions) {
      final k = transactionCategoryKey(t);
      out.putIfAbsent(
        k,
        () => AiCategorySuggestion(
          transactionKey: k,
          suggestedCanonical: null,
          confidence: 0.0,
          rationale: null,
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          model: openAiModel,
          promptVersion: promptVersion,
        ),
      );
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

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_openAiChatCompletionsUrl),
            headers: {
              'Authorization': 'Bearer ${Constants.openAIKey}',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(_openAiRequestTimeout);
    } on TimeoutException {
      throw const FormatException(
        'OpenAI request timed out. Try again with fewer transactions or check your connection.',
      );
    } on SocketException catch (e) {
      throw FormatException('Network error: ${e.message}');
    } on http.ClientException catch (e) {
      throw FormatException('Network error: ${e.message}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FormatException(
        'OpenAI request failed (${res.statusCode}): ${res.body}',
      );
    }

    dynamic outer;
    try {
      outer = jsonDecode(res.body);
    } on FormatException catch (e) {
      throw FormatException('OpenAI response was not valid JSON: ${e.message}');
    }
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

  Future<Map<String, AiCategorySuggestion>> _suggestBatchWithConfidence({
    required List<Transaction> batch,
    required List<String> allowedCategoryIds,
    required int promptVersion,
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
        'exact shape: {"suggestions":[{"key":"<copied from input>","categoryId":"<allowed>","confidence":0.0,"rationale":"..."}]} '
        'Each categoryId MUST be exactly one string from the allowed list (character-for-character match). '
        'confidence MUST be a number from 0.0 to 1.0. '
        'Return exactly one suggestion object per input line (same key). '
        'If uncertain, pick the closest allowed category but use a low confidence.';
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

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_openAiChatCompletionsUrl),
            headers: {
              'Authorization': 'Bearer ${Constants.openAIKey}',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(_openAiRequestTimeout);
    } on TimeoutException {
      throw const FormatException(
        'OpenAI request timed out. Try again with fewer transactions or check your connection.',
      );
    } on SocketException catch (e) {
      throw FormatException('Network error: ${e.message}');
    } on http.ClientException catch (e) {
      throw FormatException('Network error: ${e.message}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FormatException(
        'OpenAI request failed (${res.statusCode}): ${res.body}',
      );
    }

    dynamic outer;
    try {
      outer = jsonDecode(res.body);
    } on FormatException catch (e) {
      throw FormatException('OpenAI response was not valid JSON: ${e.message}');
    }
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
    final contentRaw = msg['content'];
    if (contentRaw is! String || contentRaw.isEmpty) {
      throw const FormatException('OpenAI message content is empty.');
    }
    final content = unwrapOpenAiMessageContent(contentRaw);

    Map<String, AiCategorySuggestion> parsed;
    try {
      parsed = parseSuggestionsWithConfidenceFromResponseContent(
        content,
        allowedCategoryIds,
        expectedKeys,
        promptVersion,
      );
    } on FormatException catch (e) {
      throw FormatException('Could not parse AI category JSON: ${e.message}');
    }
    final out = <String, AiCategorySuggestion>{};
    for (final t in batch) {
      final k = transactionCategoryKey(t);
      if (parsed.containsKey(k)) {
        out[k] = parsed[k]!;
      }
    }
    return out;
  }

  void close() {
    _client.close();
  }
}
