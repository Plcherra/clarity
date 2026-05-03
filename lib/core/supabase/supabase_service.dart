import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfigException implements Exception {
  const SupabaseConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class SupabaseService {
  const SupabaseService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static String get url => dotenv.env['SUPABASE_URL']?.trim() ?? '';
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

  static bool get hasEnvConfig => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> initializeFromEnv() async {
    if (!hasEnvConfig) {
      throw const SupabaseConfigException(
        'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to .env.',
      );
    }

    await Supabase.initialize(url: url, anonKey: anonKey, debug: kDebugMode);
  }

  SupabaseClient get client {
    final injected = _client;
    if (injected != null) return injected;
    try {
      return Supabase.instance.client;
    } on Object {
      throw const SupabaseConfigException(
        'Supabase has not been initialized. Call SupabaseService.initializeFromEnv() before using Supabase.',
      );
    }
  }

  bool get isConfigured {
    try {
      client;
      return true;
    } on Object {
      return false;
    }
  }

  GoTrueClient get auth => client.auth;
  FunctionsClient get functions => client.functions;
}
