import 'package:equatable/equatable.dart';

import 'json.dart';

final class PokerState extends Equatable {
  const PokerState({
    required this.startingChips,
    this.chips = const {},
    this.wagers = const {},
    this.settledTeamIds = const {},
    this.betting = false,
  });

  factory PokerState.start(int startingChips, Iterable<String> teams) =>
      PokerState(
        startingChips: startingChips,
        chips: {for (final id in teams) id: startingChips},
      );

  factory PokerState.fromJson(JsonMap json) => PokerState(
    startingChips: json.readInt('startingChips'),
    chips: json.readIntMap('chips'),
    wagers: json.readIntMap('wagers'),
    settledTeamIds: json.readStringList('settledTeamIds').toSet(),
    betting: json.readBool('betting'),
  );

  final int startingChips;
  final Map<String, int> chips;
  final Map<String, int> wagers;
  final Set<String> settledTeamIds;
  final bool betting;

  PokerState copyWith({
    Map<String, int>? chips,
    Map<String, int>? wagers,
    Set<String>? settledTeamIds,
    bool? betting,
  }) => PokerState(
    startingChips: startingChips,
    chips: chips ?? this.chips,
    wagers: wagers ?? this.wagers,
    settledTeamIds: settledTeamIds ?? this.settledTeamIds,
    betting: betting ?? this.betting,
  );

  JsonMap toJson() => {
    'startingChips': startingChips,
    'chips': chips,
    'wagers': wagers,
    'settledTeamIds': settledTeamIds.toList(),
    'betting': betting,
  };

  @override
  List<Object?> get props => [
    startingChips,
    chips,
    wagers,
    settledTeamIds,
    betting,
  ];
}
