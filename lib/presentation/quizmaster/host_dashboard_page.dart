/// The quizmaster dashboard.
///
/// Owns the [QuizEngineBloc] — the single source of truth of a session — and
/// the [HostServerCubit] that publishes it over the network.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/settings_page.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/data/session_checkpoint.dart';
import '../../core/data/session_recovery.dart';
import '../../core/models/models.dart';
import '../common/adaptive_layout.dart';
import '../common/bundled_web_client.dart';
import '../common/scoreboard_view.dart';
import '../common/session_notifications.dart';
import '../player/player_page.dart';
import '../spectator/tv_page.dart';
import 'dashboard_panels.dart';
import 'correction_history_panel.dart';
import 'host_server_cubit.dart';
import 'recovery/recovery_store.dart';
import 'recovery/rebind_recovery_panel.dart';
import '../../core/engine/session_access.dart';
import 'session_access_panel.dart';

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
        BlocProvider<HostServerCubit>(
          create: (context) => HostServerCubit(
            engine: context.read<QuizEngineBloc>(),
            serverName: quiz.name,
            // Lets guests load the player client straight from this device, so
            // the LAN address is all they need.
            webClient: bundledWebClient(),
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

    return BlocConsumer<QuizEngineBloc, QuizEngineState>(
      listenWhen: (previous, current) =>
          current.game.jeopardy?.pendingPickQuestionId != null &&
          (previous.game.jeopardy?.pendingPickQuestionId !=
                  current.game.jeopardy?.pendingPickQuestionId ||
              (previous.game.recoveryPaused && !current.game.recoveryPaused) ||
              previous.game.jeopardy?.pendingPickPlayerId !=
                  current.game.jeopardy?.pendingPickPlayerId),
      listener: (context, state) async {
        final pick = state.game.jeopardy!;
        final id = pick.pendingPickQuestionId!;
        final playerId = pick.pendingPickPlayerId!;
        final question = state.game.questionById(id);
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.tr("Fragenauswahl bestätigen")),
            content: Text(
              context.tr(
                "{0} hat {1} für {2} Punkte gewählt.\n\n{3}\n\nBitte bestätige die Auswahl, um die Frage zu öffnen.",
                [
                  state.game.players[playerId]?.name ?? "Spieler",
                  pick.board.categoryNameOf(id),
                  pick.board.pointsFor(id),
                  question?.prompt ?? "",
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.tr("Ablehnen")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.tr("Bestätigen")),
              ),
            ],
          ),
        );
        if (!engine.isClosed) {
          engine.add(
            ConfirmQuestionPickEvent(
              questionId: id,
              playerId: playerId,
              accepted: accepted == true,
            ),
          );
        }
      },
      builder: (context, engineState) {
        return BlocBuilder<HostServerCubit, HostServerState>(
          builder: (context, serverState) {
            final game = engineState.game;
            final savedRemainingMicros =
                (game.round.question?.timeLimit.inMicroseconds ?? 0) -
                game.round.timerElapsedAt(game.hostTimeMicros).inMicroseconds;

            // The preview connects through loopback (always reachable on this
            // device) but tells players the LAN address they can really use.
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
                  const SettingsButton(),
                  IconButton(
                    tooltip: context.tr("Preview the TV screen"),
                    onPressed: openTvPreview,
                    icon: const Icon(Icons.tv),
                  ),
                  IconButton(
                    tooltip: context.tr("Join this session as a local player"),
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
                  PopupMenuButton<GameMode>(
                    tooltip: context.tr("Game mode"),
                    icon: const Icon(Icons.tune),
                    onSelected: (mode) => engine.add(ChangeGameModeEvent(mode)),
                    itemBuilder: (_) => [
                      PopupMenuItem<GameMode>(
                        value: SoloMode(),
                        child: Text(context.tr("Solo scoring")),
                      ),
                      PopupMenuItem<GameMode>(
                        value: TeamMode(),
                        child: Text(context.tr("Team scoring (shared buzzer)")),
                      ),
                      PopupMenuItem<GameMode>(
                        value: TeamMode(sharedBuzzer: false),
                        child: Text(
                          context.tr("Team scoring (individual buzzers)"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              body: SessionNotifications(
                game: game,
                child: AdaptivePanelGrid(
                  panels: [
                    SessionAccessPanel(access: engine.access),
                    PanelCard(
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
                              context.tr(
                                'Previous invitation (may be invalid): {0}',
                                [previousJoinUri],
                              ),
                            ),
                          if (game.recoveryPaused) ...[
                            if (game.round.question != null &&
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
                                    : () => engine.add(
                                        ResumeRecoveredGameEvent(policy),
                                      ),
                                child: Text(
                                  context.tr(switch (policy) {
                                    RecoveryTimerPolicy.savedTime =>
                                      'Continue with saved time',
                                    RecoveryTimerPolicy.restart =>
                                      'Restart the full timer',
                                    RecoveryTimerPolicy.soft =>
                                      'Continue with a soft timer',
                                  }),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (!game.isStarted)
                      PanelCard(
                        title: context.tr("Quiz starten"),
                        icon: Icons.play_circle_outline,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.tr(
                                "Spieler können beitreten. Die Fragenauswahl wird erst nach dem Start freigegeben.",
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () =>
                                  engine.add(const StartGameEvent()),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(context.tr("Quiz jetzt starten")),
                            ),
                          ],
                        ),
                      ),
                    LiveRoundPanel(
                      state: engineState,
                      onJudge: (wasCorrect) => engine.add(
                        JudgeBuzzerEvent(
                          wasCorrect: wasCorrect,
                          playerId: game.round.activePlayerId,
                          questionId: game.round.question?.id,
                          startedAtHostMicros: game.round.startedAtHostMicros,
                          resolvedAttempts: game.round.resolvedAttempts,
                        ),
                      ),
                      onJudgeAnswer: engine.add,
                      onJudgeBuzzer: engine.add,
                      onReveal: () => engine.add(const RevealRoundEvent()),
                      onLock: () => engine.add(const LockBuzzerEvent()),
                      onReopenBuzzer: () =>
                          engine.add(const ReopenBuzzerEvent()),
                      onReopenBuzzerForAll: () =>
                          engine.add(const ReopenBuzzerEvent(forAll: true)),
                      onEndRound: () => engine.add(const EndRoundEvent()),
                      onNext: () {
                        if (game.isStarted) {
                          engine.add(const NextQuestionEvent());
                        }
                      },
                      onCloseRound: () => engine.add(const CloseRoundEvent()),
                    ),
                    if (game.round.question case final question?)
                      if ([
                        ...question.media,
                        if (game.round.status == RoundStatus.revealed)
                          ...question.solutionMedia,
                      ].any(
                        (m) => m is AudioAttachment || m is VideoAttachment,
                      ))
                        PanelCard(
                          title: context.tr("Medienwiedergabe"),
                          icon: Icons.live_tv,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: () => engine.add(
                                  const ControlTvMediaEvent(TvMediaAction.play),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: Text(context.tr("Abspielen")),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => engine.add(
                                  const ControlTvMediaEvent(
                                    TvMediaAction.pause,
                                  ),
                                ),
                                icon: const Icon(Icons.pause),
                                label: Text(context.tr("Pause")),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => engine.add(
                                  const ControlTvMediaEvent(
                                    TvMediaAction.restart,
                                  ),
                                ),
                                icon: const Icon(Icons.replay),
                                label: Text(context.tr("Neu starten")),
                              ),
                              Text(
                                game.tvMediaPaused
                                    ? context.tr("TV: pausiert")
                                    : context.tr("TV: Wiedergabe angefordert"),
                              ),
                            ],
                          ),
                        ),
                    if (game.poker case final poker?)
                      PanelCard(
                        title: context.tr("Pokerchips"),
                        icon: Icons.casino_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.tr("{0} Startchips pro Team · {1}", [
                                poker.startingChips,
                                poker.betting
                                    ? context.tr("Einsatzphase")
                                    : context.tr("Antwortphase"),
                              ]),
                            ),
                            for (final team in game.teams.values)
                              Text(
                                context.tr("{0}: {1} Chips · Einsatz: {2}", [
                                  team.name,
                                  poker.chips[team.id] ?? 0,
                                  poker.wagers[team.id] ?? "–",
                                ]),
                              ),
                            if (poker.betting)
                              FilledButton(
                                onPressed: () =>
                                    engine.add(const OpenPokerAnswersEvent()),
                                child: Text(
                                  context.tr(
                                    "Einsätze schließen & Antworten öffnen",
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (game.jeopardy case final jeopardy?)
                      JeopardyBoardPanel(
                        game: game,
                        jeopardy: jeopardy,
                        canPick:
                            game.isStarted &&
                            engineState.canStartRound &&
                            jeopardy.pendingPickQuestionId == null,
                        maxWager: engine.maxDailyDoubleWager(game),
                        onSelect: (questionId) =>
                            engine.add(SelectJeopardyCellEvent(questionId)),
                        onPlaceWager: (wager) =>
                            engine.add(PlaceDailyDoubleWagerEvent(wager)),
                        onSetOrder: (ids) =>
                            engine.add(SetJeopardyOrderEvent(ids)),
                        onSetTurn: (teamId) =>
                            engine.add(SetJeopardyTurnEvent(teamId)),
                      ),
                    ServerControlPanel(
                      state: serverState,
                      connectedPlayers:
                          serverState.status == HostServerStatus.running
                          ? game.connectedPlayers.length
                          : 0,
                      onOpenTvPreview: openTvPreview,
                      onStart: () => context.read<HostServerCubit>().start(),
                      onStop: () => context.read<HostServerCubit>().stop(),
                    ),
                    PanelCard(
                      title: game.poker == null
                          ? context.tr("Scoreboard · {0}", [
                              context.tr(game.mode.label),
                            ])
                          : context.tr("Pokerchips · Teams"),
                      icon: Icons.leaderboard_outlined,
                      child: ScoreboardView(game: game),
                    ),
                    CorrectionHistoryPanel(game: game, engine: engine),
                    PlayersPanel(
                      game: game,
                      connectionsAvailable:
                          serverState.status == HostServerStatus.running,
                      onSetOrder:
                          engineState.canStartRound &&
                              game.jeopardy?.pendingPickQuestionId == null &&
                              game.jeopardy?.pendingDailyDoubleId == null
                          ? (ids) => engine.add(SetPlayerOrderEvent(ids))
                          : null,
                      onKick: (id) => engine.add(KickPlayerEvent(id)),
                      onBan: (id) => engine.add(KickPlayerEvent(id, ban: true)),
                      onMerge: (source, target) => engine.add(
                        MergePlayersEvent(
                          sourcePlayerId: source,
                          targetPlayerId: target,
                        ),
                      ),
                      onAssignTeam: (playerId, teamId) => engine.add(
                        AssignTeamEvent(playerId: playerId, teamId: teamId),
                      ),
                    ),
                    if (game.jeopardy == null)
                      QuestionBankPanel(
                        game: game,
                        canStart: game.isStarted && engineState.canStartRound,
                        onStart: (questionId) =>
                            engine.add(StartRoundEvent(questionId)),
                      ),
                    ServerLogPanel(logs: serverState.logs),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
