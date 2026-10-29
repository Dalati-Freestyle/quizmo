/// The authoritative quiz state machine.
///
/// The engine is plain `package:bloc` — no Flutter, no `dart:io` — so the exact
/// same instance drives the host UI, an embedded server inside a mobile app, a
/// Docker container and the unit tests.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';

import '../models/models.dart';
import '../sync/clock.dart';
import 'quiz_engine_event.dart';
import 'quiz_engine_state.dart';
import 'scoring_rules.dart';
import 'session_access.dart';

export 'quiz_engine_event.dart';
export 'quiz_engine_state.dart';

/// Owns the session and turns [QuizEngineEvent]s into [QuizEngineState]s.
///
/// ## Buzzer fairness
///
/// The engine never locks the buzzer on the first packet it sees. Instead the
/// first press opens a short *grace window* ([buzzerGraceWindow]). Presses that
/// arrive inside that window are merged into the queue and the whole queue is
/// sorted by the latency adjusted host timestamp. Only then is the floor handed
/// out. That is what lets a player on a slow link win a race they actually won.
///
/// ## Jeopardy
///
/// When a [JeopardyBoard] is supplied the session plays the Jeopardy format.
/// Questions are still ordinary [Question]s of any kind; the engine only
///
/// * lets the quizmaster pick them from the board
///   ([SelectJeopardyCellEvent]), rotating the pick between the teams,
/// * replaces their scoring rule by the points of the row (or the wager of a
///   Daily Double), and
/// * restricts who may answer: the picking team first, and — if the board
///   allows stealing — the other teams after a miss.
class QuizEngineBloc extends Bloc<QuizEngineEvent, QuizEngineState> {
  /// Creates an engine seeded with [questionBank], [teams] and [mode].
  QuizEngineBloc({
    List<Question> questionBank = const [],
    Map<String, Team> teams = const {},
    GameMode mode = const SoloMode(),
    JeopardyBoard? jeopardyBoard,
    int? pokerStartingChips,
    SolutionRevealMode revealMode = SolutionRevealMode.afterEachQuestion,
    this.buzzerGraceWindow = const Duration(milliseconds: 350),
    this.autoContinueBuzzer = true,
    NowMicros now = systemNowMicros,
    Timer Function(Duration, void Function()) createTimer = Timer.new,
    GameState? restoredGame,
    this.recoverySessionId,
    Map<String, String> resumeTokenHashes = const {},
    SessionAccessState accessState = const SessionAccessState(),
  }) : _now = now,
       access = SessionAccess(accessState),
       _createTimer = createTimer,
       resumeTokenHashes = Map.of(resumeTokenHashes),
       recoveryPlayerIds = Set.of(
         restoredGame?.players.keys ?? const <String>[],
       ),
       _initialBank = questionBank,
       _initialBoard = jeopardyBoard,
       super(
         QuizEngineState(
           game:
               restoredGame ??
               GameState(
                 questionBank: questionBank,
                 totalQuestionCount: questionBank.length,
                 teams: teams,
                 mode: pokerStartingChips == null ? mode : const TeamMode(),
                 jeopardy: jeopardyBoard == null
                     ? null
                     : JeopardyState.start(jeopardyBoard, teams.keys),
                 poker: pokerStartingChips == null
                     ? null
                     : PokerState.start(pokerStartingChips, teams.keys),
                 hostTimeMicros: now(),
                 revealMode: revealMode,
               ),
         ),
       ) {
    if (restoredGame != null && !restoredGame.recoveryPaused) {
      throw ArgumentError('Restored games must be paused.');
    }
    on<ResumeRecoveredGameEvent>(_onResumeRecoveredGame);
    on<PauseForRecoveryEvent>((event, emit) {
      if (state.game.recoveryPaused) return;
      _graceTimer?.cancel();
      recoveryPlayerIds.addAll(state.game.players.keys);
      emit(
        _publish(
          state.game.copyWith(
            recoveryPaused: true,
            hostTimeMicros: _now(),
            tvMediaPaused: true,
          ),
          notice: 'Recovery paused. Confirm how to resume first.',
        ),
      );
    });
    on<RebindRecoveredPlayerEvent>((event, emit) {
      final game = state.game;
      final original = game.players[event.playerId];
      final temporary = game.players[event.temporaryPlayerId];
      final hash = this.resumeTokenHashes[event.temporaryPlayerId];
      if (!game.recoveryPaused ||
          original == null ||
          temporary == null ||
          original.isConnected ||
          !temporary.isConnected ||
          hash == null ||
          !recoveryPlayerIds.contains(original.id) ||
          recoveryPlayerIds.contains(temporary.id)) {
        emit(state.copyWith(notice: 'This participant cannot be reassigned.'));
        return;
      }
      this.resumeTokenHashes[original.id] = hash;
      identityTransfers[temporary.id] = original.id;
      final cleaned = _removePlayer(game, temporary.id);
      emit(
        _publish(
          cleaned.copyWith(
            players: {
              ...cleaned.players,
              original.id: original.copyWith(
                isConnected: true,
                clockOffsetMicros: temporary.clockOffsetMicros,
                roundTripMicros: temporary.roundTripMicros,
              ),
            },
          ),
        ),
      );
    });
    if (revealMode != SolutionRevealMode.afterEachQuestion &&
        (jeopardyBoard != null || pokerStartingChips != null)) {
      throw ArgumentError(
        'Deferred reveal is only supported for standard quizzes.',
      );
    }
    on<StartGameEvent>((event, emit) {
      if (!state.game.isStarted) {
        emit(
          _publish(
            state.game.copyWith(isStarted: true),
            notice: 'Quiz gestartet.',
          ),
        );
      }
    });
    on<PlayerJoinedEvent>(_onPlayerJoined);
    on<RenameTeamEvent>(_onRenameTeam);
    on<PlayerLeftEvent>(_onPlayerLeft);
    on<KickPlayerEvent>(_onKickPlayer);
    on<MergePlayersEvent>(_onMergePlayers);
    on<ReopenBuzzerEvent>(_onReopenBuzzer);
    on<EndRoundEvent>(_onEndRound);
    on<TimeSyncEvent>(_onTimeSync);
    on<AssignTeamEvent>(_onAssignTeam);
    on<ChangeGameModeEvent>(_onChangeGameMode);
    on<StartRoundEvent>(_onStartRound);
    on<NextQuestionEvent>(_onNextQuestion);
    on<SubmitAnswerEvent>(_onSubmitAnswer);
    on<BuzzerPressEvent>(_onBuzzerPress);
    on<LockBuzzerEvent>(_onLockBuzzer);
    on<JudgeBuzzerEvent>(_onJudgeBuzzer);
    on<JudgeAnswerEvent>(_onJudgeAnswer);
    on<CorrectScoreEvent>(_onCorrectScore);
    on<UndoCorrectionEvent>(_onUndoCorrection);
    on<RevealRoundEvent>(_onRevealRound);
    on<CloseRoundEvent>(_onCloseRound);
    on<SelectJeopardyCellEvent>(_onSelectJeopardyCell);
    on<ConfirmQuestionPickEvent>(_onConfirmQuestionPick);
    on<SetPlayerOrderEvent>((event, emit) {
      final game = state.game;
      if (!state.canStartRound ||
          game.jeopardy?.pendingPickQuestionId != null ||
          game.jeopardy?.pendingDailyDoubleId != null ||
          !isPermutation(event.playerIds, game.players.keys.toList())) {
        return;
      }
      final updated = game.copyWith(
        playerOrder: List.unmodifiable(event.playerIds),
      );
      emit(
        _publish(
          updated.copyWith(
            jeopardy: updated.jeopardy?.copyWith(
              currentTeamId: game.completedQuestionIds.isEmpty
                  ? updated.selectionOrder.firstOrNull
                  : updated.jeopardy?.currentTeamId,
            ),
          ),
        ),
      );
    });
    on<SetJeopardyOrderEvent>((event, emit) {
      final game = state.game;
      final jeopardy = game.jeopardy;
      if (jeopardy == null ||
          !state.canStartRound ||
          jeopardy.pendingDailyDoubleId != null ||
          jeopardy.pendingPickQuestionId != null) {
        return;
      }
      if (!isPermutation(event.teamIds, game.participantIds)) {
        return;
      }
      emit(
        _publish(
          game.copyWith(
            jeopardy: jeopardy.copyWith(
              turnOrder: List.unmodifiable(event.teamIds),
              currentTeamId: game.completedQuestionIds.isEmpty
                  ? event.teamIds.firstOrNull
                  : jeopardy.currentTeamId,
            ),
          ),
        ),
      );
    });
    on<ControlTvMediaEvent>((event, emit) {
      final game = state.game;
      if (game.round.question == null) return;
      emit(
        _publish(
          game.copyWith(
            tvMediaPaused: event.action == TvMediaAction.pause,
            tvMediaCommandRevision: game.tvMediaCommandRevision + 1,
            tvMediaRevision:
                game.tvMediaRevision +
                (event.action == TvMediaAction.restart ? 1 : 0),
          ),
        ),
      );
    });
    on<PlaceDailyDoubleWagerEvent>(_onPlaceDailyDoubleWager);
    on<SetJeopardyTurnEvent>(_onSetJeopardyTurn);
    if (pokerStartingChips != null &&
        (pokerStartingChips < 1 ||
            pokerStartingChips > 1000000 ||
            jeopardyBoard != null)) {
      throw ArgumentError('Invalid poker configuration.');
    }
    on<PlacePokerWagerEvent>(_onPlacePokerWager);
    on<OpenPokerAnswersEvent>(_onOpenPokerAnswers);
    on<ResetGameEvent>(_onResetGame);
    on<ExpireRoundEvent>((event, emit) {
      final game = state.game;
      final round = game.round;
      if (round.question?.id != event.questionId ||
          round.startedAtHostMicros != event.startedAt ||
          round.hasSoftTimer ||
          !round.status.acceptsInput ||
          (game.poker?.betting ?? false)) {
        return;
      }
      _graceTimer?.cancel();
      if (round.nextCandidate != null) {
        _onLockBuzzer(const LockBuzzerEvent(), emit);
        return;
      }
      emit(
        _publish(
          game.copyWith(round: round.copyWith(status: RoundStatus.locked)),
          notice: 'Zeit abgelaufen. Antworten sind geschlossen.',
        ),
      );
    });
  }

  /// How long the engine waits for in-flight presses before locking the buzzer.
  final Duration buzzerGraceWindow;
  final bool autoContinueBuzzer;

  final NowMicros _now;
  final List<Question> _initialBank;
  final JeopardyBoard? _initialBoard;
  Timer? _graceTimer;
  final Timer Function(Duration, void Function()) _createTimer;
  Timer? _roundTimer;
  final String? recoverySessionId;
  final Map<String, String> resumeTokenHashes;
  final SessionAccess access;
  final Set<String> recoveryPlayerIds;
  final Map<String, String> identityTransfers = {};
  Future<void> Function()? persistRecovery;
  GameState? committedRecoveryGame;
  GameState get publishedGame {
    final game = committedRecoveryGame ?? state.game;
    return state.game.recoveryPaused
        ? game.copyWith(recoveryPaused: true, tvMediaPaused: true)
        : game;
  }

  @override
  void on<E extends QuizEngineEvent>(
    EventHandler<E, QuizEngineState> handler, {
    EventTransformer<E>? transformer,
  }) {
    super.on<E>((event, emit) async {
      if (state.game.recoveryPaused &&
          event is! ResumeRecoveredGameEvent &&
          event is! RebindRecoveredPlayerEvent &&
          event is! PlayerJoinedEvent &&
          event is! PlayerLeftEvent &&
          event is! TimeSyncEvent) {
        emit(
          state.copyWith(
            notice: 'Recovery paused. Confirm how to resume first.',
          ),
        );
        return;
      }
      await handler(event, emit);
    }, transformer: transformer);
  }

  void _onResumeRecoveredGame(
    ResumeRecoveredGameEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    if (!game.recoveryPaused) return;
    final round = game.round;
    final start = round.startedAtHostMicros;
    final delta = _now() - game.hostTimeMicros;
    AnswerSubmission shift(AnswerSubmission answer) =>
        AnswerSubmission.fromJson({
          ...answer.toJson(),
          'clientTimestampMicros': answer.clientTimestampMicros + delta,
          'hostTimestampMicros': answer.hostTimestampMicros + delta,
        });
    emit(
      _publish(
        game.copyWith(
          recoveryPaused: false,
          tvMediaPaused: true,
          round: round.copyWith(
            startedAtHostMicros: start == null ? null : start + delta,
            timerRestartedAtHostMicros:
                event.timerPolicy == RecoveryTimerPolicy.restart
                ? _now()
                : round.timerRestartedAtHostMicros == null
                ? null
                : round.timerRestartedAtHostMicros! + delta,
            recoverySoftTimer:
                event.timerPolicy == RecoveryTimerPolicy.soft ||
                (event.timerPolicy == RecoveryTimerPolicy.savedTime &&
                    round.recoverySoftTimer),
            answers: round.answers.map(
              (id, answer) => MapEntry(id, shift(answer)),
            ),
            buzzerQueue: round.buzzerQueue
                .map(
                  (press) => BuzzerPress(
                    playerId: press.playerId,
                    questionId: press.questionId,
                    clientTimestampMicros: press.clientTimestampMicros + delta,
                    clockOffsetMicros: press.clockOffsetMicros,
                  ),
                )
                .toList(),
          ),
        ),
        notice: 'Recovered game resumed. Media stays paused.',
      ),
    );
    if (state.game.round.status.acceptsInput &&
        state.game.round.nextCandidate != null) {
      add(const LockBuzzerEvent());
    }
  }

  /// The host clock, exposed so the UI can render latency relative to it.
  int get hostNowMicros =>
      state.game.recoveryPaused ? state.game.hostTimeMicros : _now();

  @override
  Future<void> close() {
    _graceTimer?.cancel();
    _roundTimer?.cancel();
    unawaited(access.close());
    return super.close();
  }

  void _onKickPlayer(KickPlayerEvent event, Emitter<QuizEngineState> emit) {
    if (!state.game.players.containsKey(event.playerId)) return;
    resumeTokenHashes.remove(event.playerId);
    if (event.ban) access.ban(event.playerId);
    emit(_publish(_removePlayer(state.game, event.playerId)));
    if (state.game.round.status.acceptsInput &&
        state.game.round.buzzerQueue.isNotEmpty) {
      add(const LockBuzzerEvent());
    }
  }

  void _onMergePlayers(MergePlayersEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final source = game.players[event.sourcePlayerId];
    final target = game.players[event.targetPlayerId];
    if (source == null ||
        target == null ||
        source.isConnected ||
        !target.isConnected ||
        source.id == target.id) {
      return;
    }
    final answers = {...game.round.answers};
    final answerVerdicts = {...game.round.answerVerdicts};
    final acceptedElapsed = {...game.round.acceptedElapsedMicros}
      ..remove(source.id);
    final answer = answers.remove(source.id);
    final sourceVerdict = answerVerdicts.remove(source.id);
    if (answer != null && !answers.containsKey(target.id)) {
      answers[target.id] = answer.withPlayerId(target.id);
      answerVerdicts.remove(target.id);
      if (sourceVerdict != null) answerVerdicts[target.id] = sourceVerdict;
      final elapsed = game.round.acceptedElapsedMicros[source.id];
      if (elapsed != null) acceptedElapsed[target.id] = elapsed;
    }
    final totals = {...game.scores.byPlayer}..remove(source.id);
    totals[target.id] =
        game.scores.scoreOf(source.id) + game.scores.scoreOf(target.id);
    final history = game.scores.history
        .map(
          (e) => e.playerId != source.id
              ? e
              : ScoreEvent(
                  playerId: target.id,
                  questionId: e.questionId,
                  points: e.points,
                  reason: e.reason,
                  atHostMicros: e.atHostMicros,
                ),
        )
        .toList();
    final cleaned = _removePlayer(game, source.id);
    final queue = <String, BuzzerPress>{};
    for (final press in game.round.buzzerQueue) {
      final migrated = press.playerId == source.id
          ? press.withPlayerId(target.id)
          : press;
      final previous = queue[migrated.playerId];
      if (previous == null ||
          migrated.hostTimestampMicros < previous.hostTimestampMicros) {
        queue[migrated.playerId] = migrated;
        final elapsed = game.round.acceptedElapsedMicros[press.playerId];
        if (elapsed != null) acceptedElapsed[migrated.playerId] = elapsed;
      }
    }
    final orderedQueue = queue.values.toList()
      ..sort((a, b) => a.hostTimestampMicros.compareTo(b.hostTimestampMicros));
    emit(
      _publish(
        cleaned.copyWith(
          scores: ScoreState(byPlayer: totals, history: history),
          round: cleaned.round.copyWith(
            answers: answers,
            acceptedElapsedMicros: acceptedElapsed,
            answerVerdicts: answerVerdicts,
            buzzerQueue: orderedQueue,
            status: game.round.status,
            activePlayerId: game.round.activePlayerId == source.id
                ? target.id
                : game.round.activePlayerId,
            lockedOutPlayerIds: {
              ...cleaned.round.lockedOutPlayerIds,
              if (game.round.lockedOutPlayerIds.contains(source.id)) target.id,
            },
          ),
        ),
      ),
    );
  }

  GameState _removePlayer(GameState game, String id) {
    final players = {...game.players}..remove(id);
    final totals = {...game.scores.byPlayer}..remove(id);
    final answers = {...game.round.answers}..remove(id);
    final activeRemoved = game.round.activePlayerId == id;
    return game.copyWith(
      players: players,
      playerOrder: game.playerOrder.where((p) => p != id).toList(),
      jeopardy: game.jeopardy?.copyWith(
        currentTeamId:
            game.mode is SoloMode &&
                game.jeopardy?.currentTeamId == id &&
                !(game.jeopardy?.hasActiveQuestion ?? false)
            ? game.selectionOrder.where((p) => p != id).firstOrNull
            : game.jeopardy?.currentTeamId,
        pendingPickQuestionId: game.jeopardy?.pendingPickPlayerId == id
            ? null
            : game.jeopardy?.pendingPickQuestionId,
        pendingPickPlayerId: game.jeopardy?.pendingPickPlayerId == id
            ? null
            : game.jeopardy?.pendingPickPlayerId,
      ),
      scores: ScoreState(
        byPlayer: totals,
        history: game.scores.history.where((e) => e.playerId != id).toList(),
      ),
      round: game.round.copyWith(
        answers: answers,
        acceptedElapsedMicros: {...game.round.acceptedElapsedMicros}
          ..remove(id),
        answerVerdicts: {...game.round.answerVerdicts}..remove(id),
        buzzerQueue: game.round.buzzerQueue
            .where((e) => e.playerId != id)
            .toList(),
        lockedOutPlayerIds: {...game.round.lockedOutPlayerIds}..remove(id),
        activePlayerId: activeRemoved ? null : game.round.activePlayerId,
        status: activeRemoved && game.round.status == RoundStatus.locked
            ? RoundStatus.acceptingAnswers
            : game.round.status,
      ),
    );
  }

  void _onReopenBuzzer(ReopenBuzzerEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    if (round.question is! BuzzerQuestion ||
        round.status == RoundStatus.revealed ||
        round.status == RoundStatus.idle ||
        (game.poker?.betting ?? false) ||
        (round.status == RoundStatus.locked && round.activePlayerId != null)) {
      return;
    }
    if (round.buzzerAnswerCorrect) {
      return;
    }
    if (game.poker != null && _pokerEveryoneSettled(game)) return;
    _graceTimer?.cancel();
    emit(
      _publish(
        game.copyWith(
          round: round.copyWith(
            status: RoundStatus.acceptingAnswers,
            startedAtHostMicros: _now(),
            timerRestartedAtHostMicros: null,
            activePlayerId: null,
            buzzerQueue: const [],
            lockedOutPlayerIds: event.forAll
                ? {
                    for (final player in game.players.values)
                      if (game.poker?.settledTeamIds.contains(player.teamId) ??
                          false)
                        player.id,
                  }
                : round.lockedOutPlayerIds,
            buzzerOpenForAll:
                round.buzzerOpenForAll ||
                (event.forAll &&
                    !(game.jeopardy?.activeIsDailyDouble ?? false)),
          ),
        ),
        notice: event.forAll
            ? 'Buzzer für alle freigegeben.'
            : 'Buzzer freigegeben. Alle übrigen Spieler dürfen erneut buzzern.',
      ),
    );
  }

  void _onEndRound(EndRoundEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final question = game.round.question;
    if (question == null ||
        game.round.status == RoundStatus.revealed ||
        (game.poker?.betting ?? false)) {
      return;
    }
    _graceTimer?.cancel();
    if (_awaitManualGrades(game, emit)) return;
    final scored = question is BuzzerQuestion
        ? game
        : _scoreAnswers(game, question);
    emit(_publish(_reveal(scored), notice: 'Runde beendet.'));
  }

  // ---------------------------------------------------------------- lobby ---

  void _onPlayerJoined(PlayerJoinedEvent event, Emitter<QuizEngineState> emit) {
    var game = state.game;
    if (event.createdTeam case final team?) {
      if (game.players.containsKey(event.player.id) ||
          game.teams.containsKey(team.id) ||
          event.player.teamId != team.id ||
          team.name.trim().isEmpty ||
          team.name.trim().length > 60) {
        return;
      }
      game = game.copyWith(
        teams: {...game.teams, team.id: team},
        poker: game.poker?.copyWith(
          chips: {...game.poker!.chips, team.id: game.poker!.startingChips},
        ),
        jeopardy: game.jeopardy?.currentTeamId == null
            ? game.jeopardy?.copyWith(currentTeamId: team.id)
            : game.jeopardy,
      );
    }
    if (event.player.teamId != null &&
        !game.teams.containsKey(event.player.teamId)) {
      return;
    }
    final existing = game.players[event.player.id];
    final player = existing == null
        ? event.player
        : existing.copyWith(
            name: event.player.name,
            teamId: existing.teamId,
            isConnected: true,
            clockOffsetMicros: event.player.clockOffsetMicros,
            roundTripMicros: event.player.roundTripMicros,
          );

    var updated = game.copyWith(
      players: {...game.players, player.id: player},
      scores: game.scores.withParticipant(player.id),
    );
    if (updated.jeopardy != null &&
        !updated.jeopardy!.hasActiveQuestion &&
        updated.jeopardy!.pendingDailyDoubleId == null &&
        updated.jeopardy!.pendingPickQuestionId == null &&
        updated.completedQuestionIds.isEmpty &&
        (game.players.isEmpty || updated.jeopardy!.currentTeamId == null)) {
      updated = updated.copyWith(
        jeopardy: updated.jeopardy!.copyWith(
          currentTeamId: updated.selectionOrder.firstOrNull,
        ),
      );
    }
    emit(_publish(updated, notice: '${player.name} joined.'));
  }

  void _onPlayerLeft(PlayerLeftEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final player = game.players[event.playerId];
    if (player == null || !player.isConnected) return;

    emit(
      _publish(
        game.copyWith(
          players: {
            ...game.players,
            player.id: player.copyWith(isConnected: false),
          },
        ),
        notice: '${player.name} left.',
      ),
    );
  }

  void _onRenameTeam(RenameTeamEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final player = game.players[event.playerId];
    final team = game.teams[player?.teamId];
    final name = event.name.trim();
    if (player == null ||
        !player.isConnected ||
        team == null ||
        name.isEmpty ||
        name.length > 60) {
      return;
    }
    emit(
      _publish(
        game.copyWith(
          teams: {
            ...game.teams,
            team.id: Team(id: team.id, name: name, colorValue: team.colorValue),
          },
        ),
      ),
    );
  }

  void _onTimeSync(TimeSyncEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final player = game.players[event.playerId];
    if (player == null) return;

    emit(
      _publish(
        game.copyWith(
          players: {
            ...game.players,
            player.id: player.copyWith(
              clockOffsetMicros: event.clockOffsetMicros,
              roundTripMicros: event.roundTripMicros,
            ),
          },
        ),
      ),
    );
  }

  void _onAssignTeam(AssignTeamEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final player = game.players[event.playerId];
    if (player == null) return;
    if (game.poker != null &&
        (!(state.canStartRound || game.poker!.betting) ||
            !game.teams.containsKey(event.teamId))) {
      return;
    }

    emit(
      _publish(
        game.copyWith(
          players: {
            ...game.players,
            player.id: player.copyWith(teamId: event.teamId),
          },
        ),
      ),
    );
  }

  void _onChangeGameMode(
    ChangeGameModeEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    if (state.game.poker != null ||
        !state.canStartRound ||
        state.game.jeopardy?.pendingPickQuestionId != null ||
        state.game.jeopardy?.pendingDailyDoubleId != null) {
      return;
    }
    final updated = state.game.copyWith(mode: event.mode);
    emit(
      _publish(
        updated.copyWith(
          jeopardy: updated.jeopardy?.copyWith(
            turnOrder: const [],
            currentTeamId: updated.participantIds.firstOrNull,
          ),
        ),
        notice: 'Mode switched to ${event.mode.label}.',
      ),
    );
  }

  // ---------------------------------------------------------------- round ---

  void _onStartRound(StartRoundEvent event, Emitter<QuizEngineState> emit) {
    if (state.game.round.question?.requiresManualGrading == true &&
        !state.canStartRound) {
      emit(state.copyWith(notice: 'Finish the current question first.'));
      return;
    }
    final game = state.game.copyWith(isStarted: true);
    if (game.jeopardy != null) {
      // On a board every round starts by picking a cell, so that the points,
      // the turn rotation and the answer restrictions cannot be bypassed.
      _onSelectJeopardyCell(SelectJeopardyCellEvent(event.questionId), emit);
      return;
    }
    if (game.poker != null &&
        (!state.canStartRound ||
            game.completedQuestionIds.contains(event.questionId))) {
      return;
    }
    final question = game.questionById(event.questionId);
    if (question == null) {
      emit(state.copyWith(notice: 'Unknown question "${event.questionId}".'));
      return;
    }

    _graceTimer?.cancel();
    emit(
      _publish(
        game.copyWith(
          poker: game.poker?.copyWith(
            wagers: const {},
            settledTeamIds: const {},
            betting: true,
          ),
          round: RoundState(
            question: question,
            status: RoundStatus.acceptingAnswers,
            startedAtHostMicros: _now(),
          ),
        ),
        notice: 'Round started: ${question.prompt}',
      ),
    );
  }

  void _onNextQuestion(NextQuestionEvent event, Emitter<QuizEngineState> emit) {
    if (state.game.jeopardy != null) {
      emit(state.copyWith(notice: 'Pick the next question on the board.'));
      return;
    }
    final next = state.game.nextPendingQuestion;
    if (next == null) {
      emit(state.copyWith(notice: 'No pending questions left.'));
      return;
    }
    _onStartRound(StartRoundEvent(next.id), emit);
  }

  void _onSubmitAnswer(SubmitAnswerEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    final answer = event.answer;

    final rejection = _rejectSubmission(
      round,
      answer.playerId,
      answer.questionId,
    );
    if (rejection != null) {
      emit(state.copyWith(notice: rejection));
      return;
    }
    if (round.question is BuzzerQuestion ||
        !(round.question?.accepts(answer) ?? false)) {
      emit(state.copyWith(notice: 'Invalid answer for this question.'));
      return;
    }
    if (round.answers.containsKey(answer.playerId)) {
      emit(state.copyWith(notice: 'Only the first answer counts.'));
      return;
    }
    if (_teamAlreadyAnswered(game, answer.playerId)) {
      emit(state.copyWith(notice: 'Your team already answered.'));
      return;
    }

    var updated = game.copyWith(
      round: round.copyWith(
        answers: {...round.answers, answer.playerId: answer},
        acceptedElapsedMicros: {
          ...round.acceptedElapsedMicros,
          answer.playerId: round
              .timerElapsedAt(answer.hostTimestampMicros)
              .inMicroseconds,
        },
      ),
    );

    final allAnswered = _everyoneAnswered(updated);
    if (allAnswered && round.question!.requiresManualGrading) {
      updated = updated.copyWith(
        round: updated.round.copyWith(status: RoundStatus.locked),
      );
    }
    emit(
      _publish(
        updated.copyWith(
          allAnswersRevision: game.allAnswersRevision + (allAnswered ? 1 : 0),
        ),
      ),
    );
    if (allAnswered &&
        !round.question!.requiresManualGrading &&
        !round.hasSoftTimer) {
      add(const RevealRoundEvent());
    }
  }

  void _onJudgeAnswer(JudgeAnswerEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    if (round.question?.requiresManualGrading != true ||
        round.question?.id != event.questionId ||
        round.startedAtHostMicros != event.startedAtHostMicros ||
        (round.status != RoundStatus.acceptingAnswers &&
            round.status != RoundStatus.locked) ||
        !round.answers.containsKey(event.playerId) ||
        (game.poker?.betting ?? false)) {
      emit(state.copyWith(notice: 'Diese Antwort kann nicht bewertet werden.'));
      return;
    }
    final value = event.wasCorrect ? 1 : 0;
    if (round.answerVerdicts[event.playerId] == value) return;
    final updated = game.copyWith(
      round: round.copyWith(
        answerVerdicts: {...round.answerVerdicts, event.playerId: value},
      ),
    );
    emit(
      _publish(
        _recordJudgment(
          game,
          updated,
          event.playerId,
          CorrectionKind.answer,
          round.answerVerdicts[event.playerId],
          value,
          event.reason,
        ),
      ),
    );
  }

  bool _awaitManualGrades(GameState game, Emitter<QuizEngineState> emit) {
    if (game.round.pendingGradeCount == 0) return false;
    emit(
      _publish(
        game.copyWith(round: game.round.copyWith(status: RoundStatus.locked)),
        notice: 'Bitte erst alle eingegangenen Antworten bewerten.',
      ),
    );
    return true;
  }

  GameState _recordJudgment(
    GameState before,
    GameState after,
    String playerId,
    CorrectionKind kind,
    int? beforeValue,
    int afterValue,
    String? reason,
  ) {
    final player = before.players[playerId]!;
    final buzzer = kind == CorrectionKind.buzzer;
    return after.copyWith(
      corrections: [
        ...before.corrections,
        ManualCorrection(
          id: 'judgment-${before.corrections.length + 1}',
          kind: kind,
          questionId: before.round.question!.id,
          roundStartedAt: before.round.startedAtHostMicros!,
          playerId: playerId,
          teamId: before.mode is TeamMode ? player.teamId : null,
          participantName: before.mode is TeamMode
              ? '${before.teams[player.teamId]?.name ?? player.teamId} / ${player.name}'
              : player.name,
          beforeValue: beforeValue,
          afterValue: afterValue,
          atHostMicros: _now(),
          reason: reason,
          scoreDeltas: {
            for (final id in before.players.keys)
              if (after.scores.scoreOf(id) != before.scores.scoreOf(id))
                id: after.scores.scoreOf(id) - before.scores.scoreOf(id),
          },
          chipDeltas: {
            for (final id in before.poker?.chips.keys ?? const <String>[])
              if (after.poker!.chips[id] != before.poker!.chips[id])
                id: after.poker!.chips[id]! - before.poker!.chips[id]!,
          },
          beforeRound: buzzer ? before.round : null,
          afterRound: buzzer ? after.round : null,
          beforeJeopardy: buzzer ? before.jeopardy : null,
          afterJeopardy: buzzer ? after.jeopardy : null,
          beforePoker: buzzer ? before.poker : null,
          afterPoker: buzzer ? after.poker : null,
          beforeFinished: before.isFinished,
          afterFinished: after.isFinished,
          wasCompleted: before.completedQuestionIds.contains(
            before.round.question!.id,
          ),
        ),
      ],
    );
  }

  void _onCorrectScore(CorrectScoreEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final player = game.players[event.playerId];
    if (game.recoveryPaused ||
        player == null ||
        event.requestId.isEmpty ||
        event.delta == 0 ||
        game.round.question?.id != event.questionId ||
        game.round.startedAtHostMicros != event.roundStartedAt ||
        (game.poker != null && !game.poker!.chips.containsKey(player.teamId))) {
      emit(state.copyWith(notice: 'Diese Korrektur ist nicht zulässig.'));
      return;
    }
    final id = 'score-${event.requestId}';
    if (game.corrections.any((entry) => entry.id == id)) {
      emit(state.copyWith(notice: 'Diese Korrektur wurde bereits angewendet.'));
      return;
    }
    final poker = game.poker;
    final previous = poker == null
        ? game.scores.scoreOf(player.id)
        : poker.chips[player.teamId]!;
    final next = previous + event.delta;
    if (poker != null && next < 0) {
      emit(
        state.copyWith(notice: 'Die Korrektur würde negative Chips erzeugen.'),
      );
      return;
    }
    final entry = ManualCorrection(
      id: id,
      kind: poker == null ? CorrectionKind.points : CorrectionKind.chips,
      questionId: event.questionId,
      roundStartedAt: event.roundStartedAt,
      playerId: player.id,
      teamId: game.mode is TeamMode ? player.teamId : null,
      participantName: game.mode is TeamMode
          ? '${game.teams[player.teamId]?.name ?? player.teamId} / ${player.name}'
          : player.name,
      beforeValue: previous,
      afterValue: next,
      atHostMicros: _now(),
      reason: event.reason,
      scoreDeltas: poker == null ? {player.id: event.delta} : const {},
      chipDeltas: poker == null ? const {} : {player.teamId!: event.delta},
    );
    emit(
      _publish(
        _applyCorrectionDeltas(
          game,
          entry,
        ).copyWith(corrections: [...game.corrections, entry]),
      ),
    );
  }

  String? correctionUndoError(ManualCorrection entry) {
    final game = state.game;
    if (game.recoveryPaused) return 'Zuerst die Wiederherstellung fortsetzen.';
    if (entry.reversesId != null) {
      return 'Gegenkorrekturen können nicht zurückgenommen werden.';
    }
    if (!game.corrections.contains(entry)) return 'Unbekannte Korrektur.';
    if (game.corrections.any((e) => e.reversesId == entry.id)) {
      return 'Diese Korrektur wurde bereits zurückgenommen.';
    }
    final player = game.players[entry.playerId];
    if (player == null ||
        (game.mode is TeamMode ? player.teamId : null) != entry.teamId ||
        entry.scoreDeltas.keys.any((id) => !game.players.containsKey(id))) {
      return 'Die betroffenen Teilnehmer oder Teams wurden verändert.';
    }
    for (final delta in entry.chipDeltas.entries) {
      final chips = game.poker?.chips[delta.key];
      if (chips == null || chips - delta.value < 0) {
        return 'Ausgezahlte Chips wurden bereits eingesetzt. Rücknahme gesperrt.';
      }
    }
    switch (entry.kind) {
      case CorrectionKind.points:
      case CorrectionKind.chips:
        return null;
      case CorrectionKind.answer:
        if (game.round.question?.id != entry.questionId ||
            game.round.startedAtHostMicros != entry.roundStartedAt ||
            game.round.status == RoundStatus.revealed ||
            game.round.answerVerdicts[entry.playerId] != entry.afterValue ||
            !game.round.answers.containsKey(entry.playerId)) {
          return 'Die Runde wurde bereits aufgelöst oder die Bewertung verändert.';
        }
        final index = game.corrections.indexOf(entry);
        final reversed = game.corrections.map((e) => e.reversesId).toSet();
        if (game.corrections
            .skip(index + 1)
            .any(
              (e) =>
                  e.kind == CorrectionKind.answer &&
                  e.reversesId == null &&
                  !reversed.contains(e.id) &&
                  e.playerId == entry.playerId &&
                  e.questionId == entry.questionId &&
                  e.roundStartedAt == entry.roundStartedAt,
            )) {
          return 'Zuerst die spätere Bewertung zurücknehmen.';
        }
        return null;
      case CorrectionKind.buzzer:
        if (game.round != entry.afterRound ||
            game.jeopardy != entry.afterJeopardy ||
            game.poker?.copyWith(chips: entry.afterPoker?.chips) !=
                entry.afterPoker ||
            game.isFinished != entry.afterFinished) {
          return 'Weitere Spielaktionen hängen von dieser Bewertung ab.';
        }
        return null;
    }
  }

  void _onUndoCorrection(
    UndoCorrectionEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final entry = game.corrections
        .where((e) => e.id == event.correctionId)
        .firstOrNull;
    final error = entry == null
        ? 'Unbekannte Korrektur.'
        : correctionUndoError(entry);
    if (error != null) {
      emit(state.copyWith(notice: error));
      return;
    }
    final original = entry!;
    final inverse = ManualCorrection(
      id: 'undo-${original.id}',
      kind: original.kind,
      questionId: original.questionId,
      roundStartedAt: original.roundStartedAt,
      playerId: original.playerId,
      teamId: original.teamId,
      participantName: original.participantName,
      beforeValue: switch (original.kind) {
        CorrectionKind.points => game.scores.scoreOf(original.playerId),
        CorrectionKind.chips => game.poker!.chips[original.teamId]!,
        _ => original.afterValue,
      },
      afterValue: switch (original.kind) {
        CorrectionKind.points =>
          game.scores.scoreOf(original.playerId) -
              original.scoreDeltas[original.playerId]!,
        CorrectionKind.chips =>
          game.poker!.chips[original.teamId]! -
              original.chipDeltas[original.teamId]!,
        _ => original.beforeValue,
      },
      atHostMicros: _now(),
      reason: event.reason,
      reversesId: original.id,
      scoreDeltas: original.scoreDeltas.map(
        (id, delta) => MapEntry(id, -delta),
      ),
      chipDeltas: original.chipDeltas.map((id, delta) => MapEntry(id, -delta)),
    );
    var updated = _applyCorrectionDeltas(game, inverse);
    if (original.kind == CorrectionKind.answer) {
      final verdicts = {...game.round.answerVerdicts}
        ..remove(original.playerId);
      if (original.beforeValue != null) {
        verdicts[original.playerId] = original.beforeValue!;
      }
      updated = updated.copyWith(
        round: game.round.copyWith(answerVerdicts: verdicts),
      );
    } else if (original.kind == CorrectionKind.buzzer) {
      _graceTimer?.cancel();
      final completed = {...game.completedQuestionIds};
      if (!original.wasCompleted) completed.remove(original.questionId);
      updated = updated.copyWith(
        round: original.beforeRound!,
        jeopardy: original.beforeJeopardy,
        isFinished: original.beforeFinished,
        completedQuestionIds: completed,
        roundHistory: game.roundHistory
            .where(
              (r) =>
                  r.question?.id != original.questionId ||
                  r.startedAtHostMicros != original.roundStartedAt,
            )
            .toList(),
        poker: original.beforePoker?.copyWith(chips: updated.poker?.chips),
      );
    }
    emit(
      _publish(
        updated.copyWith(corrections: [...game.corrections, inverse]),
        notice: 'Korrektur als Gegenkorrektur zurückgenommen.',
      ),
    );
  }

  GameState _applyCorrectionDeltas(GameState game, ManualCorrection entry) {
    var scores = game.scores;
    for (final delta in entry.scoreDeltas.entries) {
      scores = scores.apply(
        playerId: delta.key,
        questionId: entry.questionId,
        delta: ScoreDelta(delta.value, reason: 'Manual correction'),
        atHostMicros: entry.atHostMicros,
      );
    }
    final poker = game.poker;
    return game.copyWith(
      scores: scores,
      poker: poker?.copyWith(
        chips: {
          ...poker.chips,
          for (final delta in entry.chipDeltas.entries)
            delta.key: poker.chips[delta.key]! + delta.value,
        },
      ),
    );
  }

  void _onBuzzerPress(BuzzerPressEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    final press = event.press;

    final rejection = _rejectSubmission(
      round,
      press.playerId,
      press.questionId,
    );
    if (rejection != null) {
      emit(state.copyWith(notice: rejection));
      return;
    }
    if (round.question is! BuzzerQuestion) {
      emit(state.copyWith(notice: 'This round has no buzzer.'));
      return;
    }
    if (round.lockedOutPlayerIds.contains(press.playerId)) {
      emit(state.copyWith(notice: 'Player is locked out for this round.'));
      return;
    }
    if (round.buzzerQueue.any((queued) => queued.playerId == press.playerId)) {
      return;
    }

    final wasEmpty = round.buzzerQueue.isEmpty;
    final queue = [...round.buzzerQueue, press]
      ..sort((a, b) => a.hostTimestampMicros.compareTo(b.hostTimestampMicros));

    emit(
      _publish(
        game.copyWith(
          tvMediaPaused: true,
          round: round.copyWith(
            buzzerQueue: queue,
            acceptedElapsedMicros: {
              ...round.acceptedElapsedMicros,
              press.playerId: round
                  .timerElapsedAt(press.hostTimestampMicros)
                  .inMicroseconds,
            },
          ),
        ),
        notice:
            '${game.players[press.playerId]?.name ?? press.playerId} buzzed.',
      ),
    );

    if (wasEmpty) _startGraceWindow();
  }

  void _onLockBuzzer(LockBuzzerEvent event, Emitter<QuizEngineState> emit) {
    _graceTimer?.cancel();
    final game = state.game;
    final round = game.round;
    if (round.status != RoundStatus.acceptingAnswers) return;

    final winner = round.nextCandidate;
    if (winner == null) return;

    emit(
      _publish(
        game.copyWith(
          round: round.copyWith(
            status: RoundStatus.locked,
            activePlayerId: winner.playerId,
            lockedOutPlayerIds: {
              ...round.lockedOutPlayerIds,
              ..._sharedBuzzerLockouts(game, winner.playerId),
            },
          ),
        ),
        notice:
            '${game.players[winner.playerId]?.name ?? winner.playerId} has the floor.',
      ),
    );
  }

  void _onJudgeBuzzer(JudgeBuzzerEvent event, Emitter<QuizEngineState> emit) {
    final before = state.game;
    var game = state.game;
    var round = game.round;
    final question = round.question;
    final activeId = round.activePlayerId;

    if (question is! BuzzerQuestion ||
        round.status != RoundStatus.locked ||
        activeId == null ||
        (event.playerId != null && event.playerId != activeId) ||
        (event.questionId != null && event.questionId != question.id) ||
        (event.startedAtHostMicros != null &&
            event.startedAtHostMicros != round.startedAtHostMicros) ||
        (event.resolvedAttempts != null &&
            event.resolvedAttempts != round.resolvedAttempts)) {
      emit(state.copyWith(notice: 'Nothing to judge right now.'));
      return;
    }

    QuizEngineState publishJudgment(GameState updated, {String? notice}) =>
        _publish(
          _recordJudgment(
            before,
            updated,
            activeId,
            CorrectionKind.buzzer,
            before.round.buzzerVerdicts[activeId],
            event.wasCorrect ? 1 : 0,
            event.reason,
          ),
          notice: notice,
        );

    round = round.copyWith(
      buzzerVerdicts: {
        ...round.buzzerVerdicts,
        activeId: event.wasCorrect ? 1 : 0,
      },
    );
    game = game.copyWith(round: round);
    final continueAutomatically =
        autoContinueBuzzer &&
        !question.hostEndsRound &&
        question.retryLimit == null;

    if (game.poker != null) {
      final teamId = game.players[activeId]!.teamId!;
      final settled = _settlePoker(game, teamId, event.wasCorrect);
      final locked = {
        ...round.lockedOutPlayerIds,
        ...game.players.values
            .where((p) => p.teamId == teamId)
            .map((p) => p.id),
      };
      final remaining = round.buzzerQueue
          .where((p) => !locked.contains(p.playerId))
          .toList();
      final updated = settled.copyWith(
        round: round.copyWith(
          status: continueAutomatically
              ? RoundStatus.acceptingAnswers
              : RoundStatus.locked,
          activePlayerId: null,
          buzzerQueue: continueAutomatically ? remaining : const [],
          lockedOutPlayerIds: locked,
          resolvedAttempts: round.resolvedAttempts + 1,
        ),
      );
      final done = _pokerEveryoneSettled(updated);
      emit(
        publishJudgment(
          done && !question.hostEndsRound && !round.hasSoftTimer
              ? _reveal(
                  updated.copyWith(
                    allAnswersRevision: game.allAnswersRevision + 1,
                  ),
                )
              : updated,
        ),
      );
      if (!done && continueAutomatically && remaining.isNotEmpty) {
        add(const LockBuzzerEvent());
      }
      return;
    }

    final rank = round.rankOf(activeId);
    final press = rank >= 0 ? round.buzzerQueue[rank] : null;
    final atHostMicros = press?.hostTimestampMicros ?? _now();

    final delta = _ruleFor(game, question).evaluate(
      ScoringContext(
        isCorrect: event.wasCorrect,
        elapsed: Duration(
          microseconds:
              round.acceptedElapsedMicros[activeId] ??
              round.elapsedAt(atHostMicros).inMicroseconds,
        ),
        timeLimit: question.timeLimit,
        rank: round.resolvedAttempts,
        attempt: round.resolvedAttempts + 1,
      ),
    );
    final scores = game.scores.apply(
      playerId: activeId,
      questionId: question.id,
      delta: delta,
      atHostMicros: atHostMicros,
    );
    final playerName = game.players[activeId]?.name ?? activeId;

    if (event.wasCorrect) {
      emit(
        publishJudgment(
          question.hostEndsRound || round.hasSoftTimer
              ? game.copyWith(
                  scores: scores,
                  round: round.copyWith(
                    activePlayerId: null,
                    buzzerQueue: const [],
                    resolvedAttempts: round.resolvedAttempts + 1,
                    buzzerAnswerCorrect: true,
                  ),
                )
              : _reveal(game.copyWith(scores: scores)),
          notice: '$playerName was right ($delta).',
        ),
      );
      return;
    }

    // Wrong answer on the board: the picking team's miss either hands the
    // question to the other teams or ends it.
    if (game.jeopardy case final jeopardy? when jeopardy.hasActiveQuestion) {
      if (!jeopardy.isStealRound && !round.buzzerOpenForAll) {
        final missed = game.copyWith(
          scores: scores,
          round: round.copyWith(
            activePlayerId: null,
            buzzerQueue: const [],
            resolvedAttempts: round.resolvedAttempts + 1,
            lockedOutPlayerIds: question.lockOutOnMiss
                ? {...round.lockedOutPlayerIds, activeId}
                : round.lockedOutPlayerIds,
          ),
        );
        if (_canOpenSteal(missed)) {
          final steal = _openStealRound(missed);
          emit(
            publishJudgment(
              continueAutomatically
                  ? steal
                  : steal.copyWith(
                      round: steal.round.copyWith(status: RoundStatus.locked),
                    ),
              notice: '$playerName missed ($delta). The other teams may steal.',
            ),
          );
        } else {
          emit(
            publishJudgment(
              continueAutomatically && !round.hasSoftTimer
                  ? _reveal(missed)
                  : missed,
              notice: '$playerName missed ($delta).',
            ),
          );
        }
        return;
      }
    }

    // Wrong answer: drop that press and offer the floor to the next in line.
    final remaining = round.buzzerQueue
        .where((queued) => queued.playerId != activeId)
        .toList(growable: false);
    final lockedOut = question.lockOutOnMiss
        ? {...round.lockedOutPlayerIds, activeId}
        : round.lockedOutPlayerIds;
    final next = RoundState(
      question: question,
      status: continueAutomatically
          ? RoundStatus.acceptingAnswers
          : RoundStatus.locked,
      startedAtHostMicros: round.startedAtHostMicros,
      buzzerQueue: continueAutomatically ? remaining : const [],
      answers: round.answers,
      lockedOutPlayerIds: lockedOut,
      resolvedAttempts: round.resolvedAttempts + 1,
      buzzerOpenForAll: round.buzzerOpenForAll,
      buzzerVerdicts: round.buzzerVerdicts,
    );

    emit(
      publishJudgment(
        game.copyWith(scores: scores, round: next),
        notice: continueAutomatically
            ? '$playerName missed ($delta). Buzzer is open again.'
            : '$playerName hat falsch geantwortet ($delta). Buzzer freigeben oder Runde beenden.',
      ),
    );

    if (continueAutomatically && remaining.isNotEmpty) {
      add(const LockBuzzerEvent());
    }
  }

  void _onRevealRound(RevealRoundEvent event, Emitter<QuizEngineState> emit) {
    _graceTimer?.cancel();
    final game = state.game;
    final question = game.round.question;
    if (question == null ||
        game.round.status == RoundStatus.revealed ||
        (game.poker?.betting ?? false)) {
      return;
    }
    if (_awaitManualGrades(game, emit)) return;

    // Points are resolved per question kind — polymorphism, not a type switch
    // on a string identifier.
    final scored = switch (question) {
      MultipleChoiceQuestion() ||
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => _scoreAnswers(game, question),
      BuzzerQuestion() => game,
    };

    // Nobody of the picking team got it right: the others may try.
    if (_canOpenSteal(scored)) {
      emit(
        _publish(
          _openStealRound(scored),
          notice: 'Nobody scored. The other teams may steal.',
        ),
      );
      return;
    }

    emit(_publish(_reveal(scored), notice: 'Round revealed.'));
  }

  void _onCloseRound(CloseRoundEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    if (game.round.status != RoundStatus.revealed) {
      emit(state.copyWith(notice: 'Reveal the round before closing it.'));
      return;
    }
    emit(
      _publish(
        game.copyWith(
          round: RoundState.idle,
          jeopardy: game.jeopardy?.copyWith(
            activePoints: null,
            activeIsDailyDouble: false,
            isStealRound: false,
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- jeopardy ---

  void _onSelectJeopardyCell(
    SelectJeopardyCellEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = event.playerId == null
        ? state.game.copyWith(isStarted: true)
        : state.game;
    final jeopardy = game.jeopardy;
    if (jeopardy == null) {
      emit(state.copyWith(notice: 'This session has no Jeopardy board.'));
      return;
    }
    if (event.playerId != null && !_mayPick(game, event.playerId!)) return;
    if (jeopardy.pendingDailyDoubleId != null ||
        jeopardy.pendingPickQuestionId != null) {
      return;
    }
    if (!state.canStartRound) {
      emit(state.copyWith(notice: 'Finish the current question first.'));
      return;
    }
    final id = event.questionId;
    final question = game.questionById(id);
    final points = jeopardy.board.pointsFor(id);
    if (question == null || points == null) {
      emit(state.copyWith(notice: 'That question is not on the board.'));
      return;
    }
    if (game.completedQuestionIds.contains(id)) {
      emit(state.copyWith(notice: 'That question was already played.'));
      return;
    }

    if (event.playerId != null) {
      emit(
        _publish(
          game.copyWith(
            jeopardy: jeopardy.copyWith(
              pendingPickQuestionId: id,
              pendingPickPlayerId: event.playerId,
            ),
          ),
        ),
      );
      return;
    }
    if (jeopardy.board.isDailyDouble(id)) {
      _graceTimer?.cancel();
      emit(
        _publish(
          game.copyWith(
            round: RoundState.idle,
            jeopardy: jeopardy.copyWith(
              pendingDailyDoubleId: id,
              activePoints: null,
              activeIsDailyDouble: false,
              isStealRound: false,
            ),
          ),
          notice: 'Daily Double! Place the wager.',
        ),
      );
      return;
    }

    _beginBoardRound(
      game,
      question,
      points: points,
      isDailyDouble: false,
      emit: emit,
    );
  }

  void _onConfirmQuestionPick(
    ConfirmQuestionPickEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final jeopardy = game.jeopardy;
    if (jeopardy == null ||
        jeopardy.pendingPickQuestionId != event.questionId ||
        jeopardy.pendingPickPlayerId != event.playerId) {
      return;
    }
    final mayPick = game.mayPickQuestion(event.playerId);
    emit(
      _publish(
        game.copyWith(
          jeopardy: jeopardy.copyWith(
            pendingPickQuestionId: null,
            pendingPickPlayerId: null,
          ),
        ),
      ),
    );
    if (event.accepted && mayPick) {
      _onSelectJeopardyCell(SelectJeopardyCellEvent(event.questionId), emit);
    }
  }

  void _onPlaceDailyDoubleWager(
    PlaceDailyDoubleWagerEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final jeopardy = game.jeopardy;
    final pendingId = jeopardy?.pendingDailyDoubleId;
    final question = pendingId == null ? null : game.questionById(pendingId);
    if (jeopardy == null || question == null) {
      emit(state.copyWith(notice: 'No Daily Double is waiting for a wager.'));
      return;
    }

    if (event.playerId != null &&
        (!_mayPick(game, event.playerId!) || event.questionId != pendingId)) {
      return;
    }
    final maxWager = maxDailyDoubleWager(game);
    if (event.wager < 1 || event.wager > maxWager) {
      emit(
        state.copyWith(notice: 'The wager must be between 1 and $maxWager.'),
      );
      return;
    }

    _beginBoardRound(
      game,
      question,
      points: event.wager,
      isDailyDouble: true,
      emit: emit,
    );
  }

  void _onSetJeopardyTurn(
    SetJeopardyTurnEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final jeopardy = game.jeopardy;
    if (jeopardy == null) {
      emit(state.copyWith(notice: 'This session has no Jeopardy board.'));
      return;
    }
    if (jeopardy.pendingDailyDoubleId != null ||
        jeopardy.pendingPickQuestionId != null) {
      return;
    }
    if (!game.participantIds.contains(event.teamId)) {
      emit(state.copyWith(notice: 'Unknown team.'));
      return;
    }
    if (!state.canStartRound) {
      emit(state.copyWith(notice: 'The turn cannot change during a question.'));
      return;
    }
    emit(
      _publish(
        game.copyWith(jeopardy: jeopardy.copyWith(currentTeamId: event.teamId)),
        notice: '${game.participantName(event.teamId)} picks next.',
      ),
    );
  }

  bool _mayPick(GameState game, String playerId) {
    return game.mayPickQuestion(playerId);
  }

  /// The highest wager the picking team may place on a Daily Double.
  ///
  /// Classic rule: the team's own score, but never less than the most
  /// valuable row so that a team in the red can still take part.
  int maxDailyDoubleWager(GameState game) {
    final jeopardy = game.jeopardy;
    if (jeopardy == null) return 0;
    final teamScore = game.mode is TeamMode
        ? game.teamScores[jeopardy.currentTeamId] ?? 0
        : game.scores.byPlayer[jeopardy.currentTeamId] ?? 0;
    final highest = jeopardy.board.highestRowPoints;
    return teamScore > highest ? teamScore : highest;
  }

  void _beginBoardRound(
    GameState game,
    Question question, {
    required int points,
    required bool isDailyDouble,
    required Emitter<QuizEngineState> emit,
  }) {
    _graceTimer?.cancel();
    final jeopardy = game.jeopardy!;
    emit(
      _publish(
        game.copyWith(
          poker: game.poker?.copyWith(
            wagers: const {},
            settledTeamIds: const {},
            betting: true,
          ),
          round: RoundState(
            question: question,
            status: RoundStatus.acceptingAnswers,
            startedAtHostMicros: _now(),
          ),
          jeopardy: jeopardy.copyWith(
            pendingDailyDoubleId: null,
            activePoints: points,
            activeIsDailyDouble: isDailyDouble,
            isStealRound: false,
          ),
        ),
        notice: 'Round started: ${question.prompt}',
      ),
    );
  }

  /// Whether the picking team failed and the board lets the others try.
  bool _canOpenSteal(GameState game) {
    final jeopardy = game.jeopardy;
    final question = game.round.question;
    if (jeopardy == null || question == null) return false;
    if (game.round.buzzerAnswerCorrect) return false;
    if (game.round.buzzerOpenForAll) return false;
    if (!jeopardy.hasActiveQuestion || jeopardy.isStealRound) return false;
    if (!jeopardy.canSteal || jeopardy.currentTeamId == null) return false;
    if (game.participantIds.length < 2) return false;
    return !game.scores.history.any(
      (event) => event.questionId == question.id && event.points > 0,
    );
  }

  /// Restarts the question on stage for the teams other than the picker.
  GameState _openStealRound(GameState game) {
    _graceTimer?.cancel();
    return game.copyWith(
      round: RoundState(
        question: game.round.question,
        resolvedAttempts: game.round.resolvedAttempts,
        lockedOutPlayerIds: game.round.lockedOutPlayerIds,
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: _now(),
      ),
      jeopardy: game.jeopardy!.copyWith(isStealRound: true),
    );
  }

  /// The rule that scores [question] in [game].
  ///
  /// On a board the points come from the row (or the wager) instead of the
  /// rule stored on the question, which keeps every question kind usable on
  /// every row.
  ScoringRule _ruleFor(GameState game, Question question) {
    final jeopardy = game.jeopardy;
    final points = jeopardy?.activePoints;
    if (jeopardy == null || points == null) return question.scoringRule;
    final risksPoints =
        jeopardy.activeIsDailyDouble || jeopardy.board.penalizeWrongAnswers;
    return FixedPointsRule(
      correctPoints: points,
      wrongPoints: risksPoints ? -points : 0,
    );
  }

  /// Whether the team of [playerId] already gave an answer this round.
  ///
  /// On a board only one answer per team counts, otherwise a big team would
  /// earn the row points once per member.
  bool _teamAlreadyAnswered(GameState game, String playerId) {
    if (game.mode is! TeamMode ||
        (game.jeopardy == null && game.poker == null)) {
      return false;
    }
    final teamId = game.players[playerId]?.teamId;
    if (teamId == null) return false;
    return game.round.answers.keys.any(
      (answeredId) => game.players[answeredId]?.teamId == teamId,
    );
  }

  /// Whether every player (on a board: every team) that may answer did.
  bool _everyoneAnswered(GameState game) {
    if (game.poker case final poker?) {
      final teams = game.teams.keys.where(
        (id) => (poker.wagers[id] ?? 0) > 0 || (poker.chips[id] ?? 0) == 0,
      );
      return teams.isNotEmpty &&
          teams.every(
            (team) => game.round.answers.keys.any(
              (id) => game.players[id]?.teamId == team,
            ),
          );
    }
    final jeopardy = game.jeopardy;
    final eligible = game.connectedPlayers
        .where(
          (player) =>
              (jeopardy?.mayAnswer(game.participantId(player)) ?? true) &&
              (game.poker == null ||
                  (game.poker!.wagers[player.teamId] ?? 0) > 0),
        )
        .toList(growable: false);
    if (eligible.isEmpty) return false;
    return eligible.every((player) {
      if (game.mode is TeamMode &&
          (jeopardy != null || game.poker != null) &&
          player.teamId != null) {
        return game.round.answers.keys.any(
          (id) => game.players[id]?.teamId == player.teamId,
        );
      }
      return game.round.answers.containsKey(player.id);
    });
  }

  /// The team that picks after [currentId], following the roster order.
  String? _nextTeamId(GameState game, String? currentId) {
    final ids = game.selectionOrder;
    if (ids.isEmpty) return null;
    final index = currentId == null ? -1 : ids.indexOf(currentId);
    return ids[(index + 1) % ids.length];
  }

  void _onResetGame(ResetGameEvent event, Emitter<QuizEngineState> emit) {
    _graceTimer?.cancel();
    final game = state.game;
    final teams = game.teams;
    final board = _initialBoard;
    emit(
      _publish(
        GameState(
          mode: game.mode,
          revealMode: game.revealMode,
          poker: game.poker == null
              ? null
              : PokerState.start(game.poker!.startingChips, teams.keys),
          players: game.players,
          playerOrder: game.playerOrder,
          teams: teams,
          questionBank: _initialBank.isEmpty ? game.questionBank : _initialBank,
          totalQuestionCount: _initialBank.isEmpty
              ? game.questionBank.length
              : _initialBank.length,
          jeopardy: board == null
              ? null
              : JeopardyState.start(board, teams.keys).copyWith(
                  turnOrder: game.jeopardy?.turnOrder,
                  currentTeamId: game.selectionOrder.firstOrNull,
                ),
          scores: ScoreState(
            byPlayer: {for (final id in game.players.keys) id: 0},
          ),
        ),
        notice: 'Game reset.',
      ),
    );
  }

  // --------------------------------------------------------------- helpers ---

  /// Wraps [game] into a state, stamping it with the current host clock.
  QuizEngineState _publish(GameState game, {String? notice}) {
    _roundTimer?.cancel();
    final round = game.round;
    final question = round.question;
    final start = round.startedAtHostMicros;
    if (question != null &&
        start != null &&
        !game.recoveryPaused &&
        !round.hasSoftTimer &&
        round.status.acceptsInput &&
        !(game.poker?.betting ?? false)) {
      final remaining =
          round.timerStartedAtHostMicros! +
          question.timeLimit.inMicroseconds -
          _now();
      _roundTimer = _createTimer(
        Duration(microseconds: remaining < 0 ? 0 : remaining),
        () {
          if (!isClosed) add(ExpireRoundEvent(question.id, start));
        },
      );
    }
    return QuizEngineState(
      game: game.copyWith(
        hostTimeMicros: game.recoveryPaused ? game.hostTimeMicros : _now(),
        tvMediaPaused:
            game.round.question?.id != state.game.round.question?.id ||
                (game.round.status == RoundStatus.revealed &&
                    state.game.round.status != RoundStatus.revealed)
            ? false
            : game.tvMediaPaused,
      ),
      notice: notice,
    );
  }

  /// Marks the round revealed and files the question as played.
  ///
  /// A question played from the board also passes the pick on to the next team.
  GameState _reveal(GameState game) {
    if (game.poker case final poker?) {
      for (final teamId in poker.wagers.keys) {
        game = _settlePoker(game, teamId, false);
      }
      game = game.copyWith(poker: game.poker!.copyWith(betting: false));
    }
    final question = game.round.question;
    final jeopardy = game.jeopardy;
    return game.copyWith(
      isFinished:
          game.questionBank.isNotEmpty &&
          (game.jeopardy?.board.questionIds ??
                  game.questionBank.map((q) => q.id))
              .every(
                (id) =>
                    game.completedQuestionIds.contains(id) ||
                    id == question?.id,
              ),
      round: game.round.copyWith(status: RoundStatus.revealed),
      roundHistory: game.revealMode == SolutionRevealMode.atEnd
          ? [
              ...game.roundHistory,
              game.round.copyWith(status: RoundStatus.revealed),
            ]
          : game.roundHistory,
      completedQuestionIds: question == null
          ? game.completedQuestionIds
          : {...game.completedQuestionIds, question.id},
      jeopardy: jeopardy == null || !jeopardy.hasActiveQuestion
          ? jeopardy
          : jeopardy.copyWith(
              currentTeamId: _nextTeamId(game, jeopardy.currentTeamId),
              isStealRound: false,
            ),
    );
  }

  /// Returns why a submission is inadmissible, or `null` when it is accepted.
  String? _rejectSubmission(
    RoundState round,
    String playerId,
    String questionId,
  ) {
    if (!round.status.acceptsInput) return 'Round is not accepting input.';
    final question = round.question;
    if (question == null) return 'No question on stage.';
    if (question.id != questionId) return 'Submission targets a stale round.';
    if (!round.hasSoftTimer &&
        !(state.game.poker?.betting ?? false) &&
        round.timerElapsedAt(_now()) >= question.timeLimit) {
      return 'Zeit abgelaufen. Antworten sind geschlossen.';
    }
    if (state.game.players[playerId]?.isConnected != true) {
      return 'Unknown or disconnected player.';
    }
    if (state.game.poker case final poker?) {
      final teamId = state.game.players[playerId]?.teamId;
      if (poker.betting) return 'Die Einsatzphase läuft noch.';
      if (teamId == null ||
          ((poker.wagers[teamId] ?? 0) < 1 && (poker.chips[teamId] ?? 0) > 0)) {
        return 'Dein Team hat keinen Einsatz.';
      }
      if (poker.settledTeamIds.contains(teamId)) {
        return 'Dein Team wurde bereits gewertet.';
      }
    }
    if (state.game.jeopardy case final jeopardy?) {
      final participant = state.game.participantId(
        state.game.players[playerId],
      );
      if (!round.buzzerOpenForAll && !jeopardy.mayAnswer(participant)) {
        return jeopardy.isStealRound
            ? 'Only the other teams may steal this question.'
            : 'The picking team answers first.';
      }
    }
    return null;
  }

  /// Team mates that are locked out because the mode uses one shared buzzer.
  Set<String> _sharedBuzzerLockouts(GameState game, String winnerId) {
    switch (game.mode) {
      case TeamMode(sharedBuzzer: true):
        final teamId = game.players[winnerId]?.teamId;
        if (teamId == null) return const <String>{};
        return game.players.values
            .where((player) => player.teamId == teamId && player.id != winnerId)
            .map((player) => player.id)
            .toSet();
      case TeamMode():
      case SoloMode():
        return const <String>{};
    }
  }

  /// Books the points of every multiple choice submission of the round.
  GameState _scoreAnswers(GameState game, Question question) {
    final round = game.round;
    if (game.poker != null) {
      var result = game;
      for (final answer in round.answers.values) {
        result = _settlePoker(
          result,
          game.players[answer.playerId]!.teamId!,
          round.accuracyFor(answer) == 1,
        );
      }
      return result;
    }
    final submissions = round.answers.values.toList(growable: false)
      ..sort((a, b) => a.hostTimestampMicros.compareTo(b.hostTimestampMicros));

    var scores = game.scores;
    var correctRank = 0;
    final rule = _ruleFor(game, question);
    for (var index = 0; index < submissions.length; index++) {
      final answer = submissions[index];
      final accuracy =
          round.accuracyFor(answer) ??
          (throw StateError('Cannot score an ungraded answer.'));
      final isCorrect = accuracy > 0;
      final delta = evaluateAccuracy(
        rule,
        ScoringContext(
          isCorrect: isCorrect,
          elapsed: Duration(
            microseconds:
                round.acceptedElapsedMicros[answer.playerId] ??
                round.elapsedAt(answer.hostTimestampMicros).inMicroseconds,
          ),
          timeLimit: question.timeLimit,
          rank: isCorrect ? correctRank : index,
        ),
        accuracy,
      );
      if (isCorrect) correctRank++;
      scores = scores.apply(
        playerId: answer.playerId,
        questionId: question.id,
        delta: delta,
        atHostMicros: answer.hostTimestampMicros,
      );
    }
    return game.copyWith(scores: scores);
  }

  void _onPlacePokerWager(
    PlacePokerWagerEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final poker = game.poker;
    final teamId = game.players[event.playerId]?.teamId;
    if (poker == null ||
        !poker.betting ||
        teamId == null ||
        !game.teams.containsKey(teamId) ||
        game.round.question?.id != event.questionId ||
        event.wager < 0 ||
        event.wager >
            (poker.chips[teamId] ?? 0) + (poker.wagers[teamId] ?? 0)) {
      return;
    }
    emit(
      _publish(
        game.copyWith(
          poker: poker.copyWith(
            chips: {
              ...poker.chips,
              teamId:
                  poker.chips[teamId]! +
                  (poker.wagers[teamId] ?? 0) -
                  event.wager,
            },
            wagers: {...poker.wagers, teamId: event.wager},
          ),
        ),
      ),
    );
  }

  void _onOpenPokerAnswers(
    OpenPokerAnswersEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final poker = game.poker;
    if (poker == null || !poker.betting || game.round.question == null) return;
    emit(
      _publish(
        game.copyWith(
          poker: poker.copyWith(betting: false),
          round: game.round.copyWith(
            startedAtHostMicros: _now(),
            timerRestartedAtHostMicros: null,
          ),
        ),
        notice: 'Einsätze geschlossen. Antworten sind jetzt offen.',
      ),
    );
  }

  GameState _settlePoker(GameState game, String teamId, bool correct) {
    final poker = game.poker!;
    if (poker.settledTeamIds.contains(teamId)) return game;
    final payout = pokerChipPayout(
      wager: poker.wagers[teamId] ?? 0,
      isCorrect: correct,
    );
    return game.copyWith(
      poker: poker.copyWith(
        chips: {...poker.chips, teamId: (poker.chips[teamId] ?? 0) + payout},
        settledTeamIds: {...poker.settledTeamIds, teamId},
      ),
    );
  }

  bool _pokerEveryoneSettled(GameState game) => game.teams.keys
      .where(
        (id) =>
            (game.poker!.wagers[id] ?? 0) > 0 ||
            (game.poker!.chips[id] ?? 0) == 0,
      )
      .every((id) => game.poker!.settledTeamIds.contains(id));

  void _startGraceWindow() {
    _graceTimer?.cancel();
    _graceTimer = _createTimer(buzzerGraceWindow, () {
      if (!isClosed) add(const LockBuzzerEvent());
    });
  }
}
