/// The aggregate session state that the host owns and broadcasts.
library;

import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';
import 'player.dart';
import 'poker.dart';
import 'question.dart';
import 'round.dart';
import 'quiz_format.dart';
import 'score.dart';
import 'team.dart';

const Object _unset = Object();

/// How participants compete against each other.
///
/// Modelled as a union so that a future `RelayMode` or `TournamentMode` can
/// carry its own configuration without widening a shared settings bag.
sealed class GameMode extends Equatable {
  /// Const constructor so modes can be used as default values.
  const GameMode();

  /// Display label for the host dashboard.
  String get label;

  /// Serializes the mode.
  JsonMap toJson();

  /// Restores a mode from [json].
  static GameMode fromJson(JsonMap json) => switch (json.readString('mode')) {
    SoloMode._mode => const SoloMode(),
    TeamMode._mode => TeamMode(
      sharedBuzzer: json.readBool('sharedBuzzer', orElse: true),
    ),
    final unknown => throw JsonContractException(
      'Unknown game mode "$unknown".',
    ),
  };
}

/// Every player scores for themselves.
final class SoloMode extends GameMode {
  /// Creates the solo mode.
  const SoloMode();

  static const String _mode = 'solo';

  @override
  String get label => 'Solo';

  @override
  JsonMap toJson() => const {'mode': _mode};

  @override
  List<Object?> get props => const [];
}

/// Players score for their team.
final class TeamMode extends GameMode {
  /// Creates the team mode.
  const TeamMode({this.sharedBuzzer = true});

  static const String _mode = 'team';

  /// Whether one buzzer press locks the whole team out of a second attempt.
  final bool sharedBuzzer;

  @override
  String get label => 'Teams';

  @override
  JsonMap toJson() => {'mode': _mode, 'sharedBuzzer': sharedBuzzer};

  @override
  List<Object?> get props => [sharedBuzzer];
}

/// The complete, serializable snapshot of a hosted session.
///
/// The very same type travels over the web socket; the player facing copy is
/// produced by [redactedForPlayers] so that clients can never read the solution
/// out of their own network tab.
final class GameState extends Equatable {
  /// Creates a session snapshot.
  const GameState({
    this.mode = const SoloMode(),
    this.players = const {},
    this.playerOrder = const [],
    this.teams = const {},
    this.scores = const ScoreState(),
    this.round = RoundState.idle,
    this.questionBank = const [],
    this.totalQuestionCount = 0,
    this.completedQuestionIds = const {},
    this.jeopardy,
    this.poker,
    this.hostTimeMicros = 0,
    this.tvMediaPaused = false,
    this.tvMediaRevision = 0,
    this.tvMediaCommandRevision = 0,
    this.allAnswersRevision = 0,
    this.isFinished = false,
    this.isStarted = false,
    this.revealMode = SolutionRevealMode.afterEachQuestion,
    this.roundHistory = const [],
    this.recoveryPaused = false,
  });

  /// Restores a snapshot from [json].
  factory GameState.fromJson(JsonMap json) => GameState(
    recoveryPaused: json.readBool('recoveryPaused'),
    allAnswersRevision: json['allAnswersRevision'] == null
        ? 0
        : json.readInt('allAnswersRevision'),
    isFinished: json.readBool('isFinished', orElse: false),
    isStarted: json.readBool('isStarted'),
    revealMode: SolutionRevealMode.fromName(
      json.readStringOrNull('revealMode') ?? 'afterEachQuestion',
    ),
    roundHistory: json['roundHistory'] == null
        ? const []
        : json.readList('roundHistory', RoundState.fromJson),
    mode: GameMode.fromJson(json.readObject('mode')),
    players: json.readMap('players', Player.fromJson),
    playerOrder: json['playerOrder'] == null
        ? const []
        : json.readStringList('playerOrder'),
    teams: json.readMap('teams', Team.fromJson),
    scores: ScoreState.fromJson(json.readObject('scores')),
    round: RoundState.fromJson(json.readObject('round')),
    questionBank: json.readList('questionBank', Question.fromJson),
    totalQuestionCount: json['totalQuestionCount'] == null
        ? 0
        : json.readInt('totalQuestionCount'),
    completedQuestionIds: json.readStringList('completedQuestionIds').toSet(),
    jeopardy: switch (json.readObjectOrNull('jeopardy')) {
      final JsonMap value => JeopardyState.fromJson(value),
      null => null,
    },
    poker: switch (json.readObjectOrNull('poker')) {
      final JsonMap value => PokerState.fromJson(value),
      null => null,
    },
    hostTimeMicros: json.readInt('hostTimeMicros'),
    tvMediaPaused: json.readBool('tvMediaPaused', orElse: false),
    tvMediaRevision: json['tvMediaRevision'] == null
        ? 0
        : json.readInt('tvMediaRevision'),
    tvMediaCommandRevision: json['tvMediaCommandRevision'] == null
        ? 0
        : json.readInt('tvMediaCommandRevision'),
  );

  /// Active competition mode.
  final GameMode mode;

  /// Connected and previously connected players, keyed by id.
  final Map<String, Player> players;
  final List<String> playerOrder;

  List<String> get orderedPlayerIds => [
    ...playerOrder.where(players.containsKey),
    ...players.keys.where((id) => !playerOrder.contains(id)),
  ];
  String? participantId(Player? player) =>
      mode is TeamMode ? player?.teamId : player?.id;
  String? participantName(String? id) =>
      mode is TeamMode ? teams[id]?.name : players[id]?.name;
  List<String> get participantIds => mode is TeamMode
      ? {
          ...orderedPlayerIds
              .map((id) => players[id]!.teamId)
              .whereType<String>(),
          ...teams.keys,
        }.toList()
      : orderedPlayerIds;
  List<String> get selectionOrder => [
    ...?jeopardy?.turnOrder.where(participantIds.contains),
    ...participantIds.where(
      (id) => !(jeopardy?.turnOrder.contains(id) ?? false),
    ),
  ];
  bool mayPickQuestion(String? playerId) {
    final player = players[playerId];
    return !recoveryPaused &&
        isStarted &&
        player != null &&
        player.isConnected &&
        jeopardy?.currentTeamId != null &&
        participantId(player) == jeopardy?.currentTeamId;
  }

  bool mayAnswerQuestion(String? playerId) =>
      !recoveryPaused &&
      (round.buzzerOpenForAll ||
          (jeopardy?.mayAnswer(participantId(players[playerId])) ?? true));

  /// Configured teams, keyed by id.
  final Map<String, Team> teams;

  /// Current score board.
  final ScoreState scores;

  /// The round on stage.
  final RoundState round;

  /// All questions of the session; empty in player facing snapshots.
  final List<Question> questionBank;

  final int totalQuestionCount;

  /// Questions that were already revealed.
  final Set<String> completedQuestionIds;

  /// Board bookkeeping when the session plays a Jeopardy quiz, else `null`.
  final JeopardyState? jeopardy;

  final PokerState? poker;

  /// Host wall clock at the moment the snapshot was produced.
  ///
  /// Clients use it as a coarse freshness check and as a fallback when their
  /// own sync handshake has not completed yet.
  final int hostTimeMicros;
  final bool tvMediaPaused;
  final int tvMediaRevision;
  final int tvMediaCommandRevision;
  final int allAnswersRevision;
  final bool isFinished;
  final bool isStarted;

  /// Timing of guest-visible results for a standard quiz.
  final SolutionRevealMode revealMode;

  /// Completed rounds retained for the final solution overview.
  final List<RoundState> roundHistory;
  final bool recoveryPaused;

  /// Whether guests must not yet receive solutions, verdicts or standings.
  bool get resultsHidden =>
      revealMode == SolutionRevealMode.atEnd && !isFinished;

  /// Whether the final solution overview is available to players and TVs.
  bool get showFinalReview =>
      revealMode == SolutionRevealMode.atEnd &&
      isFinished &&
      roundHistory.isNotEmpty;

  Map<String, String> get questionWinners {
    final winners = <String, Set<String>>{};
    for (final entry in scores.history) {
      if (entry.points <= 0 ||
          !completedQuestionIds.contains(entry.questionId)) {
        continue;
      }
      final player = players[entry.playerId];
      final name =
          (mode is TeamMode ? teams[player?.teamId]?.name : null) ??
          player?.name ??
          entry.playerId;
      (winners[entry.questionId] ??= {}).add(name);
    }
    return winners.map((id, names) => MapEntry(id, names.join(", ")));
  }

  /// Players with an open socket.
  List<Player> get connectedPlayers => players.values
      .where((player) => player.isConnected)
      .toList(growable: false);

  /// The player that currently holds the floor.
  Player? get activePlayer {
    final id = round.activePlayerId;
    return id == null ? null : players[id];
  }

  /// Team of [activePlayer], if the session runs in team mode.
  Team? get activeTeam {
    final teamId = activePlayer?.teamId;
    return teamId == null ? null : teams[teamId];
  }

  /// Team totals derived from the player totals.
  Map<String, int> get teamScores =>
      poker?.chips ?? scores.teamTotals(players.values);

  /// Returns the question with [id], or `null` when it is not in the bank.
  Question? questionById(String id) {
    for (final question in questionBank) {
      if (question.id == id) return question;
    }
    return null;
  }

  /// The first question that has not been revealed yet.
  Question? get nextPendingQuestion {
    for (final question in questionBank) {
      if (!completedQuestionIds.contains(question.id)) return question;
    }
    return null;
  }

  /// Returns a copy that is safe to hand to a player client.
  ///
  /// Always strips the upcoming bank and host notes. In deferred mode, also
  /// withholds solutions, verdicts, standings and archived rounds until the
  /// quiz is finished; otherwise each round reveals its solution immediately.
  GameState redactedForPlayers({bool includeMediaData = false}) {
    final question = round.question;
    final keepSolution = round.status == RoundStatus.revealed && !resultsHidden;
    return copyWith(
      questionBank: const [],
      totalQuestionCount: questionBank.isEmpty
          ? totalQuestionCount
          : questionBank.length,
      jeopardy: jeopardy?.redacted(),
      scores: resultsHidden ? const ScoreState() : scores,
      roundHistory: showFinalReview
          ? [
              for (final completed in roundHistory)
                completed.copyWith(
                  question: completed.question?.forWire(
                    reveal: true,
                    includeMediaData: includeMediaData,
                  ),
                ),
            ]
          : const [],
      round: round.copyWith(
        status: resultsHidden && round.status == RoundStatus.revealed
            ? RoundStatus.locked
            : round.status,
        question: question?.forWire(
          reveal: keepSolution,
          includeMediaData: includeMediaData,
        ),
        answers: poker != null && !keepSolution ? const {} : round.answers,
        acceptedElapsedMicros: poker != null && !keepSolution
            ? const {}
            : round.acceptedElapsedMicros,
        answerVerdicts: keepSolution ? round.answerVerdicts : const {},
        buzzerVerdicts: resultsHidden ? const {} : round.buzzerVerdicts,
        buzzerAnswerCorrect: resultsHidden ? false : round.buzzerAnswerCorrect,
      ),
    );
  }

  /// Returns a copy with the given fields replaced.
  GameState copyWith({
    GameMode? mode,
    Map<String, Player>? players,
    List<String>? playerOrder,
    Map<String, Team>? teams,
    ScoreState? scores,
    RoundState? round,
    List<Question>? questionBank,
    int? totalQuestionCount,
    Set<String>? completedQuestionIds,
    Object? jeopardy = _unset,
    Object? poker = _unset,
    Object? hostTimeMicros = _unset,
    bool? tvMediaPaused,
    int? tvMediaRevision,
    int? tvMediaCommandRevision,
    int? allAnswersRevision,
    bool? isFinished,
    bool? isStarted,
    SolutionRevealMode? revealMode,
    List<RoundState>? roundHistory,
    bool? recoveryPaused,
  }) => GameState(
    mode: mode ?? this.mode,
    players: players ?? this.players,
    playerOrder: playerOrder ?? this.playerOrder,
    teams: teams ?? this.teams,
    scores: scores ?? this.scores,
    round: round ?? this.round,
    questionBank: questionBank ?? this.questionBank,
    totalQuestionCount: totalQuestionCount ?? this.totalQuestionCount,
    completedQuestionIds: completedQuestionIds ?? this.completedQuestionIds,
    jeopardy: identical(jeopardy, _unset)
        ? this.jeopardy
        : jeopardy as JeopardyState?,
    poker: identical(poker, _unset) ? this.poker : poker as PokerState?,
    tvMediaPaused: tvMediaPaused ?? this.tvMediaPaused,
    tvMediaRevision: tvMediaRevision ?? this.tvMediaRevision,
    tvMediaCommandRevision:
        tvMediaCommandRevision ?? this.tvMediaCommandRevision,
    allAnswersRevision: allAnswersRevision ?? this.allAnswersRevision,
    isFinished: isFinished ?? this.isFinished,
    isStarted: isStarted ?? this.isStarted,
    revealMode: revealMode ?? this.revealMode,
    roundHistory: roundHistory ?? this.roundHistory,
    recoveryPaused: recoveryPaused ?? this.recoveryPaused,
    hostTimeMicros: identical(hostTimeMicros, _unset)
        ? this.hostTimeMicros
        : hostTimeMicros as int,
  );

  /// Serializes the snapshot.
  JsonMap toJson() => {
    'mode': mode.toJson(),
    'players': players.map((key, value) => MapEntry(key, value.toJson())),
    'playerOrder': playerOrder,
    'teams': teams.map((key, value) => MapEntry(key, value.toJson())),
    'scores': scores.toJson(),
    'round': round.toJson(),
    'questionBank': questionBank
        .map((question) => question.toJson())
        .toList(growable: false),
    'totalQuestionCount': totalQuestionCount,
    'completedQuestionIds': completedQuestionIds.toList(growable: false),
    'jeopardy': jeopardy?.toJson(),
    'poker': poker?.toJson(),
    'hostTimeMicros': hostTimeMicros,
    'tvMediaPaused': tvMediaPaused,
    'tvMediaRevision': tvMediaRevision,
    'tvMediaCommandRevision': tvMediaCommandRevision,
    'allAnswersRevision': allAnswersRevision,
    'isFinished': isFinished,
    'isStarted': isStarted,
    'revealMode': revealMode.name,
    'roundHistory': roundHistory.map((round) => round.toJson()).toList(),
    'recoveryPaused': recoveryPaused,
  };

  @override
  List<Object?> get props => [
    mode,
    players,
    playerOrder,
    teams,
    scores,
    round,
    questionBank,
    totalQuestionCount,
    completedQuestionIds,
    jeopardy,
    poker,
    hostTimeMicros,
    tvMediaPaused,
    tvMediaRevision,
    tvMediaCommandRevision,
    allAnswersRevision,
    isFinished,
    isStarted,
    revealMode,
    roundHistory,
    recoveryPaused,
  ];
}
