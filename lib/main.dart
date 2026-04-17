import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/upload_screen.dart';

void main() {
  runApp(ClarityApp(appState: AppState()));
}

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
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      textTheme: const TextTheme().apply(
        bodyColor: const Color(0xFF1C1B19),
        displayColor: const Color(0xFF1C1B19),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: const Color(0xFFF7F5F2),
          backgroundColor: const Color(0xFF1C1B19),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
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
          home: UploadScreen(appState: appState),
        );
      },
    );
  }
}
