import 'package:equatable/equatable.dart';

import 'answer.dart';
import 'game_state.dart';
import 'json.dart';

/// What one player may know about the answers of the round on stage before
/// the reveal: their own and those of their team.
///
/// Snapshots are the same for all guests and withhold every answer, so this
/// travels separately to each player (`GameSnapshotMessage.answers`).
final class PlayerAnswers extends Equatable {
  const PlayerAnswers({
    this.own,
    this.valid,
    this.team = const [],
    this.isFinal = false,
  });

  factory PlayerAnswers.fromJson(JsonMap json) => PlayerAnswers(
    own: switch (json.readObjectOrNull('own')) {
      final value? => AnswerSubmission.fromJson(value),
      null => null,
    },
    valid: switch (json.readObjectOrNull('valid')) {
      final value? => AnswerSubmission.fromJson(value),
      null => null,
    },
    team: json['team'] == null
        ? const []
        : json.readList('team', AnswerSubmission.fromJson),
    isFinal: json.readBool('isFinal', orElse: false),
  );

  /// The last answer this player sent in the round.
  final AnswerSubmission? own;

  /// The answer that counts: the last one of the team, or [own] for a player
  /// who answers alone.
  final AnswerSubmission? valid;

  /// The last answer of every member, only when the team shares one answer.
  final List<AnswerSubmission> team;

  /// Whether the host judged [valid] already, so it cannot be replaced.
  final bool isFinal;

  JsonMap toJson() => {
    if (own != null) 'own': own!.toJson(),
    if (valid != null) 'valid': valid!.toJson(),
    if (team.isNotEmpty) 'team': [for (final answer in team) answer.toJson()],
    if (isFinal) 'isFinal': true,
  };

  @override
  List<Object?> get props => [own, valid, team, isFinal];
}

/// The answers of the round on stage that [playerId] may see in [game], the
/// host's full state.
PlayerAnswers playerAnswersOf(GameState game, String playerId) {
  final round = game.round;
  final own = round.lastSubmissionOf(playerId);
  final teamId = game.sharedAnswerTeamOf(playerId);
  if (teamId == null) return PlayerAnswers(own: own, valid: own);
  final valid = game.teamAnswerOf(teamId);
  return PlayerAnswers(
    own: own,
    valid: valid,
    team: [
      for (final member in game.players.values)
        if (member.teamId == teamId) ?round.lastSubmissionOf(member.id),
    ],
    isFinal: valid != null && round.answerVerdicts.containsKey(valid.playerId),
  );
}
