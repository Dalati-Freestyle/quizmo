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
import 'media_preload_registry.dart';
import 'media_screens.dart';
import 'quiz_engine_event.dart';
import 'quiz_engine_state.dart';
import 'scoring_rules.dart';
import 'session_access.dart';

export 'media_preload_registry.dart';
export 'media_screens.dart';
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
    int pokerMinStake = 0,
    int? pokerMaxStake,
    List<Joker> jokers = const [],
    List<InfoSlide> slides = const [],
    SnowflakeScoring? snowflakeScoring,
    SolutionRevealMode revealMode = SolutionRevealMode.afterEachQuestion,
    this.buzzerGraceWindow = const Duration(milliseconds: 350),
    this.autoContinueBuzzer = true,
    this.answerCountdown = Duration.zero,
    this.draftGrace = Duration.zero,
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
                     : PokerState.start(
                         pokerStartingChips,
                         teams.keys,
                         minStake: pokerMinStake,
                         maxStake: pokerMaxStake,
                       ),
                 snowflake: snowflakeScoring,
                 jokers: jokers.isEmpty ? null : JokerState(jokers: jokers),
                 slides: slides,
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
    on<EndAnswerCountdownEvent>(_onEndAnswerCountdown);
    on<UpdateDraftEvent>(_onUpdateDraft);
    on<AdoptDraftsEvent>(_onAdoptDrafts);
    on<ConfirmGradesEvent>(_onConfirmGrades);
    on<BuzzerPressEvent>(_onBuzzerPress);
    on<LockBuzzerEvent>(_onLockBuzzer);
    on<JudgeBuzzerEvent>(_onJudgeBuzzer);
    on<JudgeAnswerEvent>(_onJudgeAnswer);
    on<SetVerbalAnswersEvent>(_onSetVerbalAnswers);
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
      if (game.round.question == null && !game.showsSlide) return;
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
    on<SeekTvMediaEvent>((event, emit) {
      final game = state.game;
      if (game.round.question == null && !game.showsSlide) return;
      if (event.mediaKey.isEmpty || event.position.isNegative) return;
      emit(
        _publish(
          game.copyWith(
            tvMediaSeek: TvMediaSeek(
              mediaKey: event.mediaKey,
              positionMicros: event.position.inMicroseconds,
              revision: (game.tvMediaSeek?.revision ?? 0) + 1,
            ),
          ),
        ),
      );
    });
    on<ShowRevealMediaEvent>((event, emit) {
      final game = state.game;
      final round = game.round;
      final question = round.question;
      if (question == null ||
          round.status != RoundStatus.revealed ||
          question.media.isEmpty ||
          question.solutionMedia.isEmpty ||
          round.showsQuestionMedia == event.questionMedia) {
        return;
      }
      emit(
        _publish(
          game.copyWith(
            round: round.copyWith(showsQuestionMedia: event.questionMedia),
          ),
        ),
      );
    });
    on<PlaceDailyDoubleWagerEvent>(_onPlaceDailyDoubleWager);
    on<SetJeopardyTurnEvent>(_onSetJeopardyTurn);
    if (pokerStartingChips != null &&
        (pokerStartingChips < 1 ||
            pokerStartingChips > 1000000 ||
            pokerMinStake < 0 ||
            pokerMinStake > pokerStartingChips ||
            (pokerMaxStake != null &&
                (pokerMaxStake < 1 || pokerMaxStake < pokerMinStake)) ||
            jeopardyBoard != null)) {
      throw ArgumentError('Invalid poker configuration.');
    }
    on<PlacePokerWagerEvent>(_onPlacePokerWager);
    on<OpenPokerAnswersEvent>(_onOpenPokerAnswers);
    if (jokers.any(
      (joker) => switch (joker) {
        CreditJoker() || ForcedStakeJoker() => pokerStartingChips == null,
      },
    )) {
      throw ArgumentError('Poker jokers need a poker session.');
    }
    on<UseJokerEvent>(_onUseJoker);
    on<ShowSlideEvent>((event, emit) {
      final game = state.game;
      final slide = game.slides
          .where((slide) => slide.id == event.slideId)
          .firstOrNull;
      final running =
          game.round.question != null &&
          game.round.status != RoundStatus.revealed;
      if (slide == null || running || game.recoveryPaused) {
        emit(
          state.copyWith(
            notice: 'Zwischenfolien gehen nur zwischen den Fragen.',
          ),
        );
        return;
      }
      emit(
        _publish(
          game.copyWith(
            activeSlide: slide,
            shownSlideIds: {...game.shownSlideIds, slide.id},
          ),
        ),
      );
    });
    on<HideSlideEvent>((event, emit) {
      if (state.game.activeSlide == null) return;
      emit(_publish(state.game.copyWith(activeSlide: null)));
    });
    on<RevealPokerQuestionEvent>((event, emit) {
      final game = state.game;
      final poker = game.poker;
      if (poker == null || !poker.betting || !poker.questionHidden) return;
      emit(
        _publish(
          game.copyWith(
            poker: poker.copyWith(questionHidden: false, category: null),
          ),
          notice: 'Frage aufgedeckt. Jetzt setzen.',
        ),
      );
    });
    on<RevokeJokerEvent>(_onRevokeJoker);
    on<ShowHintEvent>(_onShowHint);
    on<TakeBackHintEvent>(_onTakeBackHint);
    on<ResetGameEvent>(_onResetGame);
    on<FinishQuizEvent>((event, emit) {
      var game = state.game;
      if (!(event.early ? game.canFinishEarly : game.canFinish)) {
        emit(
          state.copyWith(notice: 'Das Quiz kann noch nicht beendet werden.'),
        );
        return;
      }
      _graceTimer?.cancel();
      _roundTimer?.cancel();
      if (event.early) game = _cancelRunningRound(game);
      emit(_publish(game.copyWith(isFinished: true)));
    });
    on<ExpireRoundEvent>((event, emit) {
      final game = state.game;
      final round = game.round;
      if (round.question?.id != event.questionId ||
          round.startedAtHostMicros != event.startedAt ||
          round.question?.hasTimeLimit != true ||
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
      final end =
          round.timerStartedAtHostMicros! +
          round.question!.timeLimit.inMicroseconds;
      if (_waitsForDrafts(game, end, event, emit)) return;
      _expire(_settleDrafts(game, end), emit);
    });
  }

  /// Closes the answers of a round whose time is up.
  void _expire(GameState game, Emitter<QuizEngineState> emit) {
    final round = game.round;
    final locked = game.copyWith(
      round: round.copyWith(status: RoundStatus.locked),
    );
    // On a board, running out of time is a miss of the picking team: the
    // other teams may steal right away, as after a wrong answer. A round
    // the host judges stays locked until the grades are confirmed.
    if (locked.jeopardy?.isStealRound == false && !locked.round.manualGrading) {
      final scored = _scoreRound(locked, round.question!);
      if (_canOpenSteal(scored)) {
        emit(
          _publish(
            _openStealRound(scored),
            notice: 'Zeit abgelaufen. Die anderen Teams dürfen stehlen.',
          ),
        );
        return;
      }
    }
    emit(
      _publish(locked, notice: 'Zeit abgelaufen. Antworten sind geschlossen.'),
    );
  }

  void _onUpdateDraft(UpdateDraftEvent event, Emitter<QuizEngineState> emit) {
    final draft = event.draft;
    final game = state.game;
    final round = game.round;
    final question = round.question;
    if (question == null ||
        !question.supportsDrafts ||
        !_belongsToRound(draft, round) ||
        (game.poker?.betting ?? false) ||
        _rejectParticipant(round, draft.playerId) != null) {
      return;
    }
    final wait = _draftWait;
    final end = wait != null
        ? wait.endMicros
        : question.hasTimeLimit && !round.hasSoftTimer
        ? round.timerStartedAtHostMicros! + question.timeLimit.inMicroseconds
        : null;
    final time = draft.hostTimestampMicros;
    if ((wait == null && !round.status.acceptsInput) ||
        (wait == null && end != null && _now() >= end) ||
        (end != null && time >= end) ||
        time < round.startedAtHostMicros! ||
        // A clock that runs ahead must not push a draft behind the others.
        time > _now() + 250000) {
      return;
    }
    final previous = draftOf(draft.playerId);
    if (previous != null && previous.hostTimestampMicros > time) return;
    final content = draft.content;
    if (content != null && !_draftCounts(game, content)) return;
    _drafts[draft.playerId] = draft;
    _draftChanges.add(draft.playerId);
  }

  /// Whether [content] would count if the answers closed now.
  bool _draftCounts(GameState game, AnswerSubmission content) =>
      content.questionId == game.round.question?.id &&
      // Biggest Snowflake compares complete answers only.
      (game.round.snowflake != null
          ? game.round.question!.supportsDrafts &&
                game.round.question!.accepts(content)
          : game.round.question!.acceptsDraft(content));

  /// Whether somebody who may answer did not, so that a draft could count.
  bool _draftsMayCount(GameState game) {
    final round = game.round;
    if (!round.status.acceptsInput ||
        !(round.question?.supportsDrafts ?? false) ||
        (game.poker?.betting ?? false)) {
      return false;
    }
    return game.players.values.any((player) {
      if (_rejectParticipant(round, player.id) != null) return false;
      final teamId = game.sharedAnswerTeamOf(player.id);
      return teamId == null
          ? !round.answers.containsKey(player.id)
          : game.teamAnswerOf(teamId) == null;
    });
  }

  /// Closes the answers at [endMicros] and, when drafts may count, waits a
  /// moment for those under way. [resume] then goes on; returns whether it
  /// was postponed.
  bool _waitsForDrafts(
    GameState game,
    int endMicros,
    QuizEngineEvent resume,
    Emitter<QuizEngineState> emit,
  ) {
    if (draftGrace <= Duration.zero ||
        _draftWait != null ||
        !_draftsMayCount(game)) {
      return false;
    }
    final round = game.round;
    _draftWait = _DraftWait(
      questionId: round.question!.id,
      startedAt: round.startedAtHostMicros!,
      endMicros: endMicros,
      resume: resume,
    );
    emit(
      _publish(
        game.copyWith(round: round.copyWith(status: RoundStatus.locked)),
      ),
    );
    final event = AdoptDraftsEvent(
      round.question!.id,
      round.startedAtHostMicros!,
    );
    _draftTimer = _createTimer(draftGrace, () {
      if (!isClosed) add(event);
    });
    return true;
  }

  /// Takes over the drafts of a round that closed at [endMicros], or earlier
  /// when it was waiting for drafts.
  GameState _settleDrafts(GameState game, int endMicros) {
    final wait = _draftWait;
    _draftTimer?.cancel();
    _draftWait = null;
    if (wait != null) return _withAdoptedDrafts(game, wait.endMicros);
    return _draftsMayCount(game) ? _withAdoptedDrafts(game, endMicros) : game;
  }

  void _onAdoptDrafts(AdoptDraftsEvent event, Emitter<QuizEngineState> emit) {
    final wait = _draftWait;
    final round = state.game.round;
    if (wait == null ||
        wait.questionId != event.questionId ||
        wait.startedAt != event.startedAt ||
        round.question?.id != wait.questionId ||
        round.startedAtHostMicros != wait.startedAt) {
      return;
    }
    final game = _settleDrafts(state.game, wait.endMicros);
    if (game.round.manualGrading &&
        (game.round.pendingGradeCount > 0 ||
            game.round.answerVerdicts.isEmpty)) {
      emit(
        _publish(game, notice: 'Antworten sind geschlossen. Bitte bewerten.'),
      );
      return;
    }
    switch (wait.resume) {
      case ExpireRoundEvent():
        _expire(game, emit);
      case EndRoundEvent():
        _endRound(game, emit);
      default:
        _revealRound(game, emit);
    }
  }

  /// Counts the last draft of every team (or player) without a sent answer,
  /// as if it had been given exactly when the answers closed.
  GameState _withAdoptedDrafts(GameState game, int endMicros) {
    final round = game.round;
    final question = round.question!;
    final best = <String, AnswerDraft>{};
    for (final draft in _drafts.values) {
      final content = draft.content;
      final player = game.players[draft.playerId];
      if (content == null ||
          player == null ||
          !_belongsToRound(draft, round) ||
          draft.hostTimestampMicros >= endMicros ||
          !_draftCounts(game, content) ||
          _rejectParticipant(round, player.id) != null) {
        continue;
      }
      final teamId = game.sharedAnswerTeamOf(player.id);
      if (teamId == null
          ? round.answers.containsKey(player.id)
          : game.teamAnswerOf(teamId) != null) {
        continue;
      }
      final key = teamId == null ? 'player:${player.id}' : 'team:$teamId';
      final previous = best[key];
      if (previous == null || compareDraftOrder(draft, previous) > 0) {
        best[key] = draft;
      }
    }
    if (best.isEmpty) return game;
    final elapsed = round.timerElapsedAt(endMicros).inMicroseconds;
    final limit = question.timeLimit.inMicroseconds;
    return game.copyWith(
      round: round.copyWith(
        answers: {
          ...round.answers,
          for (final draft in best.values)
            draft.playerId: AnswerSubmission.fromJson({
              ...draft.content!.toJson(),
              'playerId': draft.playerId,
              'clientTimestampMicros': endMicros,
              'clockOffsetMicros': 0,
              'hostTimestampMicros': endMicros,
            }),
        },
        // Without a time bonus.
        acceptedElapsedMicros: {
          ...round.acceptedElapsedMicros,
          for (final draft in best.values)
            draft.playerId: elapsed < limit ? limit : elapsed,
        },
        adoptedPlayerIds: {
          ...round.adoptedPlayerIds,
          for (final draft in best.values) draft.playerId,
        },
      ),
    );
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

  /// Time teams have to replace their answer in a hosted or previewed game.
  static const defaultAnswerCountdown = Duration(seconds: 5);

  /// Time to replace answers after every team answered; zero closes at once.
  final Duration answerCountdown;

  Timer? _countdownTimer;

  /// Grace in a hosted or previewed game, see [draftGrace].
  static const defaultDraftGrace = Duration(milliseconds: 500);

  /// How long the host waits for drafts that were under way when the answers
  /// closed; only drafts from before that instant count. Zero: no wait.
  final Duration draftGrace;

  /// The last draft of every player in the running round.
  final Map<String, AnswerDraft> _drafts = {};

  /// Set while the host waits for drafts of a closed round.
  _DraftWait? _draftWait;
  Timer? _draftTimer;
  final StreamController<String> _draftChanges = StreamController.broadcast(
    sync: true,
  );

  /// Players whose draft changed.
  Stream<String> get draftChanges => _draftChanges.stream;

  /// TVs whose browser refuses to start media with sound.
  final MediaScreens mediaScreens = MediaScreens();

  /// Handles and keys of the uploads guests preload in the lobby; created
  /// with the first guest, the question bank never changes afterwards.
  late final MediaPreloadRegistry mediaPreload = MediaPreloadRegistry(
    state.game,
  );

  /// How far every device got with preloading.
  final MediaPreloadStatuses mediaPreloadStatuses = MediaPreloadStatuses();

  /// Whether the answers are closed but drafts under way may still arrive.
  bool get isWaitingForDrafts => _draftWait != null;

  /// The current draft of [playerId] in the running round.
  AnswerDraft? draftOf(String playerId) => switch (_drafts[playerId]) {
    final draft? when _belongsToRound(draft, state.game.round) => draft,
    _ => null,
  };

  /// What the team of [playerId] enters in the running round, for its members
  /// only: empty when they answer alone or their team may not answer.
  List<AnswerDraft> teamDraftsOf(String playerId) {
    final game = state.game;
    final teamId = game.sharedAnswerTeamOf(playerId);
    if (teamId == null ||
        game.round.status == RoundStatus.revealed ||
        (game.poker?.betting ?? false) ||
        _rejectParticipant(game.round, playerId) != null) {
      return const [];
    }
    return [
      for (final member in game.players.values)
        if (member.teamId == teamId) ?draftOf(member.id)?.preview(),
    ];
  }

  static bool _belongsToRound(AnswerDraft draft, RoundState round) =>
      draft.questionId == round.question?.id &&
      draft.roundStartedAt == round.startedAtHostMicros;
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
            hintTimesMicros: [
              for (final time in round.hintTimesMicros) time + delta,
            ],
            recoverySoftTimer:
                event.timerPolicy == RecoveryTimerPolicy.soft ||
                (event.timerPolicy == RecoveryTimerPolicy.savedTime &&
                    round.recoverySoftTimer),
            answers: round.answers.map(
              (id, answer) => MapEntry(id, shift(answer)),
            ),
            replacedAnswers: [
              for (final answer in round.replacedAnswers) shift(answer),
            ],
            answerDeadlineMicros: round.answerDeadlineMicros == null
                ? null
                : _now() + answerCountdown.inMicroseconds,
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
    _countdownTimer?.cancel();
    _draftTimer?.cancel();
    unawaited(_draftChanges.close());
    mediaScreens.close();
    mediaPreloadStatuses.close();
    unawaited(access.close());
    return super.close();
  }

  void _onKickPlayer(KickPlayerEvent event, Emitter<QuizEngineState> emit) {
    if (!state.game.players.containsKey(event.playerId)) return;
    resumeTokenHashes.remove(event.playerId);
    if (event.ban) access.ban(event.playerId);
    emit(
      _publish(
        _removePlayer(
          _handOverPoints(state.game, event.playerId),
          event.playerId,
        ),
      ),
    );
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
    final replacedAnswers = [
      for (final earlier in game.round.replacedAnswers)
        earlier.playerId == source.id
            ? earlier.withPlayerId(target.id)
            : earlier,
    ];
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
          scores: game.scores.copyWith(byPlayer: totals, history: history),
          round: cleaned.round.copyWith(
            answers: answers,
            replacedAnswers: replacedAnswers,
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
      scores: game.scores.copyWith(
        byPlayer: totals,
        history: game.scores.history.where((e) => e.playerId != id).toList(),
      ),
      round: game.round.copyWith(
        answers: answers,
        replacedAnswers: [
          for (final answer in game.round.replacedAnswers)
            if (answer.playerId != id) answer,
        ],
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
    if (_waitsForDrafts(game, _now(), event, emit)) return;
    _endRound(_settleDrafts(game, _now()), emit);
  }

  void _endRound(GameState game, Emitter<QuizEngineState> emit) {
    final question = game.round.question!;
    if (_closesForGrading(game, emit)) return;
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

    // Points earned so far stay with the team they were earned for.
    final handedOver = player.teamId == event.teamId
        ? game
        : _handOverPoints(game, player.id);
    emit(
      _publish(
        handedOver.copyWith(
          players: {
            ...game.players,
            player.id: player.copyWith(teamId: event.teamId),
          },
        ),
      ),
    );
  }

  /// Cancels a round that is not revealed yet, for an early end of the game:
  /// nothing is scored, the question stays unplayed, reserved poker stakes go
  /// back to the teams and pending board picks are dropped.
  GameState _cancelRunningRound(GameState game) {
    final poker = game.poker;
    final jeopardy = game.jeopardy;
    final running =
        game.round.question != null &&
        game.round.status != RoundStatus.revealed;
    // Jokers of a cancelled question are given back, including their price.
    var jokers = game.jokers;
    final refunds = <String, int>{};
    if (running && jokers != null) {
      for (final play in jokers.plays) {
        jokers = jokers!.withoutPlay(play);
        refunds[play.teamId] = (refunds[play.teamId] ?? 0) + play.paidChips;
      }
    }
    return game.copyWith(
      round: running ? RoundState.idle : game.round,
      jokers: jokers,
      poker: poker == null || game.round.status == RoundStatus.revealed
          ? poker
          : poker.copyWith(
              questionHidden: false,
              category: null,
              chips: {
                for (final entry in poker.chips.entries)
                  entry.key:
                      (poker.settledTeamIds.contains(entry.key)
                          ? entry.value
                          : entry.value + (poker.wagers[entry.key] ?? 0)) +
                      (refunds[entry.key] ?? 0),
              },
              wagers: const {},
              betting: false,
            ),
      jeopardy: jeopardy?.copyWith(
        pendingDailyDoubleId: null,
        pendingPickQuestionId: null,
        pendingPickPlayerId: null,
        activePoints: running ? null : jeopardy.activePoints,
        isStealRound: running ? false : jeopardy.isStealRound,
      ),
    );
  }

  /// With teams, the points of [playerId] stay with their current team
  /// before they leave it (team change or removal).
  GameState _handOverPoints(GameState game, String playerId) {
    final teamId = game.players[playerId]?.teamId;
    if (game.mode is! TeamMode ||
        game.poker != null ||
        teamId == null ||
        !game.teams.containsKey(teamId)) {
      return game;
    }
    return game.copyWith(
      scores: game.scores.handOverToTeam(
        playerId: playerId,
        teamId: teamId,
        atHostMicros: _now(),
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
    if (state.game.round.manualGrading && !state.canStartRound) {
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
            questionHidden: _announcesCategory(game),
            category: _announcesCategory(game) ? question.category : null,
          ),
          jokers: game.jokers?.copyWith(plays: const []),
          activeSlide: null,
          round: RoundState(
            question: question,
            status: RoundStatus.acceptingAnswers,
            startedAtHostMicros: _now(),
            snowflake: game.snowflake,
            verbal: _verbalFor(game, question),
          ),
        ),
        notice: 'Round started: ${markdownToPlain(question.prompt)}',
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
    final teamId = game.sharedAnswerTeamOf(answer.playerId);
    if (teamId == null && round.answers.containsKey(answer.playerId)) {
      emit(state.copyWith(notice: 'Only the first answer counts.'));
      return;
    }
    final previous = round.lastSubmissionOf(answer.playerId);
    if (previous != null && compareAnswerOrder(answer, previous) <= 0) {
      // A repeated or overtaken frame of the same player.
      return;
    }
    final current = game.teamAnswerOf(teamId);
    if (current != null && round.answerVerdicts.containsKey(current.playerId)) {
      emit(
        state.copyWith(notice: 'Die Antwort des Teams wurde schon bewertet.'),
      );
      return;
    }

    // The last answer of a team counts; the ones before stay on record.
    final updated = _withValidTeamAnswers(
      game.copyWith(
        round: round.copyWith(
          answers: {...round.answers, answer.playerId: answer},
          replacedAnswers: teamId == null || previous == null
              ? null
              : [
                  for (final earlier in round.replacedAnswers)
                    if (earlier != previous) earlier,
                  previous,
                ],
          acceptedElapsedMicros: {
            ...round.acceptedElapsedMicros,
            answer.playerId: round
                .timerElapsedAt(answer.hostTimestampMicros)
                .inMicroseconds,
          },
        ),
      ),
    );

    if (!_everyoneAnswered(updated)) {
      emit(_publish(updated));
      return;
    }
    final announced = updated.copyWith(
      // Replacing an answer does not announce it again.
      allAnswersRevision:
          game.allAnswersRevision +
          (round.answerDeadlineMicros == null ? 1 : 0),
    );
    final closes = round.manualGrading || !round.hasSoftTimer;
    if (closes && teamId != null && answerCountdown > Duration.zero) {
      emit(
        _publish(
          announced.copyWith(
            round: announced.round.copyWith(
              answerDeadlineMicros: _countdownEnd(announced.round),
            ),
          ),
        ),
      );
      return;
    }
    _closeAnswered(announced, emit);
  }

  /// Closes the answers of a round that everybody answered.
  void _closeAnswered(GameState game, Emitter<QuizEngineState> emit) {
    if (!game.round.manualGrading) {
      emit(_publish(game));
      if (!game.round.hasSoftTimer) add(const RevealRoundEvent());
      return;
    }
    emit(
      _publish(
        game.copyWith(round: game.round.copyWith(status: RoundStatus.locked)),
      ),
    );
  }

  /// End of a fresh countdown; never later than the time limit.
  int _countdownEnd(RoundState round) {
    final end = _now() + answerCountdown.inMicroseconds;
    final question = round.question!;
    if (!question.hasTimeLimit || round.hasSoftTimer) return end;
    final limit =
        round.timerStartedAtHostMicros! + question.timeLimit.inMicroseconds;
    return limit < end ? limit : end;
  }

  void _onEndAnswerCountdown(
    EndAnswerCountdownEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    final deadline = game.round.answerDeadlineMicros;
    if (deadline == null ||
        !game.round.status.acceptsInput ||
        (event.deadlineMicros != null && event.deadlineMicros != deadline)) {
      return;
    }
    _closeAnswered(
      game.copyWith(round: game.round.copyWith(answerDeadlineMicros: null)),
      emit,
    );
  }

  /// Keeps exactly one answer per team that shares its answer: a judged one,
  /// else the last one its current members sent. Also settles the answers
  /// after players changed teams or were removed.
  GameState _withValidTeamAnswers(GameState game) {
    final round = game.round;
    if (!game.sharesTeamAnswers ||
        round.status == RoundStatus.revealed ||
        round.allSubmissions.isEmpty) {
      return game;
    }
    final answers = <String, AnswerSubmission>{};
    final replaced = <AnswerSubmission>[];
    final valid = <String, AnswerSubmission>{};
    bool judged(AnswerSubmission answer) =>
        round.answers[answer.playerId] == answer &&
        round.answerVerdicts.containsKey(answer.playerId);
    for (final answer in round.allSubmissions) {
      final player = game.players[answer.playerId];
      if (player == null) continue;
      final teamId = player.teamId;
      if (teamId == null) {
        if (round.answers[answer.playerId] == answer) {
          answers[answer.playerId] = answer;
        }
        continue;
      }
      final best = valid[teamId];
      final wins =
          best == null ||
          (judged(answer) != judged(best)
              ? judged(answer)
              : compareAnswerOrder(answer, best) > 0);
      if (wins) {
        if (best != null) replaced.add(best);
        valid[teamId] = answer;
      } else {
        replaced.add(answer);
      }
    }
    for (final answer in valid.values) {
      answers[answer.playerId] = answer;
    }
    return game.copyWith(
      round: round.copyWith(
        answers: answers,
        replacedAnswers: replaced,
        answerVerdicts: {
          for (final entry in round.answerVerdicts.entries)
            if (answers[entry.key] == round.answers[entry.key] &&
                answers.containsKey(entry.key))
              entry.key: entry.value,
        },
      ),
    );
  }

  void _onJudgeAnswer(JudgeAnswerEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    final answered = round.answers.containsKey(event.playerId);
    if (!round.manualGrading ||
        round.question?.id != event.questionId ||
        round.startedAtHostMicros != event.startedAtHostMicros ||
        (round.status != RoundStatus.acceptingAnswers &&
            round.status != RoundStatus.locked) ||
        !(answered || game.mayJudgeVerbally(event.playerId)) ||
        (game.poker?.betting ?? false)) {
      emit(state.copyWith(notice: 'Diese Antwort kann nicht bewertet werden.'));
      return;
    }
    if (round.answerVerdicts[event.playerId] == (event.wasCorrect ? 1 : 0)) {
      return;
    }
    emit(
      _publish(
        _withVerdict(game, event.playerId, event.wasCorrect, event.reason),
      ),
    );
  }

  /// Records the host's verdict on the answer of [playerId]; a spoken answer
  /// without typed text is created by it.
  GameState _withVerdict(
    GameState game,
    String playerId,
    bool correct,
    String? reason,
  ) {
    final round = game.round;
    final answered = round.answers.containsKey(playerId);
    final value = correct ? 1 : 0;
    final now = _now();
    final updated = game.copyWith(
      round: round.copyWith(
        answers: answered
            ? null
            : {
                ...round.answers,
                playerId: VerbalAnswer(
                  playerId: playerId,
                  questionId: round.question!.id,
                  clientTimestampMicros: now,
                ),
              },
        acceptedElapsedMicros: answered
            ? null
            : {
                ...round.acceptedElapsedMicros,
                playerId: round.timerElapsedAt(now).inMicroseconds,
              },
        answerVerdicts: {...round.answerVerdicts, playerId: value},
      ),
    );
    return _recordJudgment(
      game,
      updated,
      playerId,
      CorrectionKind.answer,
      round.answerVerdicts[playerId],
      value,
      reason,
    );
  }

  void _onConfirmGrades(
    ConfirmGradesEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    var game = state.game;
    final round = game.round;
    // A stale or repeated confirmation never judges another round.
    if (game.recoveryPaused ||
        !round.manualGrading ||
        round.status != RoundStatus.locked ||
        _draftWait != null ||
        round.question?.id != event.questionId ||
        round.startedAtHostMicros != event.startedAtHostMicros ||
        (game.poker?.betting ?? false)) {
      emit(state.copyWith(notice: 'Diese Runde kann nicht bewertet werden.'));
      return;
    }
    if (round.answers.keys.any(
      (id) =>
          !event.grades.containsKey(id) &&
          !round.answerVerdicts.containsKey(id),
    )) {
      emit(
        state.copyWith(
          notice: 'Bitte erst alle eingegangenen Antworten bewerten.',
        ),
      );
      return;
    }
    for (final entry in event.grades.entries) {
      if (!game.round.answers.containsKey(entry.key) &&
          !game.mayJudgeVerbally(entry.key)) {
        continue;
      }
      if (game.round.answerVerdicts[entry.key] ==
          (entry.value.correct ? 1 : 0)) {
        continue;
      }
      game = _withVerdict(
        game,
        entry.key,
        entry.value.correct,
        entry.value.reason,
      );
    }
    _revealRound(game, emit);
  }

  /// Closes the answers of a round the host still has to judge.
  bool _closesForGrading(GameState game, Emitter<QuizEngineState> emit) {
    final round = game.round;
    if (!round.manualGrading ||
        !round.status.acceptsInput ||
        (round.pendingGradeCount == 0 && round.answerVerdicts.isNotEmpty)) {
      return false;
    }
    emit(
      _publish(
        game.copyWith(round: round.copyWith(status: RoundStatus.locked)),
        notice: 'Antworten sind geschlossen. Bitte bewerten.',
      ),
    );
    return true;
  }

  void _onSetVerbalAnswers(
    SetVerbalAnswersEvent event,
    Emitter<QuizEngineState> emit,
  ) {
    final game = state.game;
    if (game.snowflake != null) {
      emit(
        state.copyWith(
          notice: 'Biggest Snowflake vergleicht die Antworten, mündliche Antworten sind nicht möglich.',
        ),
      );
      return;
    }
    if (game.verbalAnswers == event.enabled) return;
    final round = game.round;
    final question = round.question;
    // A round that was already judged keeps its rules; the setting then
    // applies from the next round on.
    final adjustable =
        question != null &&
        question is! BuzzerQuestion &&
        round.status != RoundStatus.revealed &&
        round.answerVerdicts.isEmpty &&
        !round.answers.values.any((answer) => answer is VerbalAnswer);
    emit(
      _publish(
        game.copyWith(
          verbalAnswers: event.enabled,
          round: adjustable
              ? round.copyWith(
                  verbal: _verbalFor(game, question, enabled: event.enabled),
                )
              : null,
        ),
        notice: event.enabled
            ? 'Mündliche Antworten aktiv: du bewertest jede Antwort selbst.'
            : 'Mündliche Antworten aus.',
      ),
    );
  }

  /// Whether a round of [question] takes its answers aloud.
  bool _verbalFor(GameState game, Question question, {bool? enabled}) =>
      (enabled ?? game.verbalAnswers) &&
      game.snowflake == null &&
      question is! BuzzerQuestion;

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
    final poker = game.poker;
    final bound = event.questionId != null || event.roundStartedAt != null;
    var player = event.playerId == null ? null : game.players[event.playerId];
    var team = event.teamId == null ? null : game.teams[event.teamId];
    // With teams, players have no points of their own: a free change for a
    // player is booked on the player's team.
    final playerTeam = game.teams[player?.teamId];
    if (!bound &&
        event.teamId == null &&
        (game.mode is TeamMode || poker != null) &&
        playerTeam != null) {
      team = playerTeam;
      player = null;
    }
    if (game.recoveryPaused ||
        event.requestId.isEmpty ||
        event.delta == 0 ||
        (event.playerId == null) == (event.teamId == null) ||
        (player == null && team == null) ||
        (team != null && game.mode is! TeamMode && poker == null) ||
        (bound &&
            (game.round.question?.id != event.questionId ||
                game.round.startedAtHostMicros != event.roundStartedAt)) ||
        (poker != null &&
            !poker.chips.containsKey(team?.id ?? player?.teamId))) {
      emit(state.copyWith(notice: 'Diese Korrektur ist nicht zulässig.'));
      return;
    }
    final reason = event.reason.trim();
    if (reason.isEmpty) {
      emit(state.copyWith(notice: 'Bitte eine Begründung angeben.'));
      return;
    }
    final id = 'score-${event.requestId}';
    if (game.corrections.any((entry) => entry.id == id)) {
      emit(state.copyWith(notice: 'Diese Korrektur wurde bereits angewendet.'));
      return;
    }
    final teamId = team?.id ?? (game.mode is TeamMode ? player!.teamId : null);
    final previous = poker != null
        ? poker.chips[team?.id ?? player!.teamId]!
        : team != null
        ? game.teamScores[team.id] ?? 0
        : game.scores.scoreOf(player!.id);
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
      playerId: player?.id ?? '',
      teamId: poker != null ? team?.id ?? player!.teamId : teamId,
      participantName: team != null
          ? team.name
          : game.mode is TeamMode
          ? '${game.teams[player!.teamId]?.name ?? player.teamId} / ${player.name}'
          : player!.name,
      beforeValue: previous,
      afterValue: next,
      atHostMicros: _now(),
      reason: reason,
      scoreDeltas: poker == null && player != null
          ? {player.id: event.delta}
          : const {},
      teamDeltas: poker == null && team != null
          ? {team.id: event.delta}
          : const {},
      chipDeltas: poker == null
          ? const {}
          : {(team?.id ?? player!.teamId)!: event.delta},
      beforeEliminations: {
        if (next > 0)
          for (final entry in {...?poker?.eliminations}.entries)
            if (entry.key == (team?.id ?? player!.teamId))
              entry.key: entry.value,
      },
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
    if (entry.targetsTeam) {
      if (entry.teamId == null ||
          !game.teams.containsKey(entry.teamId) ||
          entry.teamDeltas.keys.any((id) => !game.teams.containsKey(id))) {
        return 'Die betroffenen Teilnehmer oder Teams wurden verändert.';
      }
    } else {
      final player = game.players[entry.playerId];
      if (player == null ||
          (game.mode is TeamMode ? player.teamId : null) != entry.teamId ||
          entry.scoreDeltas.keys.any((id) => !game.players.containsKey(id))) {
        return 'Die betroffenen Teilnehmer oder Teams wurden verändert.';
      }
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
            game.poker?.copyWith(
                  chips: entry.afterPoker?.chips,
                  eliminations: entry.afterPoker?.eliminations,
                ) !=
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
        CorrectionKind.points when original.targetsTeam =>
          game.teamScores[original.teamId] ?? 0,
        CorrectionKind.points => game.scores.scoreOf(original.playerId),
        CorrectionKind.chips => game.poker!.chips[original.teamId]!,
        _ => original.afterValue,
      },
      afterValue: switch (original.kind) {
        CorrectionKind.points when original.targetsTeam =>
          (game.teamScores[original.teamId] ?? 0) -
              original.teamDeltas[original.teamId]!,
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
      teamDeltas: original.teamDeltas.map((id, delta) => MapEntry(id, -delta)),
    );
    var updated = _applyCorrectionDeltas(
      game,
      inverse,
      restored: _formerEliminations(game, original),
    );
    if (original.kind == CorrectionKind.answer) {
      final verdicts = {...game.round.answerVerdicts}
        ..remove(original.playerId);
      if (original.beforeValue != null) {
        verdicts[original.playerId] = original.beforeValue!;
      }
      // A spoken answer exists only through its verdict.
      final dropSpoken =
          original.beforeValue == null &&
          game.round.answers[original.playerId] is VerbalAnswer;
      updated = updated.copyWith(
        round: game.round.copyWith(
          answerVerdicts: verdicts,
          answers: dropSpoken
              ? ({...game.round.answers}..remove(original.playerId))
              : null,
          acceptedElapsedMicros: dropSpoken
              ? ({...game.round.acceptedElapsedMicros}
                  ..remove(original.playerId))
              : null,
        ),
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
        reportRounds: game.reportRounds
            .where(
              (r) =>
                  r.round.question?.id != original.questionId ||
                  r.round.startedAtHostMicros !=
                      original.afterRound?.startedAtHostMicros ||
                  r.isSteal != (original.afterJeopardy?.isStealRound ?? false),
            )
            .toList(),
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

  /// When the teams of [original] had gone out before corrections that are all
  /// undone together with [original] brought them back.
  Map<String, int> _formerEliminations(
    GameState game,
    ManualCorrection original,
  ) {
    final reversed = {
      original.id,
      for (final entry in game.corrections) ?entry.reversesId,
    };
    return {
      for (final entry in game.corrections)
        if (reversed.contains(entry.id))
          for (final moment in entry.beforeEliminations.entries)
            if (original.chipDeltas.containsKey(moment.key))
              moment.key: moment.value,
    };
  }

  GameState _applyCorrectionDeltas(
    GameState game,
    ManualCorrection entry, {
    Map<String, int> restored = const {},
  }) {
    var scores = game.scores;
    for (final delta in entry.scoreDeltas.entries) {
      scores = scores.apply(
        playerId: delta.key,
        questionId: entry.questionId ?? '',
        delta: ScoreDelta(delta.value, reason: 'Manual correction'),
        atHostMicros: entry.atHostMicros,
      );
    }
    for (final delta in entry.teamDeltas.entries) {
      scores = scores.applyToTeam(
        teamId: delta.key,
        questionId: entry.questionId ?? '',
        delta: ScoreDelta(delta.value, reason: 'Manual correction'),
        atHostMicros: entry.atHostMicros,
      );
    }
    var poker = game.poker;
    if (poker != null && entry.chipDeltas.isNotEmpty) {
      poker = poker
          .copyWith(
            chips: {
              ...poker.chips,
              for (final delta in entry.chipDeltas.entries)
                delta.key: poker.chips[delta.key]! + delta.value,
            },
          )
          .withReturnedTeams();
      poker = poker.copyWith(
        eliminations: {
          ...poker.eliminations,
          for (final moment in restored.entries)
            if (poker.ownedBy(moment.key) == 0) moment.key: moment.value,
        },
      );
      // While a question runs, its settlement decides who goes out.
      if (game.round.question == null ||
          game.round.status == RoundStatus.revealed) {
        poker = poker.withEliminations(
          game.reportRounds.length,
          teamIds: entry.chipDeltas.keys,
        );
      }
    }
    return game.copyWith(scores: scores, poker: poker);
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

    final delta = applyHintDeduction(
      _ruleFor(game, question).evaluate(
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
      ),
      round.hintDeductionAt(atHostMicros),
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
    final next = round.copyWith(
      activePlayerId: null,
      buzzerAnswerCorrect: false,
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
    if (_waitsForDrafts(game, _now(), event, emit)) return;
    _revealRound(_settleDrafts(game, _now()), emit);
  }

  void _revealRound(GameState game, Emitter<QuizEngineState> emit) {
    final question = game.round.question!;
    if (_closesForGrading(game, emit)) return;
    if (_awaitManualGrades(game, emit)) return;

    final scored = _scoreRound(game, question);

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

  /// Books the submitted answers of the round on stage. Buzzer rounds are
  /// scored while judging, so there is nothing left to book.
  GameState _scoreRound(GameState game, Question question) =>
      // Points are resolved per question kind — polymorphism, not a type
      // switch on a string identifier.
      switch (question) {
        MultipleChoiceQuestion() ||
        ShortAnswerQuestion() ||
        OrderingQuestion() ||
        MatchingQuestion() ||
        LocationQuestion() ||
        EstimationQuestion() ||
        TrueFalseQuestion() => _scoreAnswers(game, question),
        BuzzerQuestion() => game,
      };

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
            questionHidden: _announcesCategory(game),
            category: _announcesCategory(game) ? question.category : null,
          ),
          jokers: game.jokers?.copyWith(plays: const []),
          activeSlide: null,
          round: RoundState(
            question: question,
            status: RoundStatus.acceptingAnswers,
            startedAtHostMicros: _now(),
            snowflake: game.snowflake,
            verbal: _verbalFor(game, question),
          ),
          jeopardy: jeopardy.copyWith(
            pendingDailyDoubleId: null,
            activePoints: points,
            activeIsDailyDouble: isDailyDouble,
            isStealRound: false,
          ),
        ),
        notice: 'Round started: ${markdownToPlain(question.prompt)}',
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
    // A right answer that hints reduced to 0 points is still no miss.
    final points = jeopardy.activePoints ?? 0;
    if (game.round.hintDeduction > 0 &&
        game.round.answers.values.any(
          (answer) =>
              (points * (game.round.accuracyFor(answer) ?? 0)).round() > 0,
        )) {
      return false;
    }
    return !game.scores.history.any(
      (event) => event.questionId == question.id && event.points > 0,
    );
  }

  /// Restarts the question on stage for the teams other than the picker.
  GameState _openStealRound(GameState game) {
    _graceTimer?.cancel();
    game = _recordReportRound(game);
    return game.copyWith(
      round: RoundState(
        question: game.round.question,
        resolvedAttempts: game.round.resolvedAttempts,
        lockedOutPlayerIds: game.round.lockedOutPlayerIds,
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: _now(),
        snowflake: game.snowflake,
        verbal: game.round.verbal,
        // The other teams saw the hints too.
        hintTimesMicros: game.round.hintTimesMicros,
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

  /// Whether everybody (with shared answers: every team) that may answer did.
  bool _everyoneAnswered(GameState game) {
    final expected = game.expectedAnswerers;
    return expected.isNotEmpty && expected.every(game.hasAnswered);
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
          snowflake: game.snowflake,
          poker: game.poker == null
              ? null
              : PokerState.start(
                  game.poker!.startingChips,
                  teams.keys,
                  minStake: game.poker!.minStake,
                  maxStake: game.poker!.maxStake,
                ),
          jokers: game.jokers == null
              ? null
              : JokerState(jokers: game.jokers!.jokers),
          slides: game.slides,
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
    game = _withValidTeamAnswers(game);
    if (game.round.answerDeadlineMicros != null &&
        (!game.round.status.acceptsInput || !_everyoneAnswered(game))) {
      game = game.copyWith(
        round: game.round.copyWith(answerDeadlineMicros: null),
      );
    }
    game = _recordReportRound(game);
    _roundTimer?.cancel();
    _countdownTimer?.cancel();
    final round = game.round;
    if (_draftWait case final wait?
        when wait.questionId != round.question?.id ||
            wait.startedAt != round.startedAtHostMicros ||
            round.status == RoundStatus.revealed) {
      _draftTimer?.cancel();
      _draftWait = null;
    }
    _drafts.removeWhere((_, draft) => !_belongsToRound(draft, round));
    if (round.answerDeadlineMicros case final deadline?
        when !game.recoveryPaused) {
      final remaining = deadline - _now();
      _countdownTimer = _createTimer(
        Duration(microseconds: remaining < 0 ? 0 : remaining),
        () {
          if (!isClosed) {
            add(EndAnswerCountdownEvent(deadlineMicros: deadline));
          }
        },
      );
    }
    final question = round.question;
    final start = round.startedAtHostMicros;
    if (question != null &&
        question.hasTimeLimit &&
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
                game.activeSlide?.id != state.game.activeSlide?.id ||
                (game.round.status == RoundStatus.revealed &&
                    state.game.round.status != RoundStatus.revealed)
            ? false
            : game.tvMediaPaused,
      ),
      notice: notice,
    );
  }

  GameState _recordReportRound(GameState game) {
    final round = game.round;
    if (round.question == null ||
        round.startedAtHostMicros == null ||
        (game.poker?.betting ?? false)) {
      return game;
    }
    if (state.game.recoveryPaused && !game.recoveryPaused) {
      final oldStart = state.game.round.startedAtHostMicros;
      final shift =
          round.startedAtHostMicros! - (oldStart ?? round.startedAtHostMicros!);
      final restoredIndex = game.reportRounds.lastIndexWhere(
        (record) =>
            record.round.question?.id == round.question?.id &&
            record.round.startedAtHostMicros == oldStart &&
            (round.status == RoundStatus.revealed ||
                record.isSteal == (game.jeopardy?.isStealRound ?? false)),
      );
      game = game.copyWith(
        reportRounds: [
          for (final (index, record) in game.reportRounds.indexed)
            if (index == restoredIndex)
              record.withRound(
                round,
                presses: {
                  for (final entry in record.presses.entries)
                    entry.key: BuzzerPress(
                      playerId: entry.value.playerId,
                      questionId: entry.value.questionId,
                      clientTimestampMicros:
                          entry.value.clientTimestampMicros + shift,
                      clockOffsetMicros: entry.value.clockOffsetMicros,
                    ),
                },
              )
            else
              record,
        ],
      );
    }
    final index = game.reportRounds.lastIndexWhere(
      (entry) =>
          entry.round.question?.id == round.question?.id &&
          entry.round.startedAtHostMicros == round.startedAtHostMicros &&
          (round.status == RoundStatus.revealed ||
              entry.isSteal == (game.jeopardy?.isStealRound ?? false)),
    );
    final previous = index < 0 ? null : game.reportRounds[index];
    final frozen = previous?.round.status == RoundStatus.revealed;
    final poker = game.poker;
    final record = ReportRound(
      round: frozen ? previous!.round : round,
      players: frozen
          ? previous!.players
          : {...?previous?.players, ...game.players},
      teamNames: frozen
          ? previous!.teamNames
          : {
              ...?previous?.teamNames,
              for (final team in game.teams.values) team.id: team.name,
            },
      eligiblePlayerIds: {
        ...?previous?.eligiblePlayerIds,
        if (!frozen &&
            round.status != RoundStatus.revealed &&
            !(poker?.betting ?? false))
          for (final player in game.players.values)
            if (game.mayAnswerQuestion(player.id) &&
                (poker == null ||
                    (poker.wagers[player.teamId] ?? 0) > 0 ||
                    (poker.chips[player.teamId] ?? 0) == 0))
              player.id,
      },
      disconnectedPlayerIds: {
        ...?previous?.disconnectedPlayerIds,
        if (!frozen)
          for (final player in game.players.values)
            if (!player.isConnected) player.id,
        if (!frozen)
          ...?previous?.players.keys.where(
            (id) => !game.players.containsKey(id),
          ),
      },
      presses: {
        ...?previous?.presses,
        for (final press in round.buzzerQueue) press.playerId: press,
      },
      playerScores: {...?previous?.playerScores, ...game.scores.byPlayer},
      chips: Map.of(poker?.chips ?? const {}),
      wagers: Map.of(poker?.wagers ?? const {}),
      practiceTeamIds: {
        ...?previous?.practiceTeamIds,
        if (poker != null &&
            !poker.betting &&
            !frozen &&
            round.status != RoundStatus.revealed)
          for (final id in game.teams.keys)
            if ((poker.wagers[id] ?? 0) == 0 && (poker.chips[id] ?? 0) == 0) id,
      },
      isSteal: previous?.isSteal ?? game.jeopardy?.isStealRound ?? false,
      isDailyDouble:
          previous?.isDailyDouble ??
          game.jeopardy?.activeIsDailyDouble ??
          false,
      pointsAtStake: previous?.pointsAtStake ?? game.jeopardy?.activePoints,
    );
    final records = [...game.reportRounds];
    if (index < 0) {
      records.add(record);
    } else {
      records[index] = record;
    }
    return game.copyWith(reportRounds: records);
  }

  /// One-based number of the question on stage in the order of play.
  int _playedQuestionNumber(GameState game) {
    final index = game.reportRounds.lastIndexWhere(
      (entry) =>
          entry.round.question?.id == game.round.question?.id &&
          entry.round.startedAtHostMicros == game.round.startedAtHostMicros,
    );
    return (index < 0 ? game.reportRounds.length : index) + 1;
  }

  /// Marks the round revealed and files the question as played.
  ///
  /// A question played from the board also passes the pick on to the next team.
  GameState _reveal(GameState game) {
    if (game.poker case final poker?) {
      for (final teamId in poker.wagers.keys) {
        game = _settlePoker(game, teamId, false);
      }
      game = game.copyWith(
        poker: game.poker!
            .copyWith(betting: false)
            .withEliminations(_playedQuestionNumber(game)),
      );
    }
    final question = game.round.question;
    final jeopardy = game.jeopardy;
    // The last reveal does not finish the game: guests keep seeing the
    // solution until the host finishes it (`FinishQuizEvent`).
    return game.copyWith(
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
    if (question.hasTimeLimit &&
        !round.hasSoftTimer &&
        !(state.game.poker?.betting ?? false) &&
        round.timerElapsedAt(_now()) >= question.timeLimit) {
      return 'Zeit abgelaufen. Antworten sind geschlossen.';
    }
    if (state.game.players[playerId]?.isConnected != true) {
      return 'Unknown or disconnected player.';
    }
    return _rejectParticipant(round, playerId);
  }

  /// Why [playerId] may not answer the question on stage in this format.
  String? _rejectParticipant(RoundState round, String playerId) {
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
      ..sort(compareAnswerOrder);

    var scores = game.scores;
    var correctRank = 0;
    final rule = _ruleFor(game, question);
    for (var index = 0; index < submissions.length; index++) {
      final answer = submissions[index];
      final accuracy =
          round.accuracyFor(answer) ??
          (throw StateError('Cannot score an ungraded answer.'));
      final isCorrect = accuracy > 0;
      final delta = applyHintDeduction(
        evaluateAccuracy(
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
        ),
        // Only the hints visible when the answer was given count.
        round.hintDeductionAt(answer.hostTimestampMicros),
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
        poker.questionHidden ||
        !poker.allowsStake(event.wager, poker.availableFor(teamId)) ||
        game.jokers?.playAimedAt(teamId) != null) {
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
    if (poker == null ||
        !poker.betting ||
        poker.questionHidden ||
        game.round.question == null) {
      return;
    }
    // With a minimum stake nobody may sit out: teams that bet too little (or
    // nothing) are raised to the minimum, or all-in when they have less.
    final wagers = {...poker.wagers};
    final chips = {...poker.chips};
    for (final teamId in game.teams.keys) {
      final available = poker.availableFor(teamId);
      final lowest = poker.lowestStakeFor(available);
      if ((wagers[teamId] ?? 0) < lowest &&
          game.jokers?.playAimedAt(teamId) == null) {
        wagers[teamId] = lowest;
        chips[teamId] = available - lowest;
      }
    }
    emit(
      _publish(
        game.copyWith(
          poker: poker.copyWith(betting: false, wagers: wagers, chips: chips),
          round: game.round.copyWith(
            startedAtHostMicros: _now(),
            timerRestartedAtHostMicros: null,
          ),
        ),
        notice: 'Einsätze geschlossen. Antworten sind jetzt offen.',
      ),
    );
  }

  void _onUseJoker(UseJokerEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final jokers = game.jokers;
    final joker = jokers?.jokerById(event.jokerId);
    final teamId = event.teamId ?? game.players[event.playerId]?.teamId;
    void reject(String notice) => emit(state.copyWith(notice: notice));
    if (jokers == null ||
        joker == null ||
        teamId == null ||
        !game.teams.containsKey(teamId) ||
        game.recoveryPaused ||
        game.round.question == null ||
        game.round.status == RoundStatus.revealed ||
        (event.questionId != null &&
            event.questionId != game.round.question!.id) ||
        (event.roundStartedAt != null &&
            event.roundStartedAt != game.round.startedAtHostMicros)) {
      return reject('Dieser Joker kann gerade nicht gespielt werden.');
    }
    if (jokers.remainingFor(teamId, joker) < 1) {
      return reject('Dieser Joker ist für das Team schon verbraucht.');
    }
    if (jokers.involves(teamId)) {
      return reject(
        'Das Team ist in dieser Frage schon von einem Joker belegt.',
      );
    }
    final target = event.targetTeamId;
    if (joker.needsTarget &&
        (target == null ||
            target == teamId ||
            !game.teams.containsKey(target) ||
            jokers.involves(target))) {
      return reject('Dieses Team kann nicht angegriffen werden.');
    }
    final poker = game.poker;
    // Jokers played before the reveal belong to the category phase, all
    // others to the betting once the question is known.
    if (poker != null && poker.questionHidden != joker.beforeReveal) {
      return reject(
        joker.beforeReveal
            ? 'Dieser Joker muss vor dem Aufdecken der Frage gespielt werden.'
            : 'Dieser Joker geht erst, wenn die Frage aufgedeckt ist.',
      );
    }
    switch (joker) {
      case CreditJoker():
        if (poker == null || !poker.betting || poker.availableFor(teamId) < 1) {
          return reject('Der Kredit-Joker geht nur während der Einsatzphase.');
        }
        emit(
          _publish(
            game.copyWith(
              jokers: jokers.withPlay(
                JokerPlay(jokerId: joker.id, teamId: teamId),
              ),
            ),
            notice: 'Joker gespielt.',
          ),
        );
      case ForcedStakeJoker(:final stake, :final cost):
        if (poker == null ||
            !poker.betting ||
            target == null ||
            poker.availableFor(target) < 1 ||
            (poker.chips[teamId] ?? 0) < cost) {
          return reject(
            'Der Angriffs-Joker geht nur während der Einsatzphase, gegen ein '
            'Team mit Chips und wenn der Angreifer ihn bezahlen kann.',
          );
        }
        final available = poker.availableFor(target);
        final forced = stake < available ? stake : available;
        emit(
          _publish(
            game.copyWith(
              jokers: jokers.withPlay(
                JokerPlay(
                  jokerId: joker.id,
                  teamId: teamId,
                  targetTeamId: target,
                  paidChips: cost,
                ),
              ),
              poker: poker.copyWith(
                chips: {
                  ...poker.chips,
                  teamId: poker.chips[teamId]! - cost,
                  target: available - forced,
                },
                wagers: {...poker.wagers, target: forced},
              ),
            ),
            notice: 'Joker gespielt.',
          ),
        );
    }
  }

  /// Whether new poker questions start with the category phase: only when
  /// the quiz has a joker that is played before the reveal.
  bool _announcesCategory(GameState game) =>
      game.poker != null &&
      (game.jokers?.jokers.any((joker) => joker.beforeReveal) ?? false);

  void _onRevokeJoker(RevokeJokerEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final jokers = game.jokers;
    final play = jokers?.plays
        .where(
          (play) =>
              play.teamId == event.teamId && play.jokerId == event.jokerId,
        )
        .firstOrNull;
    final poker = game.poker;
    if (jokers == null || play == null || !(poker?.betting ?? true)) return;
    final chips = {...?poker?.chips};
    final wagers = {...?poker?.wagers};
    chips[play.teamId] = (chips[play.teamId] ?? 0) + play.paidChips;
    if (play.targetTeamId case final target?) {
      // The forced stake goes back; the target bets again freely.
      chips[target] = (chips[target] ?? 0) + (wagers.remove(target) ?? 0);
    }
    emit(
      _publish(
        game.copyWith(
          jokers: jokers.withoutPlay(play),
          poker: poker?.copyWith(chips: chips, wagers: wagers),
        ),
        notice: 'Joker zurückgenommen.',
      ),
    );
  }

  void _onShowHint(ShowHintEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    if (!game.mayChangeHints ||
        round.question?.id != event.questionId ||
        round.shownHintCount != event.shownHints ||
        round.nextHint == null) {
      emit(state.copyWith(notice: 'Gerade kann kein Tipp gezeigt werden.'));
      return;
    }
    emit(
      _publish(
        game.copyWith(
          round: round.copyWith(
            hintTimesMicros: [...round.hintTimesMicros, _now()],
          ),
          // Media paused before belongs to the question, not to the hint.
          tvMediaPaused:
              round.nextHint!.media.any(
                (m) => m is AudioAttachment || m is VideoAttachment,
              )
              ? false
              : null,
        ),
        notice: 'Tipp wird gezeigt.',
      ),
    );
  }

  void _onTakeBackHint(TakeBackHintEvent event, Emitter<QuizEngineState> emit) {
    final game = state.game;
    final round = game.round;
    if (!game.mayTakeBackHint ||
        round.question?.id != event.questionId ||
        round.shownHintCount != event.shownHints) {
      emit(
        state.copyWith(notice: 'Der Tipp kann nicht zurückgenommen werden.'),
      );
      return;
    }
    emit(
      _publish(
        game.copyWith(
          round: round.copyWith(
            hintTimesMicros: round.hintTimesMicros.sublist(
              0,
              round.shownHintCount - 1,
            ),
          ),
        ),
        notice: 'Tipp zurückgenommen.',
      ),
    );
  }

  GameState _settlePoker(GameState game, String teamId, bool correct) {
    final poker = game.poker!;
    if (poker.settledTeamIds.contains(teamId)) return game;
    final payout = pokerSettlement(
      wager: poker.wagers[teamId] ?? 0,
      isCorrect: correct,
      covering: game.jokers?.coveringJoker(teamId),
    );
    final balance = (poker.chips[teamId] ?? 0) + payout;
    return game.copyWith(
      poker: poker.copyWith(
        chips: {...poker.chips, teamId: balance < 0 ? 0 : balance},
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

/// The answers are closed, drafts under way may still arrive.
final class _DraftWait {
  const _DraftWait({
    required this.questionId,
    required this.startedAt,
    required this.endMicros,
    required this.resume,
  });

  final String questionId;
  final int startedAt;

  /// Only drafts from before this host instant count.
  final int endMicros;

  /// What closed the answers and goes on after the wait.
  final QuizEngineEvent resume;
}
