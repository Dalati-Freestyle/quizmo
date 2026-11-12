/// Root widget and theming of the Quizmo prototype.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';

import '../core/net/session_uri.dart';
import '../core/data/session_recovery.dart';

import 'common/role_selection_page.dart';
import 'l10n/app_localizations.dart';
import 'settings/locale_cubit.dart';
import 'spectator/tv_page.dart';
import 'player/player_page.dart';
import 'player/player_session_store.dart';
import 'quizmaster/recovery/recovery_gate.dart';

/// The application shell.
class QuizmoApp extends StatefulWidget {
  /// Creates the app.
  ///
  /// With [startAsTv] the app skips the role selection and opens the
  /// spectator (TV) screen right away. `main` derives it from the launch URL
  /// (`/tv`), see `isTvLaunchUri`.
  const QuizmoApp({
    this.startAsTv = false,
    this.launchUri,
    this.localeCubit,
    this.recoveryStore,
    super.key,
  });

  final LocaleCubit? localeCubit;
  final SessionRecoveryStore? recoveryStore;

  @override
  State<QuizmoApp> createState() => _QuizmoAppState();

  final Uri? launchUri;

  /// Whether the spectator screen replaces the role selection as home page.
  final bool startAsTv;

  /// Seed colour of the generated Material 3 scheme.
  static const Color seedColor = Color(0xFF5E6AD2);

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

class _QuizmoAppState extends State<QuizmoApp> {
  late final LocaleCubit _localeCubit = widget.localeCubit ?? LocaleCubit();

  @override
  void initState() {
    super.initState();
    unawaited(_localeCubit.load());
  }

  @override
  void dispose() {
    if (widget.localeCubit == null) unawaited(_localeCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _localeCubit,
    child: BlocBuilder<LocaleCubit, LocaleSettingsState>(
      builder: (context, state) => MaterialApp(
        title: 'Quizmo',
        debugShowCheckedModeBanner: false,
        locale: state.preference.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: AppLocalizations.resolveLocale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: ThemeMode.dark,
        theme: QuizmoApp.buildTheme(Brightness.light),
        darkTheme: QuizmoApp.buildTheme(Brightness.dark),
        home: widget.startAsTv
            ? TvPage(launchUri: widget.launchUri)
            : _SessionHome(
                launchUri: widget.launchUri,
                recoveryStore: widget.recoveryStore,
              ),
      ),
    ),
  );
}

class _SessionHome extends StatefulWidget {
  const _SessionHome({this.launchUri, this.recoveryStore});
  final Uri? launchUri;
  final SessionRecoveryStore? recoveryStore;
  @override
  State<_SessionHome> createState() => _SessionHomeState();
}

class _SessionHomeState extends State<_SessionHome> {
  late final Uri? _invitedRoom =
      kIsWeb &&
          (isInternetSession(widget.launchUri ?? Uri.base) ||
              (widget.launchUri ?? Uri.base).queryParameters.containsKey(
                'session',
              ))
      ? sessionUri(widget.launchUri ?? Uri.base)
      : null;
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
    builder: (context, snapshot) => _invitedRoom != null
        ? PlayerPage(initialHostUri: _invitedRoom)
        : RecoveryGate(
            store: widget.recoveryStore,
            child: snapshot.data != null
                ? PlayerPage(initialHostUri: snapshot.data!.host)
                : const RoleSelectionPage(),
          ),
  );
}
