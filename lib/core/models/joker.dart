/// Jokers: one-off helps a team may play once per game (quiz schema 12).
///
/// Whether a quiz has jokers, and which, is decided when the quiz is created;
/// a quiz without entries has none. Each kind states the formats it can be
/// played in ([Joker.isSupportedBy]); format code never names concrete kinds.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';
import 'quiz_format.dart';

/// Base type of every joker a quiz can offer.
sealed class Joker extends Equatable {
  /// Const constructor for the sealed hierarchy.
  const Joker({this.usesPerTeam = 1});

  /// How often every team may play this joker in one game.
  final int usesPerTeam;

  /// Stable identifier inside a quiz; one joker per kind.
  String get id;

  /// Whether the joker is aimed at another team.
  bool get needsTarget;

  /// Whether the joker is played after the category is announced but before
  /// the question is revealed. A poker session with such a joker announces
  /// the category of every question first (`PokerState.questionHidden`).
  bool get beforeReveal;

  /// Whether this joker can be played in [format].
  bool isSupportedBy(QuizFormat format);

  /// Serializes the joker including its configuration.
  JsonMap toJson();

  /// Problems of the configuration in [format]; empty when it is valid.
  List<String> validationErrors(QuizFormat format) => [
    if (!isSupportedBy(format))
      'Der Joker "$id" ist im Format ${format.label} nicht spielbar.',
    if (usesPerTeam < 1 || usesPerTeam > 99)
      'Ein Joker muss 1 bis 99 Mal pro Team einsetzbar sein.',
  ];

  /// Restores a joker from [json].
  ///
  /// Deserialization boundary: the only place that maps wire tags to types.
  static Joker fromJson(JsonMap json) => switch (json.readString('type')) {
    CreditJoker._type => CreditJoker(
      usesPerTeam: json.readIntOrNull('usesPerTeam') ?? 1,
      maxLoss: json.readInt('maxLoss'),
    ),
    ForcedStakeJoker._type => ForcedStakeJoker(
      usesPerTeam: json.readIntOrNull('usesPerTeam') ?? 1,
      stake: json.readInt('stake'),
      cost: json.readInt('cost'),
      lossFactor: json.readInt('lossFactor'),
    ),
    final unknown => throw JsonContractException('Unknown joker "$unknown".'),
  };
}

/// Defensive poker joker "Kredit": if the stake is lost, the bank carries the
/// loss except for [maxLoss] chips.
///
/// Played once the question is revealed, while the betting is open.
final class CreditJoker extends Joker {
  /// Creates the credit joker.
  const CreditJoker({super.usesPerTeam, this.maxLoss = 1});

  static const String _type = 'credit';

  /// Chips the team loses at most when its answer is wrong.
  final int maxLoss;

  @override
  String get id => _type;

  @override
  bool get needsTarget => false;

  @override
  bool get beforeReveal => false;

  @override
  bool isSupportedBy(QuizFormat format) => switch (format) {
    PokerFormat() => true,
    StandardFormat() || JeopardyFormat() || SnowflakeFormat() => false,
  };

  @override
  List<String> validationErrors(QuizFormat format) => [
    ...super.validationErrors(format),
    if (maxLoss < 0) 'Der Kredit-Joker braucht einen Restverlust ab 0.',
  ];

  @override
  JsonMap toJson() => {
    'type': _type,
    'usesPerTeam': usesPerTeam,
    'maxLoss': maxLoss,
  };

  @override
  List<Object?> get props => [usesPerTeam, maxLoss];
}

/// Aggressive poker joker "Zwangseinsatz": forces another team to bet [stake].
///
/// The attacker pays [cost] chips. A correct answer of the target pays as
/// usual (twice the stake back); a miss costs [lossFactor] times the stake.
/// Played after the category is announced and before the question is
/// revealed; the target's stake is then locked.
final class ForcedStakeJoker extends Joker {
  /// Creates the forced stake joker.
  const ForcedStakeJoker({
    super.usesPerTeam,
    this.stake = 3,
    this.cost = 2,
    this.lossFactor = 2,
  });

  static const String _type = 'forcedStake';

  /// Stake the target has to bet (all-in when it has fewer chips).
  final int stake;

  /// Chips the attacker pays when playing the joker.
  final int cost;

  /// Multiple of the stake the target loses with a wrong answer.
  final int lossFactor;

  @override
  String get id => _type;

  @override
  bool get needsTarget => true;

  @override
  bool get beforeReveal => true;

  @override
  bool isSupportedBy(QuizFormat format) => switch (format) {
    PokerFormat() => true,
    StandardFormat() || JeopardyFormat() || SnowflakeFormat() => false,
  };

  @override
  List<String> validationErrors(QuizFormat format) => [
    ...super.validationErrors(format),
    if (stake < 1) 'Der Angriffs-Joker braucht einen Zwangseinsatz ab 1.',
    if (cost < 0) 'Der Angriffs-Joker darf nicht weniger als 0 Chips kosten.',
    if (lossFactor < 1 || lossFactor > 10)
      'Der Verlustfaktor des Angriffs-Jokers muss zwischen 1 und 10 liegen.',
  ];

  @override
  JsonMap toJson() => {
    'type': _type,
    'usesPerTeam': usesPerTeam,
    'stake': stake,
    'cost': cost,
    'lossFactor': lossFactor,
  };

  @override
  List<Object?> get props => [usesPerTeam, stake, cost, lossFactor];
}

/// One joker played in the question on stage.
final class JokerPlay extends Equatable {
  /// Creates a record of [teamId] playing [jokerId] (on [targetTeamId]).
  const JokerPlay({
    required this.jokerId,
    required this.teamId,
    this.targetTeamId,
    this.paidChips = 0,
  });

  /// Restores a play from [json].
  factory JokerPlay.fromJson(JsonMap json) => JokerPlay(
    jokerId: json.readString('jokerId'),
    teamId: json.readString('teamId'),
    targetTeamId: json.readStringOrNull('targetTeamId'),
    paidChips: json.readIntOrNull('paidChips') ?? 0,
  );

  /// Played joker.
  final String jokerId;

  /// Team that played it.
  final String teamId;

  /// Team it is aimed at, if the joker needs one.
  final String? targetTeamId;

  /// Chips the playing team paid; refunded when the question is cancelled.
  final int paidChips;

  /// Teams this play covers: the player and its target.
  Set<String> get teamIds => {teamId, ?targetTeamId};

  /// Serializes the play.
  JsonMap toJson() => {
    'jokerId': jokerId,
    'teamId': teamId,
    if (targetTeamId != null) 'targetTeamId': targetTeamId,
    'paidChips': paidChips,
  };

  @override
  List<Object?> get props => [jokerId, teamId, targetTeamId, paidChips];
}

/// Live bookkeeping of the jokers of a session.
final class JokerState extends Equatable {
  /// Creates the joker state.
  const JokerState({
    required this.jokers,
    this.used = const {},
    this.plays = const [],
  });

  /// Restores the state from [json].
  factory JokerState.fromJson(JsonMap json) => JokerState(
    jokers: json.readList('jokers', Joker.fromJson),
    used: {
      for (final entry in json.readObject('used').entries)
        entry.key: (entry.value! as Map<String, Object?>).map(
          (key, value) => MapEntry(key, (value! as num).toInt()),
        ),
    },
    plays: json.readList('plays', JokerPlay.fromJson),
  );

  /// Jokers of the quiz.
  final List<Joker> jokers;

  /// Uses so far: team id → joker id → count.
  final Map<String, Map<String, int>> used;

  /// Jokers played in the question on stage.
  final List<JokerPlay> plays;

  /// The joker with [id], or `null`.
  Joker? jokerById(String id) =>
      jokers.where((joker) => joker.id == id).firstOrNull;

  /// How often [teamId] may still play [joker].
  int remainingFor(String teamId, Joker joker) =>
      joker.usesPerTeam - (used[teamId]?[joker.id] ?? 0);

  /// Whether [teamId] already takes part in a joker of this question.
  bool involves(String teamId) =>
      plays.any((play) => play.teamIds.contains(teamId));

  /// The joker that covers [teamId] in this question: one it played itself
  /// (e.g. a credit) or one aimed at it (a forced stake), else `null`.
  ///
  /// A team takes part in one joker per question at most ([involves]).
  Joker? coveringJoker(String teamId) {
    for (final play in plays) {
      final joker = jokerById(play.jokerId);
      if (joker == null) continue;
      if (joker.needsTarget
          ? play.targetTeamId == teamId
          : play.teamId == teamId) {
        return joker;
      }
    }
    return null;
  }

  /// The play aimed at [teamId] in this question, if any.
  JokerPlay? playAimedAt(String teamId) =>
      plays.where((play) => play.targetTeamId == teamId).firstOrNull;

  /// Returns a copy with selected fields replaced.
  JokerState copyWith({
    Map<String, Map<String, int>>? used,
    List<JokerPlay>? plays,
  }) => JokerState(
    jokers: jokers,
    used: used ?? this.used,
    plays: plays ?? this.plays,
  );

  /// Books [play] as one use of its joker.
  JokerState withPlay(JokerPlay play) => copyWith(
    used: {
      ...used,
      play.teamId: {
        ...?used[play.teamId],
        play.jokerId: (used[play.teamId]?[play.jokerId] ?? 0) + 1,
      },
    },
    plays: [...plays, play],
  );

  /// Takes [play] back, including its use.
  JokerState withoutPlay(JokerPlay play) => copyWith(
    used: {
      ...used,
      play.teamId: {
        ...?used[play.teamId],
        play.jokerId: (used[play.teamId]?[play.jokerId] ?? 1) - 1,
      },
    },
    plays: [...plays]..remove(play),
  );

  /// Serializes the state.
  JsonMap toJson() => {
    'jokers': jokers.map((joker) => joker.toJson()).toList(growable: false),
    'used': used,
    'plays': plays.map((play) => play.toJson()).toList(growable: false),
  };

  @override
  List<Object?> get props => [jokers, used, plays];
}
