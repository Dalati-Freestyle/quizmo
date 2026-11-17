/// The game sections of the admin view, shared by the real host dashboard and
/// the quiz preview.
///
/// Both screens build their game controls only through [buildGameSections]
/// and [JeopardyPickConfirmation], so the preview always shows the same admin
/// elements as a hosted game. The dashboard adds the host-only sections
/// (server, session access, guest Wi-Fi, recovery, server log), the preview
/// adds its simulation controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../common/adaptive_layout.dart';
import '../common/scoreboard_view.dart';
import '../l10n/app_localizations.dart';
import 'correction_history_panel.dart';
import 'dashboard_panels.dart';
import 'layout/dashboard_layout.dart';
import 'session_report_panel.dart';

/// Builds the game sections for [engineState] of [engine].
///
/// [startExtras] are added below the start button (e.g. the tech check on a
/// real host). [connectionsAvailable] tells the players panel whether online
/// states are meaningful.
Map<DashboardSection, Widget> buildGameSections(
  BuildContext context, {
  required QuizEngineBloc engine,
  required QuizEngineState engineState,
  required String quizName,
  bool connectionsAvailable = true,
  List<Widget> startExtras = const [],
}) {
  final game = engineState.game;
  return {
    if (!game.isStarted)
      DashboardSection.startQuiz: PanelCard(
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
              key: const ValueKey('start-quiz'),
              onPressed: () => engine.add(const StartGameEvent()),
              icon: const Icon(Icons.play_arrow),
              label: Text(context.tr("Quiz jetzt starten")),
            ),
            for (final extra in startExtras) ...[
              const SizedBox(height: 8),
              extra,
            ],
          ],
        ),
      ),
    DashboardSection.liveRound: LiveRoundPanel(
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
      onReopenBuzzer: () => engine.add(const ReopenBuzzerEvent()),
      onReopenBuzzerForAll: () =>
          engine.add(const ReopenBuzzerEvent(forAll: true)),
      onEndRound: () => engine.add(const EndRoundEvent()),
      onNext: () {
        if (game.isStarted) engine.add(const NextQuestionEvent());
      },
      onCloseRound: () => engine.add(const CloseRoundEvent()),
      onFinish: () => engine.add(const FinishQuizEvent()),
      onFinishEarly: () => engine.add(const FinishQuizEvent(early: true)),
    ),
    if (game.round.question case final question?)
      if ([
        ...question.media,
        if (game.round.status == RoundStatus.revealed)
          ...question.solutionMedia,
      ].any((m) => m is AudioAttachment || m is VideoAttachment))
        DashboardSection.media: PanelCard(
          title: context.tr("Medienwiedergabe"),
          icon: Icons.live_tv,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    engine.add(const ControlTvMediaEvent(TvMediaAction.play)),
                icon: const Icon(Icons.play_arrow),
                label: Text(context.tr("Abspielen")),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    engine.add(const ControlTvMediaEvent(TvMediaAction.pause)),
                icon: const Icon(Icons.pause),
                label: Text(context.tr("Pause")),
              ),
              OutlinedButton.icon(
                onPressed: () => engine.add(
                  const ControlTvMediaEvent(TvMediaAction.restart),
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
      DashboardSection.poker: PanelCard(
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
                onPressed: () => engine.add(const OpenPokerAnswersEvent()),
                child: Text(
                  context.tr("Einsätze schließen & Antworten öffnen"),
                ),
              ),
          ],
        ),
      ),
    if (game.jeopardy case final jeopardy?)
      DashboardSection.questions: JeopardyBoardPanel(
        game: game,
        jeopardy: jeopardy,
        canPick:
            game.isStarted &&
            engineState.canStartRound &&
            jeopardy.pendingPickQuestionId == null,
        maxWager: engine.maxDailyDoubleWager(game),
        onSelect: (questionId) =>
            engine.add(SelectJeopardyCellEvent(questionId)),
        onPlaceWager: (wager) => engine.add(PlaceDailyDoubleWagerEvent(wager)),
        onSetOrder: (ids) => engine.add(SetJeopardyOrderEvent(ids)),
        onSetTurn: (teamId) => engine.add(SetJeopardyTurnEvent(teamId)),
      )
    else
      DashboardSection.questions: QuestionBankPanel(
        game: game,
        canStart: game.isStarted && engineState.canStartRound,
        onStart: (questionId) => engine.add(StartRoundEvent(questionId)),
      ),
    DashboardSection.scoreboard: PanelCard(
      title: game.poker == null
          ? context.tr("Scoreboard · {0}", [context.tr(game.mode.label)])
          : context.tr("Pokerchips · Teams"),
      icon: Icons.leaderboard_outlined,
      child: ScoreboardView(game: game),
    ),
    DashboardSection.corrections: CorrectionHistoryPanel(
      game: game,
      engine: engine,
    ),
    if (game.isFinished)
      DashboardSection.report: SessionReportPanel(
        game: game,
        quizName: quizName,
      ),
    DashboardSection.players: PlayersPanel(
      game: game,
      connectionsAvailable: connectionsAvailable,
      onSetOrder:
          engineState.canStartRound &&
              game.jeopardy?.pendingPickQuestionId == null &&
              game.jeopardy?.pendingDailyDoubleId == null
          ? (ids) => engine.add(SetPlayerOrderEvent(ids))
          : null,
      onKick: (id) => engine.add(KickPlayerEvent(id)),
      onBan: (id) => engine.add(KickPlayerEvent(id, ban: true)),
      onMerge: (source, target) => engine.add(
        MergePlayersEvent(sourcePlayerId: source, targetPlayerId: target),
      ),
      onAssignTeam: (playerId, teamId) =>
          engine.add(AssignTeamEvent(playerId: playerId, teamId: teamId)),
    ),
  };
}

/// Asks the host to confirm a Jeopardy cell a player picked; shared by the
/// host dashboard and the preview.
class JeopardyPickConfirmation extends StatelessWidget {
  /// Wraps [child] for [engine].
  const JeopardyPickConfirmation({
    required this.engine,
    required this.child,
    super.key,
  });

  /// The engine whose picks are confirmed.
  final QuizEngineBloc engine;

  /// The screen below.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocListener<QuizEngineBloc, QuizEngineState>(
        bloc: engine,
        listenWhen: (previous, current) =>
            current.game.jeopardy?.pendingPickQuestionId != null &&
            (previous.game.jeopardy?.pendingPickQuestionId !=
                    current.game.jeopardy?.pendingPickQuestionId ||
                (previous.game.recoveryPaused &&
                    !current.game.recoveryPaused) ||
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
        child: child,
      );
}

/// Switches between solo and team scoring; shared by dashboard and preview.
class GameModeMenu extends StatelessWidget {
  /// Creates the menu for [engine].
  const GameModeMenu({required this.engine, super.key});

  /// The engine whose mode changes.
  final QuizEngineBloc engine;

  @override
  Widget build(BuildContext context) => PopupMenuButton<GameMode>(
    tooltip: context.tr("Game mode"),
    icon: const Icon(Icons.tune),
    onSelected: (mode) => engine.add(ChangeGameModeEvent(mode)),
    itemBuilder: (_) => [
      PopupMenuItem<GameMode>(
        value: const SoloMode(),
        child: Text(context.tr("Solo scoring")),
      ),
      PopupMenuItem<GameMode>(
        value: const TeamMode(),
        child: Text(context.tr("Team scoring (shared buzzer)")),
      ),
      PopupMenuItem<GameMode>(
        value: const TeamMode(sharedBuzzer: false),
        child: Text(context.tr("Team scoring (individual buzzers)")),
      ),
    ],
  );
}
