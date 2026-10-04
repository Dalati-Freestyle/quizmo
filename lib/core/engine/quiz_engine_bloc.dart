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
    this.buzzerGraceWindow = const Duration(milliseconds: 350),
    NowMicros now = systemNowMicros,
  }) : _now = now,
       _initialBank = questionBank,
       _initialTeams = teams,
       _initialBoard = jeopardyBoard,
       super(
         QuizEngineState(
           game: GameState(
             questionBank: questionBank,
             teams: teams,
             mode: mode,
             jeopardy: jeopardyBoard == null
                 ? null
                 : JeopardyState.start(jeopardyBoard, teams.keys),
             hostTimeMicros: now(),
           ),
         ),
       ) {
    on<PlayerJoinedEvent>(_onPlayerJoined);
    on<PlayerLeftEvent>(_onPlayerLeft);
    on<TimeSyncEvent>(_onTimeSync);
    on<AssignTeamEvent>(_onAssignTeam);
    on<ChangeGameModeEvent>(_onChangeGameMode);
    on<StartRoundEvent>(_onStartRound);
    on<NextQuestionEvent>(_onNextQuestion);
    on<SubmitAnswerEvent>(_onSubmitAnswer);
    on<BuzzerPressEvent>(_onBuzzerPress);
    on<LockBuzzerEvent>(_onLockBuzzer);
    on<JudgeBuzzerEvent>(_onJudgeBuzzer);
    on<RevealRoundEvent>(_onRevealRound);
    on<CloseRoundEvent>(_onCloseRound);
    on<SelectJeopardyCellEvent>(_onSelectJeopardyCell);
    on<PlaceDailyDoubleWagerEvent>(_onPlaceDailyDoubleWager);
    on<SetJeopardyTurnEvent>(_onSetJeopardyTurn);
    on<ResetGameEvent>(_onResetGame);
  }

  /// How long the engine waits for in-flight presses before locking the buzzer.
  final Duration buzzerGraceWindow;

  final NowMicros _now;
  final List<Question> _initialBank;
  final Map<String, Team> _initialTeams;
  final JeopardyBoard? _initialBoard;
  Timer? _graceTimer;

  /// The host clock, exposed so the UI can render latency relative to it.
  int get hostNowMicros => _now();

  @override
  Future<void> close() {
    _graceTimer?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------- lobby ---

  void _onPlayerJoined(PlayerJoinedEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final existing = game.players[event.player.id];
    final player = existing == null
        ? event.player
        : existing.copyWith(
            name: event.player.name,
            teamId: event.player.teamId,
            isConnected: true,
            clockOffsetMicros: event.player.clockOffsetMicros,
            roundTripMicros: event.player.roundTripMicros,
          );

    emit(
      _publish(
        game.copyWith(
          players: {...game.players, player.id: player},
          scores: game.scores.withParticipant(player.id),
        ),
        notice: '${player.name} joined.',
      ),
    );
  }

  void _onPlayerLeft(PlayerLeftEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final player = game.players[event.playerId];
    if (player == null) return;

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
    emit(
      _publish(
        state.game.copyWith(mode: event.mode),
        notice: 'Mode switched to ${event.mode.label}.',
      ),
    );
  }

  // ---------------------------------------------------------------- round ---

  void _onStartRound(StartRoundEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    if (game.jeopardy != null) {
      // On a board every round starts by picking a cell, so that the points,
      // the turn rotation and the answer restrictions cannot be bypassed.
      _onSelectJeopardyCell(SelectJeopardyCellEvent(event.questionId), emit);
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
    if (round.question is! MultipleChoiceQuestion) {
      emit(state.copyWith(notice: 'This round does not take choices.'));
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

    final updated = game.copyWith(
      round: round.copyWith(
        answers: {...round.answers, answer.playerId: answer},
      ),
    );

    emit(_publish(updated));
    // Everybody answered — no reason to keep the room waiting.
    if (_everyoneAnswered(updated)) add(const RevealRoundEvent());
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
        game.copyWith(round: round.copyWith(buzzerQueue: queue)),
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
    final game = state.game;
    final round = game.round;
    final question = round.question;
    final activeId = round.activePlayerId;

    if (question is! BuzzerQuestion ||
        round.status != RoundStatus.locked ||
        activeId == null) {
      emit(state.copyWith(notice: 'Nothing to judge right now.'));
      return;
    }

    final rank = round.rankOf(activeId);
    final press = rank >= 0 ? round.buzzerQueue[rank] : null;
    final atHostMicros = press?.hostTimestampMicros ?? _now();

    final delta = _ruleFor(game, question).evaluate(
      ScoringContext(
        isCorrect: event.wasCorrect,
        elapsed: round.elapsedAt(atHostMicros),
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
        _publish(
          _reveal(game.copyWith(scores: scores)),
          notice: '$playerName was right ($delta).',
        ),
      );
      return;
    }

    // Wrong answer on the board: the picking team's miss either hands the
    // question to the other teams or ends it.
    if (game.jeopardy case final jeopardy? when jeopardy.hasActiveQuestion) {
      if (!jeopardy.isStealRound) {
        final missed = game.copyWith(scores: scores);
        if (_canOpenSteal(missed)) {
          emit(
            _publish(
              _openStealRound(missed),
              notice: '$playerName missed ($delta). The other teams may steal.',
            ),
          );
        } else {
          emit(
            _publish(_reveal(missed), notice: '$playerName missed ($delta).'),
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
      status: RoundStatus.acceptingAnswers,
      startedAtHostMicros: round.startedAtHostMicros,
      buzzerQueue: remaining,
      answers: round.answers,
      lockedOutPlayerIds: lockedOut,
      resolvedAttempts: round.resolvedAttempts + 1,
    );

    emit(
      _publish(
        game.copyWith(scores: scores, round: next),
        notice: '$playerName missed ($delta). Buzzer is open again.',
      ),
    );

    if (remaining.isNotEmpty) add(const LockBuzzerEvent());
  }

  void _onRevealRound(RevealRoundEvent event, Emitter<QuizEngineState> emit) {
    _graceTimer?.cancel();
    final game = state.game;
    final question = game.round.question;
    if (question == null || game.round.status == RoundStatus.revealed) return;

    // Points are resolved per question kind — polymorphism, not a type switch
    // on a string identifier.
    final scored = switch (question) {
      MultipleChoiceQuestion() => _scoreMultipleChoice(game, question),
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
    final game = state.game;
    final jeopardy = game.jeopardy;
    if (jeopardy == null) {
      emit(state.copyWith(notice: 'This session has no Jeopardy board.'));
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
    if (!game.teams.containsKey(event.teamId)) {
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
        notice: '${game.teams[event.teamId]!.name} picks next.',
      ),
    );
  }

  /// The highest wager the picking team may place on a Daily Double.
  ///
  /// Classic rule: the team's own score, but never less than the most
  /// valuable row so that a team in the red can still take part.
  int maxDailyDoubleWager(GameState game) {
    final jeopardy = game.jeopardy;
    if (jeopardy == null) return 0;
    final teamScore = game.teamScores[jeopardy.currentTeamId] ?? 0;
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
    if (!jeopardy.hasActiveQuestion || jeopardy.isStealRound) return false;
    if (!jeopardy.canSteal || jeopardy.currentTeamId == null) return false;
    if (game.teams.length < 2) return false;
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
    if (game.jeopardy == null) return false;
    final teamId = game.players[playerId]?.teamId;
    if (teamId == null) return false;
    return game.round.answers.keys.any(
      (answeredId) => game.players[answeredId]?.teamId == teamId,
    );
  }

  /// Whether every player (on a board: every team) that may answer did.
  bool _everyoneAnswered(GameState game) {
    final jeopardy = game.jeopardy;
    final eligible = game.connectedPlayers
        .where((player) => jeopardy?.mayAnswer(player.teamId) ?? true)
        .toList(growable: false);
    if (eligible.isEmpty) return false;
    return eligible.every((player) {
      if (jeopardy != null && player.teamId != null) {
        return game.round.answers.keys.any(
          (id) => game.players[id]?.teamId == player.teamId,
        );
      }
      return game.round.answers.containsKey(player.id);
    });
  }

  /// The team that picks after [currentId], following the roster order.
  String? _nextTeamId(GameState game, String? currentId) {
    final ids = game.teams.keys.toList(growable: false);
    if (ids.isEmpty) return null;
    final index = currentId == null ? -1 : ids.indexOf(currentId);
    return ids[(index + 1) % ids.length];
  }

  void _onResetGame(ResetGameEvent event, Emitter<QuizEngineState> emit) {
    _graceTimer?.cancel();
    final game = state.game;
    final teams = _initialTeams.isEmpty ? game.teams : _initialTeams;
    final board = _initialBoard;
    emit(
      _publish(
        GameState(
          mode: game.mode,
          players: game.players,
          teams: teams,
          questionBank: _initialBank.isEmpty ? game.questionBank : _initialBank,
          jeopardy: board == null
              ? null
              : JeopardyState.start(board, teams.keys),
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
  QuizEngineState _publish(GameState game, {String? notice}) => QuizEngineState(
    game: game.copyWith(hostTimeMicros: _now()),
    notice: notice,
  );

  /// Marks the round revealed and files the question as played.
  ///
  /// A question played from the board also passes the pick on to the next team.
  GameState _reveal(GameState game) {
    final question = game.round.question;
    final jeopardy = game.jeopardy;
    return game.copyWith(
      round: game.round.copyWith(status: RoundStatus.revealed),
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
    if (!state.game.players.containsKey(playerId)) return 'Unknown player.';
    if (state.game.jeopardy case final jeopardy?) {
      final teamId = state.game.players[playerId]?.teamId;
      if (!jeopardy.mayAnswer(teamId)) {
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
  GameState _scoreMultipleChoice(
    GameState game,
    MultipleChoiceQuestion question,
  ) {
    final round = game.round;
    final submissions = round.answers.values.toList(growable: false)
      ..sort((a, b) => a.hostTimestampMicros.compareTo(b.hostTimestampMicros));

    var scores = game.scores;
    var correctRank = 0;
    final rule = _ruleFor(game, question);
    for (var index = 0; index < submissions.length; index++) {
      final answer = submissions[index];
      final isCorrect = question.isCorrect(answer.optionId);
      final delta = rule.evaluate(
        ScoringContext(
          isCorrect: isCorrect,
          elapsed: round.elapsedAt(answer.hostTimestampMicros),
          timeLimit: question.timeLimit,
          rank: isCorrect ? correctRank : index,
        ),
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

  void _startGraceWindow() {
    _graceTimer?.cancel();
    _graceTimer = Timer(buzzerGraceWindow, () {
      if (!isClosed) add(const LockBuzzerEvent());
    });
  }
}
