/// Root widget and theming of the Quizmo prototype.
library;

import 'package:flutter/material.dart';

import 'common/role_selection_page.dart';
import 'spectator/tv_page.dart';
import 'player/player_page.dart';
import 'player/player_session_store.dart';

/// The application shell.
class QuizmoApp extends StatelessWidget {
  /// Creates the app.
  ///
  /// With [startAsTv] the app skips the role selection and opens the
  /// spectator (TV) screen right away. `main` derives it from the launch URL
  /// (`/tv`), see `isTvLaunchUri`.
  const QuizmoApp({this.startAsTv = false, super.key});

  /// Whether the spectator screen replaces the role selection as home page.
  final bool startAsTv;

  /// Seed colour of the generated Material 3 scheme.
  static const Color seedColor = Color(0xFF5E6AD2);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quizmo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: startAsTv ? const TvPage() : const _SessionHome(),
    );
  }

  /// Builds the Material 3 theme for [brightness].
  static ThemeData buildTheme(Brightness brightness) {
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
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      ),
    );
  }
}

class _SessionHome extends StatefulWidget {
  const _SessionHome();
  @override
  State<_SessionHome> createState() => _SessionHomeState();
}

class _SessionHomeState extends State<_SessionHome> {
  late final Future<SavedPlayerSession?> _saved = _load();
  Future<SavedPlayerSession?> _load() async {
    try {
      return await PlayerSessionStore().read();
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SavedPlayerSession?>(
    future: _saved,
    builder: (context, snapshot) => snapshot.data != null
        ? PlayerPage(initialHostUri: snapshot.data!.host)
        : const RoleSelectionPage(),
  );
}
