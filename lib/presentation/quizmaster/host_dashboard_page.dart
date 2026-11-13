/// The quizmaster dashboard.
///
/// Owns the [QuizEngineBloc] — the single source of truth of a session — and
/// the [HostServerCubit] that publishes it over the network.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/settings_page.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/guest_wifi_cubit.dart';
import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/data/session_checkpoint.dart';
import '../../core/data/session_recovery.dart';
import '../../core/models/models.dart';
import '../common/adaptive_layout.dart';
import '../common/bundled_web_client.dart';
import '../common/session_notifications.dart';
import '../player/player_page.dart';
import '../spectator/tv_page.dart';
import 'dashboard_panels.dart';
import 'game_sections.dart';
import 'host_server_cubit.dart';
import 'recovery/recovery_store.dart';
import 'recovery/rebind_recovery_panel.dart';
import '../../core/engine/session_access.dart';
import 'session_access_panel.dart';
import 'tech_check_page.dart' deferred as tech_check;
import 'layout/dashboard_layout.dart';
import 'layout/dashboard_section_view.dart';
import 'wifi/guest_wifi_toggle.dart';

/// Host facing screen: run the server, drive rounds, judge answers.
class HostDashboardPage extends StatelessWidget {
  /// Creates the dashboard for [quiz].
  const HostDashboardPage({
    required this.quiz,
    this.checkpoint,
    this.recoveryStore,
    super.key,
  });

  /// Quiz definition fixed for this hosted session.
  final Quiz quiz;
  final SessionCheckpoint? checkpoint;
  final SessionRecoveryStore? recoveryStore;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<QuizEngineBloc>(
          create: (_) => QuizEngineBloc(
            restoredGame: checkpoint?.pausedGame(),
            recoverySessionId: checkpoint?.sessionId ?? newRecoveryId(),
            resumeTokenHashes: checkpoint?.resumeTokenHashes ?? const {},
            accessState: checkpoint?.accessState ?? const SessionAccessState(),
            questionBank: quiz.questions,
            autoContinueBuzzer: false,
            teams: quiz.teamsById,
            mode: quiz.teams.isEmpty ? const SoloMode() : const TeamMode(),
            revealMode: switch (quiz.format) {
              StandardFormat(:final revealMode) => revealMode,
              JeopardyFormat() ||
              PokerFormat() => SolutionRevealMode.afterEachQuestion,
            },
            pokerStartingChips: switch (quiz.format) {
              PokerFormat(:final startingChips) => startingChips,
              StandardFormat() || JeopardyFormat() => null,
            },
            jeopardyBoard: switch (quiz.format) {
              JeopardyFormat(:final board) => board,
              StandardFormat() || PokerFormat() => null,
            },
          ),
        ),
        BlocProvider<GuestWifiCubit>(create: (_) => GuestWifiCubit()),
        BlocProvider<HostServerCubit>(
          create: (context) => HostServerCubit(
            engine: context.read<QuizEngineBloc>(),
            guestWifi: context.read<GuestWifiCubit>(),
            serverName: quiz.name,
            // Lets guests load the player client straight from this device, so
            // the LAN address is all they need.
            webClient: bundledWebClient(),
            // Flags a stale packed player, which TV screens would load.
            appVersion: hostAppVersion,
          ),
        ),
      ],
      child: _RecoveryOwner(
        quiz: quiz,
        checkpoint: checkpoint,
        store: recoveryStore,
      ),
    );
  }
}

class _RecoveryOwner extends StatefulWidget {
  const _RecoveryOwner({required this.quiz, this.checkpoint, this.store});
  final Quiz quiz;
  final SessionCheckpoint? checkpoint;
  final SessionRecoveryStore? store;
  @override
  State<_RecoveryOwner> createState() => _RecoveryOwnerState();
}

class _RecoveryOwnerState extends State<_RecoveryOwner>
    with WidgetsBindingObserver {
  SessionRecovery? _recovery;
  StreamSubscription<RecoveryException>? _errors;
  Timer? _ticker;
  String? _startupError;
  bool _ready = false;
  bool _leaving = false;
  bool _canLeave = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final store = widget.store ?? await createRecoveryStore();
      if (!mounted) return;
      final recovery = SessionRecovery(
        engine: context.read<QuizEngineBloc>(),
        quiz: widget.quiz,
        store: store,
        restored: widget.checkpoint,
        previousJoinUri: widget.checkpoint?.previousJoinUri,
      );
      _recovery = recovery;
      _errors = recovery.errors.listen((_) {
        if (mounted) setState(() {});
      });
      await recovery.start();
      if (!mounted) {
        await recovery.close();
        return;
      }
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _ready = true;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _startupError = '$error';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        context.read<HostServerCubit>().setDiscoverySuspended(
          state != AppLifecycleState.resumed,
        ),
      );
    }
    if (_ready && state != AppLifecycleState.resumed) {
      unawaited(_checkpoint());
    }
  }

  Future<void> _checkpoint() async {
    try {
      await _recovery?.checkpoint();
    } on RecoveryException {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_errors?.cancel());
    unawaited(_recovery?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Saved game recovery'))),
        body: Center(
          child: _startupError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.tr(_startupError!)),
                      OutlinedButton(
                        onPressed: () async {
                          await _errors?.cancel();
                          await _recovery?.close();
                          if (!mounted) return;
                          setState(() {
                            _startupError = null;
                          });
                          await _start();
                        },
                        child: Text(context.tr('Retry')),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _leaving) return;
        _leaving = true;
        try {
          await context.read<HostServerCubit>().stop();
          await _recovery!.checkpoint();
          await _recovery!.close();
          if (!mounted) return;
          setState(() {
            _canLeave = true;
          });
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted) Navigator.of(context).pop();
        } on RecoveryException {
          _leaving = false;
          if (mounted) setState(() {});
        }
      },
      child: BlocListener<HostServerCubit, HostServerState>(
        listenWhen: (previous, current) =>
            current.endpoint != null && previous.endpoint != current.endpoint,
        listener: (context, state) {
          _recovery!.previousJoinUri = state.endpoint!.lanUri;
          unawaited(_checkpoint());
        },
        child: _HostDashboardView(
          quizName: widget.quiz.name,
          recovery: _recovery!,
          previousJoinUri: widget.checkpoint?.previousJoinUri,
        ),
      ),
    );
  }
}

class _HostDashboardView extends StatelessWidget {
  const _HostDashboardView({
    required this.quizName,
    required this.recovery,
    this.previousJoinUri,
  });

  final String quizName;
  final SessionRecovery recovery;
  final Uri? previousJoinUri;

  @override
  Widget build(BuildContext context) {
    final engine = context.read<QuizEngineBloc>();

    return JeopardyPickConfirmation(
      engine: engine,
      child: BlocBuilder<QuizEngineBloc, QuizEngineState>(
        builder: (context, engineState) {
          return BlocBuilder<HostServerCubit, HostServerState>(
            builder: (context, serverState) {
              final game = engineState.game;
              final savedRemainingMicros =
                  (game.round.question?.timeLimit.inMicroseconds ?? 0) -
                  game.round.timerElapsedAt(game.hostTimeMicros).inMicroseconds;

              // The preview connects through loopback (always reachable on
              // this device) but tells players the LAN address they can use.
              VoidCallback? openTvPreview;
              if (serverState.endpoint case final endpoint?) {
                openTvPreview = () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => TvPage(
                      hostUri: endpoint.loopbackUri,
                      joinUri: endpoint.lanUri,
                    ),
                  ),
                );
              }

              return Scaffold(
                appBar: AppBar(
                  title: Text(context.tr("Quizmaster · {0}", [quizName])),
                  actions: [
                    IconButton(
                      tooltip: context.tr("Technikcheck"),
                      icon: const Icon(Icons.fact_check_outlined),
                      onPressed: () => openTechCheck(context, game),
                    ),
                    const SettingsButton(),
                    IconButton(
                      tooltip: context.tr("Preview the TV screen"),
                      onPressed: openTvPreview,
                      icon: const Icon(Icons.tv),
                    ),
                    IconButton(
                      tooltip: context.tr(
                        "Join this session as a local player",
                      ),
                      onPressed: serverState.endpoint == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PlayerPage(
                                  initialHostUri:
                                      serverState.endpoint!.loopbackUri,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.person_add_alt),
                    ),
                    IconButton(
                      tooltip: context.tr("Reset scores"),
                      onPressed: () => engine.add(const ResetGameEvent()),
                      icon: const Icon(Icons.restart_alt),
                    ),
                    GameModeMenu(engine: engine),
                  ],
                ),
                body: SessionNotifications(
                  game: game,
                  child: DashboardSectionGrid(
                    leading: [
                      if (serverState.outdatedWebClientVersion
                          case final version?)
                        OutdatedWebClientBanner(webClientVersion: version),
                    ],
                    sections: {
                      DashboardSection.sessionAccess: SessionAccessPanel(
                        access: engine.access,
                      ),
                      // Guest Wi-Fi only exists for the embedded LAN host;
                      // the browser host plays through the internet relay.
                      if (!kIsWeb)
                        DashboardSection.guestWifi: GuestWifiToggle(
                          guestWifi: context.read<GuestWifiCubit>(),
                        ),
                      DashboardSection.recovery: _RecoveryPanel(
                        recovery: recovery,
                        engine: engine,
                        game: game,
                        previousJoinUri: previousJoinUri,
                        savedRemainingMicros: savedRemainingMicros,
                      ),
                      ...buildGameSections(
                        context,
                        engine: engine,
                        engineState: engineState,
                        quizName: quizName,
                        connectionsAvailable:
                            serverState.status == HostServerStatus.running,
                        startExtras: [
                          OutlinedButton.icon(
                            key: const ValueKey("open-tech-check"),
                            onPressed: () => openTechCheck(context, game),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: Text(context.tr("Technikcheck")),
                          ),
                        ],
                      ),
                      DashboardSection.server: ServerControlPanel(
                        state: serverState,
                        connectedPlayers:
                            serverState.status == HostServerStatus.running
                            ? game.connectedPlayers.length
                            : 0,
                        onOpenTvPreview: openTvPreview,
                        onStart: () => context.read<HostServerCubit>().start(),
                        onStop: () => context.read<HostServerCubit>().stop(),
                      ),
                      DashboardSection.serverLog: ServerLogPanel(
                        logs: serverState.logs,
                      ),
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RecoveryPanel extends StatelessWidget {
  const _RecoveryPanel({
    required this.recovery,
    required this.engine,
    required this.game,
    required this.previousJoinUri,
    required this.savedRemainingMicros,
  });

  final SessionRecovery recovery;
  final QuizEngineBloc engine;
  final GameState game;
  final Uri? previousJoinUri;
  final int savedRemainingMicros;

  @override
  Widget build(BuildContext context) => PanelCard(
    title: context.tr('Saved game recovery'),
    icon: Icons.save_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          recovery.lastError == null
              ? context.tr('Automatic recovery save: {0}', [
                  recovery.lastSavedAtMicros == null
                      ? '-'
                      : DateTime.fromMicrosecondsSinceEpoch(
                          recovery.lastSavedAtMicros!,
                        ).toLocal().toString(),
                ])
              : context.tr(recovery.lastError!.message),
        ),
        if (recovery.lastError != null)
          OutlinedButton(
            onPressed: () async {
              try {
                await recovery.checkpoint();
              } on RecoveryException {
                // The persistent status above shows this failure.
              }
            },
            child: Text(context.tr('Retry')),
          ),
        if (previousJoinUri != null)
          Text(
            context.tr('Previous invitation (may be invalid): {0}', [
              previousJoinUri,
            ]),
          ),
        if (game.recoveryPaused) ...[
          if ((game.round.question?.hasTimeLimit ?? false) &&
              game.round.status.acceptsInput &&
              !(game.poker?.betting ?? false))
            Text(
              context.tr('Saved timer: {0} s remaining', [
                savedRemainingMicros <= 0
                    ? 0
                    : (savedRemainingMicros / 1000000).ceil(),
              ]),
            ),
          Text(
            context.tr(
              'Timer choices affect the current round only. Closed rounds stay closed.',
            ),
          ),
          Text(
            context.tr(
              'Game paused for recovery. Reconnect participants before continuing. Media stays paused.',
            ),
          ),
          Text(
            context.tr(
              'Internet recovery creates a new room. Old internet links are invalid; share the new invitation and TV links. LAN addresses may also change.',
            ),
          ),
          RebindRecoveryPanel(engine: engine, game: game),
          for (final policy in RecoveryTimerPolicy.values)
            OutlinedButton(
              onPressed: recovery.lastError != null
                  ? null
                  : () => engine.add(ResumeRecoveredGameEvent(policy)),
              child: Text(
                context.tr(switch (policy) {
                  RecoveryTimerPolicy.savedTime => 'Continue with saved time',
                  RecoveryTimerPolicy.restart => 'Restart the full timer',
                  RecoveryTimerPolicy.soft => 'Continue with a soft timer',
                }),
              ),
            ),
        ],
      ],
    ),
  );
}

/// Unmissable warning that guests and TVs get an outdated web player.
///
/// A host started with `flutter run` (or built without re-running
/// `tool/bundle_web_client.dart`) embeds whatever `bundle.zip` is on disk, so
/// browsers then miss every newer feature although the host and its preview
/// already have it.
class OutdatedWebClientBanner extends StatelessWidget {
  /// Creates the banner.
  const OutdatedWebClientBanner({required this.webClientVersion, super.key});

  /// Version of the packed web player.
  final String webClientVersion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('outdated-web-client'),
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr(
                  'Veralteter Web-Player ({0}): Spieler- und TV-Browser bekommen eine alte Version und sehen neue Funktionen nicht (z. B. Abschlussseite, Timer). Vor dem Start des Hosts „dart run tool/bundle_web_client.dart“ ausführen.',
                  [webClientVersion],
                ),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the optional technical check (loaded on demand).
Future<void> openTechCheck(BuildContext context, GameState game) async {
  final engine = context.read<QuizEngineBloc>();
  final server = context.read<HostServerCubit>();
  final navigator = Navigator.of(context);
  await tech_check.loadLibrary();
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => tech_check.TechCheckPage(
        engine: engine,
        server: server,
        questions: game.questionBank,
      ),
    ),
  );
}
