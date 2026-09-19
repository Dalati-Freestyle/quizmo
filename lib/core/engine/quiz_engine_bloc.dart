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
class QuizEngineBloc extends Bloc<QuizEngineEvent, QuizEngineState> {
  /// Creates an engine seeded with [questionBank], [teams] and [mode].
  QuizEngineBloc({
    List<Question> questionBank = const [],
    Map<String, Team> teams = const {},
    GameMode mode = const SoloMode(),
    this.buzzerGraceWindow = const Duration(milliseconds: 350),
    NowMicros now = systemNowMicros,
  }) : _now = now,
       _initialBank = questionBank,
       _initialTeams = teams,
       super(
         QuizEngineState(
           game: GameState(
             questionBank: questionBank,
             teams: teams,
             mode: mode,
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
    on<ResetGameEvent>(_onResetGame);
  }

  /// How long the engine waits for in-flight presses before locking the buzzer.
  final Duration buzzerGraceWindow;

  final NowMicros _now;
  final List<Question> _initialBank;
  final Map<String, Team> _initialTeams;
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

  void _onNextQuestion(
    NextQuestionEvent event,
    Emitter<QuizEngineState> emit,
  ) {
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

    final rejection = _rejectSubmission(round, answer.playerId, answer.questionId);
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

    final updated = game.copyWith(
      round: round.copyWith(
        answers: {...round.answers, answer.playerId: answer},
      ),
    );

    // Everybody answered — no reason to keep the room waiting.
    final everyoneAnswered = updated.connectedPlayers.isNotEmpty &&
        updated.connectedPlayers.every(
          (player) => updated.round.answers.containsKey(player.id),
        );

    emit(_publish(updated));
    if (everyoneAnswered) add(const RevealRoundEvent());
  }

  void _onBuzzerPress(BuzzerPressEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    final press = event.press;

    final rejection = _rejectSubmission(round, press.playerId, press.questionId);
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
      ..sort(
        (a, b) => a.hostTimestampMicros.compareTo(b.hostTimestampMicros),
      );

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

    final delta = question.scoringRule.evaluate(
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

    emit(_publish(_reveal(scored), notice: 'Round revealed.'));
  }

  void _onResetGame(ResetGameEvent event, Emitter<QuizEngineState> emit) {
    _graceTimer?.cancel();
    final game = state.game;
    emit(
      _publish(
        GameState(
          mode: game.mode,
          players: game.players,
          teams: _initialTeams.isEmpty ? game.teams : _initialTeams,
          questionBank: _initialBank.isEmpty ? game.questionBank : _initialBank,
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
  GameState _reveal(GameState game) {
    final question = game.round.question;
    return game.copyWith(
      round: game.round.copyWith(status: RoundStatus.revealed),
      completedQuestionIds: question == null
          ? game.completedQuestionIds
          : {...game.completedQuestionIds, question.id},
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
    for (var index = 0; index < submissions.length; index++) {
      final answer = submissions[index];
      final isCorrect = question.isCorrect(answer.optionId);
      final delta = question.scoringRule.evaluate(
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



