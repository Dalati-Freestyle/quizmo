/// The aggregate session state that the host owns and broadcasts.
library;

import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';
import 'player.dart';
import 'question.dart';
import 'round.dart';
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
    this.teams = const {},
    this.scores = const ScoreState(),
    this.round = RoundState.idle,
    this.questionBank = const [],
    this.completedQuestionIds = const {},
    this.jeopardy,
    this.hostTimeMicros = 0,
  });

  /// Restores a snapshot from [json].
  factory GameState.fromJson(JsonMap json) => GameState(
    mode: GameMode.fromJson(json.readObject('mode')),
    players: json.readMap('players', Player.fromJson),
    teams: json.readMap('teams', Team.fromJson),
    scores: ScoreState.fromJson(json.readObject('scores')),
    round: RoundState.fromJson(json.readObject('round')),
    questionBank: json.readList('questionBank', Question.fromJson),
    completedQuestionIds: json.readStringList('completedQuestionIds').toSet(),
    jeopardy: switch (json.readObjectOrNull('jeopardy')) {
      final JsonMap value => JeopardyState.fromJson(value),
      null => null,
    },
    hostTimeMicros: json.readInt('hostTimeMicros'),
  );

  /// Active competition mode.
  final GameMode mode;

  /// Connected and previously connected players, keyed by id.
  final Map<String, Player> players;

  /// Configured teams, keyed by id.
  final Map<String, Team> teams;

  /// Current score board.
  final ScoreState scores;

  /// The round on stage.
  final RoundState round;

  /// All questions of the session; empty in player facing snapshots.
  final List<Question> questionBank;

  /// Questions that were already revealed.
  final Set<String> completedQuestionIds;

  /// Board bookkeeping when the session plays a Jeopardy quiz, else `null`.
  final JeopardyState? jeopardy;

  /// Host wall clock at the moment the snapshot was produced.
  ///
  /// Clients use it as a coarse freshness check and as a fallback when their
  /// own sync handshake has not completed yet.
  final int hostTimeMicros;

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
  Map<String, int> get teamScores => scores.teamTotals(players.values);

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
  /// Two things are stripped: the upcoming question bank and the solution of
  /// the running round. Once the host reveals the round the solution is kept so
  /// that players can see what the right answer was.
  GameState redactedForPlayers() {
    final question = round.question;
    final keepSolution = round.status == RoundStatus.revealed;
    return copyWith(
      questionBank: const [],
      jeopardy: jeopardy?.redacted(),
      round: round.copyWith(question: question?.forWire(reveal: keepSolution)),
    );
  }

  /// Returns a copy with the given fields replaced.
  GameState copyWith({
    GameMode? mode,
    Map<String, Player>? players,
    Map<String, Team>? teams,
    ScoreState? scores,
    RoundState? round,
    List<Question>? questionBank,
    Set<String>? completedQuestionIds,
    Object? jeopardy = _unset,
    Object? hostTimeMicros = _unset,
  }) => GameState(
    mode: mode ?? this.mode,
    players: players ?? this.players,
    teams: teams ?? this.teams,
    scores: scores ?? this.scores,
    round: round ?? this.round,
    questionBank: questionBank ?? this.questionBank,
    completedQuestionIds: completedQuestionIds ?? this.completedQuestionIds,
    jeopardy: identical(jeopardy, _unset)
        ? this.jeopardy
        : jeopardy as JeopardyState?,
    hostTimeMicros: identical(hostTimeMicros, _unset)
        ? this.hostTimeMicros
        : hostTimeMicros as int,
  );

  /// Serializes the snapshot.
  JsonMap toJson() => {
    'mode': mode.toJson(),
    'players': players.map((key, value) => MapEntry(key, value.toJson())),
    'teams': teams.map((key, value) => MapEntry(key, value.toJson())),
    'scores': scores.toJson(),
    'round': round.toJson(),
    'questionBank': questionBank
        .map((question) => question.toJson())
        .toList(growable: false),
    'completedQuestionIds': completedQuestionIds.toList(growable: false),
    'jeopardy': jeopardy?.toJson(),
    'hostTimeMicros': hostTimeMicros,
  };

  @override
  List<Object?> get props => [
    mode,
    players,
    teams,
    scores,
    round,
    questionBank,
    completedQuestionIds,
    jeopardy,
    hostTimeMicros,
  ];
}
