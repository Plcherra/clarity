import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

const Duration openAiProxyRequestTimeout = Duration(seconds: 120);
const Duration categorizeTransactionsRequestTimeout = Duration(minutes: 5);

abstract interface class OpenAiProxyClient {
  bool get isConfigured;

  Future<Map<String, dynamic>> createChatCompletion(Map<String, dynamic> body);

  Future<Map<String, dynamic>> categorizeTransactions(
    Map<String, dynamic> body,
  );

  void close();
}

class OpenAiProxyUnavailableException implements Exception {
  const OpenAiProxyUnavailableException();

  @override
  String toString() =>
      'AI categorization is not configured. Sign in and configure the Supabase call-openai Edge Function secret.';
}

final class SupabaseOpenAiProxyClient implements OpenAiProxyClient {
  SupabaseOpenAiProxyClient({
    SupabaseService supabaseService = const SupabaseService(),
  }) : _supabaseService = supabaseService;

  final SupabaseService _supabaseService;

  @override
  bool get isConfigured {
    if (!_supabaseService.isConfigured) return false;
    return _supabaseService.auth.currentSession != null;
  }

  @override
  Future<Map<String, dynamic>> createChatCompletion(
    Map<String, dynamic> body,
  ) async {
    if (!isConfigured) {
      throw const OpenAiProxyUnavailableException();
    }

    FunctionResponse response;
    try {
      response = await _supabaseService.functions
          .invoke('call-openai', body: body)
          .timeout(openAiProxyRequestTimeout);
    } on TimeoutException {
      throw const FormatException(
        'AI request timed out. Try again with fewer transactions or check your connection.',
      );
    } on FunctionException catch (e) {
      throw FormatException(_friendlyFunctionError(e.status, e.details));
    } on Object catch (e) {
      throw FormatException('AI request failed: $e');
    }

    if (response.status < 200 || response.status >= 300) {
      throw FormatException(
        _friendlyFunctionError(response.status, response.data),
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('AI response envelope is not a JSON object.');
  }

  @override
  Future<Map<String, dynamic>> categorizeTransactions(
    Map<String, dynamic> body,
  ) async {
    if (!isConfigured) {
      throw const OpenAiProxyUnavailableException();
    }

    FunctionResponse response;
    try {
      response = await _supabaseService.functions
          .invoke('categorize-transactions', body: body)
          .timeout(categorizeTransactionsRequestTimeout);
    } on TimeoutException {
      throw const FormatException(
        'AI categorization timed out. Transactions were imported and marked Unknown.',
      );
    } on FunctionException catch (e) {
      throw FormatException(_friendlyFunctionError(e.status, e.details));
    } on Object catch (e) {
      throw FormatException('AI categorization failed: $e');
    }

    if (response.status < 200 || response.status >= 300) {
      throw FormatException(
        _friendlyFunctionError(response.status, response.data),
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException(
      'AI categorization response is not a JSON object.',
    );
  }

  @override
  void close() {}
}

String _friendlyFunctionError(int statusCode, Object? details) {
  final message = _extractErrorMessage(details);
  if (statusCode == 401) {
    return 'Sign in again to use AI categorization.';
  }
  if (statusCode == 500 && message.toLowerCase().contains('secret')) {
    return 'AI categorization is not configured. Set the Edge Function secret and try again.';
  }
  if (message.trim().isNotEmpty) {
    return 'AI request failed ($statusCode): ${message.trim()}';
  }
  return 'AI request failed ($statusCode).';
}

String _extractErrorMessage(Object? details) {
  if (details == null) return '';
  if (details is String) return details;
  if (details is Map) {
    final error = details['error'];
    if (error is String) return error;
    final message = details['message'];
    if (message is String) return message;
  }
  return details.toString();
}
