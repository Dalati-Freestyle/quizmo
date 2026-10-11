/// The quizmaster dashboard.
///
/// Owns the [QuizEngineBloc] — the single source of truth of a session — and
/// the [HostServerCubit] that publishes it over the network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../common/adaptive_layout.dart';
import '../common/bundled_web_client.dart';
import '../common/scoreboard_view.dart';
import '../common/session_notifications.dart';
import '../player/player_page.dart';
import '../spectator/tv_page.dart';
import 'dashboard_panels.dart';
import 'host_server_cubit.dart';

/// Host facing screen: run the server, drive rounds, judge answers.
class HostDashboardPage extends StatelessWidget {
  /// Creates the dashboard for [quiz].
  const HostDashboardPage({required this.quiz, super.key});

  /// Quiz definition fixed for this hosted session.
  final Quiz quiz;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<QuizEngineBloc>(
          create: (_) => QuizEngineBloc(
            questionBank: quiz.questions,
            autoContinueBuzzer: false,
            teams: quiz.teamsById,
            mode: quiz.teams.isEmpty ? const SoloMode() : const TeamMode(),
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
            // Lets guests load the player client straight from this device, so
            // the LAN address is all they need.
            webClient: bundledWebClient(),
          ),
        ),
      ],
      child: _HostDashboardView(quizName: quiz.name),
    );
  }
}

class _HostDashboardView extends StatelessWidget {
  const _HostDashboardView({required this.quizName});

  final String quizName;

  @override
  Widget build(BuildContext context) {
    final engine = context.read<QuizEngineBloc>();

    return BlocBuilder<QuizEngineBloc, QuizEngineState>(
      builder: (context, engineState) {
        return BlocBuilder<HostServerCubit, HostServerState>(
          builder: (context, serverState) {
            final game = engineState.game;

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
                title: Text('Quizmaster · $quizName'),
                actions: [
                  IconButton(
                    tooltip: 'Preview the TV screen',
                    onPressed: openTvPreview,
                    icon: const Icon(Icons.tv),
                  ),
                  IconButton(
                    tooltip: 'Join this session as a local player',
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
                    tooltip: 'Reset scores',
                    onPressed: () => engine.add(const ResetGameEvent()),
                    icon: const Icon(Icons.restart_alt),
                  ),
                  PopupMenuButton<GameMode>(
                    tooltip: 'Game mode',
                    icon: const Icon(Icons.tune),
                    onSelected: (mode) => engine.add(ChangeGameModeEvent(mode)),
                    itemBuilder: (_) => const [
                      PopupMenuItem<GameMode>(
                        value: SoloMode(),
                        child: Text('Solo scoring'),
                      ),
                      PopupMenuItem<GameMode>(
                        value: TeamMode(),
                        child: Text('Team scoring (shared buzzer)'),
                      ),
                      PopupMenuItem<GameMode>(
                        value: TeamMode(sharedBuzzer: false),
                        child: Text('Team scoring (individual buzzers)'),
                      ),
                    ],
                  ),
                ],
              ),
              body: SessionNotifications(
                game: game,
                child: AdaptivePanelGrid(
                  panels: [
                    LiveRoundPanel(
                      state: engineState,
                      onJudge: (wasCorrect) =>
                          engine.add(JudgeBuzzerEvent(wasCorrect: wasCorrect)),
                      onReveal: () => engine.add(const RevealRoundEvent()),
                      onLock: () => engine.add(const LockBuzzerEvent()),
                      onReopenBuzzer: () =>
                          engine.add(const ReopenBuzzerEvent()),
                      onEndRound: () => engine.add(const EndRoundEvent()),
                      onNext: () => engine.add(const NextQuestionEvent()),
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
                          title: 'TV-Medienwiedergabe',
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
                                label: const Text('Abspielen'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => engine.add(
                                  const ControlTvMediaEvent(
                                    TvMediaAction.pause,
                                  ),
                                ),
                                icon: const Icon(Icons.pause),
                                label: const Text('Pause'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => engine.add(
                                  const ControlTvMediaEvent(
                                    TvMediaAction.restart,
                                  ),
                                ),
                                icon: const Icon(Icons.replay),
                                label: const Text('Neu starten'),
                              ),
                              Text(
                                game.tvMediaPaused
                                    ? 'TV: pausiert'
                                    : 'TV: Wiedergabe angefordert',
                              ),
                            ],
                          ),
                        ),
                    if (game.poker case final poker?)
                      PanelCard(
                        title: 'Pokerchips',
                        icon: Icons.casino_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${poker.startingChips} Startchips pro Team · ${poker.betting ? "Einsatzphase" : "Antwortphase"}',
                            ),
                            for (final team in game.teams.values)
                              Text(
                                '${team.name}: ${poker.chips[team.id] ?? 0} Chips · Einsatz: ${poker.wagers[team.id] ?? "–"}',
                              ),
                            if (poker.betting)
                              FilledButton(
                                onPressed: () =>
                                    engine.add(const OpenPokerAnswersEvent()),
                                child: const Text(
                                  'Einsätze schließen & Antworten öffnen',
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (game.jeopardy case final jeopardy?)
                      JeopardyBoardPanel(
                        game: game,
                        jeopardy: jeopardy,
                        canPick: engineState.canStartRound,
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
                      connectedPlayers: game.connectedPlayers.length,
                      onOpenTvPreview: openTvPreview,
                      onStart: () => context.read<HostServerCubit>().start(),
                      onStop: () => context.read<HostServerCubit>().stop(),
                    ),
                    PanelCard(
                      title: game.poker == null
                          ? 'Scoreboard · ${game.mode.label}'
                          : 'Pokerchips · Teams',
                      icon: Icons.leaderboard_outlined,
                      child: ScoreboardView(game: game),
                    ),
                    PlayersPanel(
                      game: game,
                      onKick: (id) => engine.add(KickPlayerEvent(id)),
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
                        canStart: engineState.canStartRound,
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
