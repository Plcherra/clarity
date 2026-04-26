import 'package:flutter/material.dart';

import '../app_state.dart';
import '../features/shell/presentation/home_shell.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';

final class ClarityApp extends StatelessWidget {
  const ClarityApp({super.key, required this.appState});

  final AppState appState;

  static ThemeData _buildTheme() {
    const seed = Color(0xFF1C1B19);
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFFAFAF8),
    );
    const onPaper = Color(0xFFF7F5F2);
    final outlineSoft = base.outline.withValues(alpha: 0.35);

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      textTheme: const TextTheme().apply(
        bodyColor: const Color(0xFF1C1B19),
        displayColor: const Color(0xFF1C1B19),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: base.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: base.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: onPaper,
          backgroundColor: const Color(0xFF1C1B19),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1C1B19),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
            fontSize: 15,
          ),
          side: BorderSide(color: outlineSoft),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF1C1B19).withValues(alpha: 0.75),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outlineSoft,
        space: 1,
        thickness: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'Clarity',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(),
          home: appState.localProfile == null
              ? OnboardingScreen(appState: appState)
              : HomeShell(appState: appState),
        );
      },
    );
  }
}

