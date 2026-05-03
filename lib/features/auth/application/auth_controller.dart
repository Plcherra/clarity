import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthService authService,
    bool initialAuthenticated = false,
  }) : _authService = authService,
       _authenticatedOverride = initialAuthenticated {
    _session = _authService.currentSession;
    _subscription = _authService.authStateChanges.listen((state) {
      _session = state.session;
      _authenticatedOverride = false;
      notifyListeners();
    });
  }

  final AuthService _authService;
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  bool _authenticatedOverride;

  bool isLoading = false;
  String? errorMessage;
  String? infoMessage;

  Session? get currentSession => _session;
  User? get currentUser => _session?.user ?? _authService.currentUser;
  bool get isAuthenticated => _authenticatedOverride || currentSession != null;

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    await _runAuthAction(() async {
      final response = await _authService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
      );
      _session = response.session;
      if (_session == null) {
        infoMessage = 'Check your email to confirm your account.';
      }
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _runAuthAction(() async {
      final response = await _authService.signInWithEmail(
        email: email,
        password: password,
      );
      _session = response.session;
    });
  }

  Future<void> signOut() async {
    await _runAuthAction(() async {
      await _authService.signOut();
      _session = null;
      _authenticatedOverride = false;
    });
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
