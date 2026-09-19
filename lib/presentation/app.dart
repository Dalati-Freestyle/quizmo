/// Root widget and theming of the Quizmo prototype.
library;

import 'package:flutter/material.dart';

import 'common/role_selection_page.dart';

/// The application shell.
class QuizmoApp extends StatelessWidget {
  /// Creates the app.
  const QuizmoApp({super.key});

  /// Seed colour of the generated Material 3 scheme.
  static const Color seedColor = Color(0xFF5E6AD2);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quizmo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const RoleSelectionPage(),
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    );
  }
}

