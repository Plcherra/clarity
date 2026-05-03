import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

class AuthService {
  AuthService({required SupabaseService supabaseService})
    : _supabaseService = supabaseService;

  final SupabaseService _supabaseService;

  Session? get currentSession {
    if (!_supabaseService.isConfigured) return null;
    return _supabaseService.auth.currentSession;
  }

  User? get currentUser {
    if (!_supabaseService.isConfigured) return null;
    return _supabaseService.auth.currentUser;
  }

  Stream<AuthState> get authStateChanges {
    if (!_supabaseService.isConfigured) return const Stream.empty();
    return _supabaseService.auth.onAuthStateChange;
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) {
    return _supabaseService.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _supabaseService.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() {
    return _supabaseService.auth.signOut();
  }
}
