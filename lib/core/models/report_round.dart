import 'package:equatable/equatable.dart';

import 'answer.dart';
import 'json.dart';
import 'player.dart';
import 'round.dart';

final class ReportRound extends Equatable {
  const ReportRound({
    required this.round,
    required this.players,
    required this.teamNames,
    required this.eligiblePlayerIds,
    required this.disconnectedPlayerIds,
    required this.presses,
    required this.playerScores,
    required this.chips,
    required this.wagers,
    required this.practiceTeamIds,
    required this.isSteal,
    required this.isDailyDouble,
    required this.pointsAtStake,
  });

  factory ReportRound.fromJson(JsonMap json) => ReportRound(
    round: RoundState.fromJson(json.readObject('round')),
    players: json.readMap('players', Player.fromJson),
    teamNames: readStringMap(json, 'teamNames'),
    eligiblePlayerIds: json.readStringList('eligiblePlayerIds').toSet(),
    disconnectedPlayerIds: json.readStringList('disconnectedPlayerIds').toSet(),
    presses: json.readMap('presses', BuzzerPress.fromJson),
    playerScores: json.readIntMap('playerScores'),
    chips: json.readIntMap('chips'),
    wagers: json.readIntMap('wagers'),
    practiceTeamIds: json.readStringList('practiceTeamIds').toSet(),
    isSteal: json.readBool('isSteal'),
    isDailyDouble: json.readBool('isDailyDouble'),
    pointsAtStake: json.readIntOrNull('pointsAtStake'),
  );

  final RoundState round;
  final Map<String, Player> players;
  final Map<String, String> teamNames;
  final Set<String> eligiblePlayerIds;
  final Set<String> disconnectedPlayerIds;
  final Map<String, BuzzerPress> presses;
  final Map<String, int> playerScores;
  final Map<String, int> chips;
  final Map<String, int> wagers;
  final Set<String> practiceTeamIds;
  final bool isSteal;
  final bool isDailyDouble;
  final int? pointsAtStake;

  ReportRound withRound(
    RoundState value, {
    Map<String, BuzzerPress>? presses,
  }) => ReportRound(
    round: value,
    players: players,
    teamNames: teamNames,
    eligiblePlayerIds: eligiblePlayerIds,
    disconnectedPlayerIds: disconnectedPlayerIds,
    presses: presses ?? this.presses,
    playerScores: playerScores,
    chips: chips,
    wagers: wagers,
    practiceTeamIds: practiceTeamIds,
    isSteal: isSteal,
    isDailyDouble: isDailyDouble,
    pointsAtStake: pointsAtStake,
  );

  JsonMap toJson() => {
    'round': round.toJson(),
    'players': players.map((id, player) => MapEntry(id, player.toJson())),
    'teamNames': teamNames,
    'eligiblePlayerIds': eligiblePlayerIds.toList(),
    'disconnectedPlayerIds': disconnectedPlayerIds.toList(),
    'presses': presses.map((id, press) => MapEntry(id, press.toJson())),
    'playerScores': playerScores,
    'chips': chips,
    'wagers': wagers,
    'practiceTeamIds': practiceTeamIds.toList(),
    'isSteal': isSteal,
    'isDailyDouble': isDailyDouble,
    'pointsAtStake': pointsAtStake,
  };

  @override
  List<Object?> get props => [
    round,
    players,
    teamNames,
    eligiblePlayerIds,
    disconnectedPlayerIds,
    presses,
    playerScores,
    chips,
    wagers,
    practiceTeamIds,
    isSteal,
    isDailyDouble,
    pointsAtStake,
  ];
}
