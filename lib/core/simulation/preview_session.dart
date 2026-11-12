import 'dart:async';
import 'dart:math';

import '../engine/quiz_engine_bloc.dart';
import '../models/models.dart';
import 'bot_decisions.dart';
import 'simulation_clock.dart';

final class PreviewParticipant {
  const PreviewParticipant({required this.player, this.bot});
  final Player player;
  final BotSettings? bot;
}

final class PreviewSession {
  PreviewSession(Quiz draft, {int seed = 1}) : this._(draft, seed, null);

  PreviewSession._(Quiz draft, this.seed, GameState? restored)
    : quiz = Quiz.fromJson(draft.toJson()),
      _random = Random(seed) {
    engine = QuizEngineBloc(
      questionBank: quiz.questions,
      teams: quiz.teamsById,
      mode: quiz.teams.isEmpty ? const SoloMode() : const TeamMode(),
      autoContinueBuzzer: false,
      revealMode: switch (quiz.format) {
        StandardFormat(:final revealMode) => revealMode,
        JeopardyFormat() ||
        PokerFormat() => SolutionRevealMode.afterEachQuestion,
      },
      jeopardyBoard: switch (quiz.format) {
        JeopardyFormat(:final board) => board,
        StandardFormat() || PokerFormat() => null,
      },
      pokerStartingChips: switch (quiz.format) {
        PokerFormat(:final startingChips) => startingChips,
        StandardFormat() || JeopardyFormat() => null,
      },
      now: () => clock.nowMicros,
      createTimer: clock.schedule,
      restoredGame: restored,
    );
    _subscription = engine.stream.listen((state) {
      _plan(state.game);
    });
    if (restored != null) {
      engine.add(const ResumeRecoveredGameEvent(RecoveryTimerPolicy.restart));
    }
  }

  final Quiz quiz;
  final int seed;
  final SimulationClock clock = SimulationClock();
  late final QuizEngineBloc engine;
  late final StreamSubscription<QuizEngineState> _subscription;
  final Map<String, PreviewParticipant> _participants = {};
  final Map<String, Timer> _pending = {};
  final Set<String> _performed = {};
  final List<({int atMicros, String action})> trace = [];
  final Random _random;
  int _nextId = 0;
  bool _closed = false;
  bool _botsEnabled = true;
  Future<void> _work = Future.value();
  String? _roundKey;
  GameState? _roundStart;
  Map<String, PreviewParticipant> _roundParticipants = {};
  String? _pendingPick;
  GameState? _guestSource;
  GameState? _guestSnapshot;

  List<PreviewParticipant> get participants =>
      List.unmodifiable(_participants.values);
  bool get botsEnabled => _botsEnabled;
  bool get isClosed => _closed;
  bool get canReplayRound => _roundStart != null;

  PreviewSession replayRound() {
    final baseline = _roundStart;
    if (baseline == null) throw StateError('No round to replay.');
    final replay = PreviewSession._(
      quiz,
      seed,
      baseline.copyWith(recoveryPaused: true),
    );
    replay._participants.addAll(_roundParticipants);
    replay._nextId = _nextId;
    replay._botsEnabled = _botsEnabled;
    return replay;
  }

  GameState _redact(GameState source) {
    if (!identical(source, _guestSource)) {
      _guestSnapshot = source.redactedForPlayers(includeMediaData: true);
      _guestSource = source;
    }
    return _guestSnapshot!;
  }

  GameState get guestGame => _redact(engine.state.game);
  Stream<GameState> get guestSnapshots =>
      engine.stream.map((state) => _redact(state.game));

  String addParticipant({
    required String name,
    BotSettings? bot,
    String? teamId,
    bool ownTeam = false,
  }) {
    if (_closed) throw StateError('Preview is closed.');
    if (name.trim().isEmpty || name.trim().length > 60) {
      throw ArgumentError.value(name, 'name');
    }
    final game = engine.state.game;
    var id = 'preview-${_nextId++}';
    while (game.teams.containsKey('$id-team')) {
      id = 'preview-${_nextId++}';
    }
    if (teamId != null && !game.teams.containsKey(teamId)) {
      throw ArgumentError.value(teamId, 'teamId');
    }
    final requiresTeam = game.mode is TeamMode || game.poker != null;
    final createTeam = ownTeam || (requiresTeam && teamId == null);
    final team = createTeam ? Team(id: '$id-team', name: name.trim()) : null;
    final player = Player(
      id: id,
      name: name.trim(),
      teamId: team?.id ?? teamId,
      roundTripMicros: 1,
    );
    _participants[id] = PreviewParticipant(player: player, bot: bot);
    if (ownTeam && game.mode is SoloMode) {
      send(const ChangeGameModeEvent(TeamMode()));
    }
    send(PlayerJoinedEvent(player, createdTeam: team));
    return id;
  }

  void removeParticipant(String id) {
    if (_participants.remove(id) == null) return;
    _cancelBotActions();
    send(KickPlayerEvent(id));
  }

  void setBotsEnabled(bool enabled) {
    _botsEnabled = enabled;
    if (!enabled) {
      _cancelBotActions();
    } else {
      _plan(engine.state.game);
    }
  }

  void send(QuizEngineEvent event) {
    if (_closed) throw StateError('Preview is closed.');
    engine.add(event);
  }

  Future<void> advance(Duration duration) {
    if (_closed) return Future.value();
    _work = _work.then((_) async {
      if (!_closed) await clock.advance(duration);
    });
    return _work;
  }

  Future<void> flush() => advance(Duration.zero);

  bool _maySubmit(GameState game, String id) {
    final round = game.round;
    if (!round.status.acceptsInput ||
        game.players[id]?.isConnected != true ||
        !game.mayAnswerQuestion(id) ||
        round.answers.containsKey(id) ||
        round.lockedOutPlayerIds.contains(id) ||
        round.buzzerQueue.any((press) => press.playerId == id)) {
      return false;
    }
    final teamId = game.players[id]?.teamId;
    if (game.poker case final poker?) {
      if (poker.betting ||
          teamId == null ||
          poker.settledTeamIds.contains(teamId) ||
          ((poker.wagers[teamId] ?? 0) == 0 &&
              (poker.chips[teamId] ?? 0) > 0)) {
        return false;
      }
    }
    if (game.jeopardy != null || game.poker != null) {
      if (game.mode is TeamMode &&
          round.answers.keys.any((id) => game.players[id]?.teamId == teamId)) {
        return false;
      }
    }
    return true;
  }

  void _plan(GameState game) {
    if (_closed || game.recoveryPaused) return;
    final round = game.round;
    final key = '${round.question?.id}:${round.startedAtHostMicros}';
    if (_roundKey != key) {
      _cancelBotActions();
      _performed.clear();
      _roundKey = key;
      if (round.question != null &&
          _roundStart?.round.question?.id != round.question?.id) {
        _roundStart = game;
        _roundParticipants = Map.of(_participants);
      }
    }
    if (!_botsEnabled) return;
    final previousPick = _pendingPick;
    _pendingPick = game.jeopardy?.pendingPickQuestionId;
    if (previousPick != null &&
        _pendingPick == null &&
        game.jeopardy?.pendingDailyDoubleId == null &&
        round.question == null) {
      _performed.removeWhere((action) => action.startsWith('pick:'));
    }
    if (!round.status.acceptsInput) {
      for (final action
          in _pending.keys.where((key) => key.startsWith('answer:')).toList()) {
        _pending.remove(action)!.cancel();
      }
    }
    if (round.status == RoundStatus.revealed) {
      _cancelBotActions();
      return;
    }
    for (final participant in _participants.values) {
      final settings = participant.bot;
      final id = participant.player.id;
      if (settings == null || game.players[id]?.isConnected != true) continue;

      final board = game.jeopardy;
      if (board != null &&
          game.isStarted &&
          engine.state.canStartRound &&
          game.mayPickQuestion(id)) {
        if (board.pendingDailyDoubleId case final questionId?) {
          _schedule('wager:$id:$questionId', settings, () {
            if (engine.state.game.jeopardy?.pendingDailyDoubleId !=
                    questionId ||
                !engine.state.game.mayPickQuestion(id)) {
              return;
            }
            final max = engine.maxDailyDoubleWager(engine.state.game);
            send(
              PlaceDailyDoubleWagerEvent(
                1 +
                    (_random.nextDouble() * max)
                        .floor()
                        .clamp(0, max - 1)
                        .toInt(),
                playerId: id,
                questionId: questionId,
              ),
            );
          });
        } else if (board.pendingPickQuestionId == null) {
          _schedule(
            'pick:$id:${game.completedQuestionIds.length}',
            settings,
            () {
              final current = engine.state.game;
              if (!engine.state.canStartRound ||
                  !current.mayPickQuestion(id) ||
                  current.jeopardy?.pendingPickQuestionId != null ||
                  current.jeopardy?.pendingDailyDoubleId != null) {
                return;
              }
              final choices = board.board.questionIds
                  .where((id) => !current.completedQuestionIds.contains(id))
                  .toList();
              if (choices.isNotEmpty) {
                send(
                  SelectJeopardyCellEvent(
                    choices[_random.nextInt(choices.length)],
                    playerId: id,
                  ),
                );
              }
            },
          );
        }
      }
      final question = round.question;
      if (question == null) continue;
      if (game.poker case final poker? when poker.betting) {
        final teamId = game.players[id]?.teamId;
        if (teamId != null && !poker.wagers.containsKey(teamId)) {
          _schedule('poker:$teamId', settings, () {
            final current = engine.state.game;
            final poker = current.poker!;
            if (!poker.betting || poker.wagers.containsKey(teamId)) return;
            final chips = poker.chips[teamId] ?? 0;
            // Risk a positive, affordable amount; bankrupt teams play for practice.
            final wager = chips == 0 ? 0 : 1 + _random.nextInt(chips);
            send(
              PlacePokerWagerEvent(
                playerId: id,
                questionId: question.id,
                wager: wager,
              ),
            );
          });
        }
        continue;
      }
      if (_maySubmit(game, id)) {
        _schedule('answer:$id:${round.resolvedAttempts}', settings, () {
          final current = engine.state.game;
          if (!_maySubmit(current, id)) return;
          final answer = botAnswer(
            question,
            playerId: id,
            timestamp: clock.nowMicros,
            correct: question is BuzzerQuestion || settings.succeeds(_random),
          );
          send(
            answer is BuzzerPress
                ? BuzzerPressEvent(answer)
                : SubmitAnswerEvent(answer),
          );
        });
      }
      if (question is BuzzerQuestion &&
          round.status == RoundStatus.locked &&
          round.activePlayerId == id) {
        _schedule('judge:$id:${round.resolvedAttempts}', settings, () {
          final current = engine.state.game.round;
          if (current.status == RoundStatus.locked &&
              current.activePlayerId == id) {
            send(JudgeBuzzerEvent(wasCorrect: settings.succeeds(_random)));
          }
        });
      }
      if (question.requiresManualGrading &&
          round.answers.containsKey(id) &&
          !round.answerVerdicts.containsKey(id)) {
        _schedule('grade:$id', settings, () {
          final current = engine.state.game.round;
          final answer = current.answers[id];
          if (answer != null &&
              !current.answerVerdicts.containsKey(id) &&
              current.status != RoundStatus.revealed) {
            send(
              JudgeAnswerEvent(
                playerId: id,
                questionId: question.id,
                startedAtHostMicros: current.startedAtHostMicros!,
                wasCorrect: question.accuracy(answer) == 1,
              ),
            );
          }
        });
      }
    }
  }

  void _schedule(String action, BotSettings settings, void Function() run) {
    if (_pending.containsKey(action) || _performed.contains(action)) return;
    final roundKey = _roundKey;
    _pending[action] = clock.schedule(settings.delay(_random), () {
      _pending.remove(action);
      if (_closed || !_botsEnabled || roundKey != _roundKey) return;
      _performed.add(action);
      trace.add((atMicros: clock.nowMicros, action: action));
      run();
    });
  }

  void _cancelBotActions() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancelBotActions();
    clock.cancelAll();
    await _subscription.cancel();
    try {
      await _work;
    } finally {
      await engine.close();
      clock.cancelAll();
    }
  }
}
