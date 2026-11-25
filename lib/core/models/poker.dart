import 'package:equatable/equatable.dart';

import 'json.dart';

final class PokerState extends Equatable {
  const PokerState({
    required this.startingChips,
    this.minStake = 0,
    this.maxStake,
    this.chips = const {},
    this.wagers = const {},
    this.settledTeamIds = const {},
    this.betting = false,
    this.questionHidden = false,
    this.category,
  });

  factory PokerState.start(
    int startingChips,
    Iterable<String> teams, {
    int minStake = 0,
    int? maxStake,
  }) => PokerState(
    startingChips: startingChips,
    minStake: minStake,
    maxStake: maxStake,
    chips: {for (final id in teams) id: startingChips},
  );

  factory PokerState.fromJson(JsonMap json) => PokerState(
    startingChips: json.readInt('startingChips'),
    // Checkpoints and snapshots of older versions have no stake limits.
    minStake: json.readIntOrNull('minStake') ?? 0,
    maxStake: json.readIntOrNull('maxStake'),
    chips: json.readIntMap('chips'),
    wagers: json.readIntMap('wagers'),
    settledTeamIds: json.readStringList('settledTeamIds').toSet(),
    betting: json.readBool('betting'),
    questionHidden: json.readBool('questionHidden'),
    category: json.readStringOrNull('category'),
  );

  final int startingChips;

  /// Smallest stake a team with chips must place (0: sitting out is allowed).
  final int minStake;

  /// Largest stake per question, or `null` when a team may bet all its chips.
  final int? maxStake;

  final Map<String, int> chips;
  final Map<String, int> wagers;
  final Set<String> settledTeamIds;
  final bool betting;

  /// Category phase before the reveal: guests only see [category] and may
  /// play the jokers that are played before the question is known
  /// (`Joker.beforeReveal`). Always part of the betting.
  final bool questionHidden;

  /// Category of the question on stage while [questionHidden].
  final String? category;

  PokerState copyWith({
    Map<String, int>? chips,
    Map<String, int>? wagers,
    Set<String>? settledTeamIds,
    bool? betting,
    bool? questionHidden,
    Object? category = _unset,
  }) => PokerState(
    startingChips: startingChips,
    minStake: minStake,
    maxStake: maxStake,
    chips: chips ?? this.chips,
    wagers: wagers ?? this.wagers,
    settledTeamIds: settledTeamIds ?? this.settledTeamIds,
    betting: betting ?? this.betting,
    questionHidden: questionHidden ?? this.questionHidden,
    category: identical(category, _unset) ? this.category : category as String?,
  );

  /// Chips [teamId] can bet: its balance plus the stake it already reserved.
  int availableFor(String? teamId) =>
      (chips[teamId] ?? 0) + (wagers[teamId] ?? 0);

  /// The lowest stake a team with [available] chips may place.
  ///
  /// A team that has fewer chips than [minStake] has to go all-in.
  int lowestStakeFor(int available) =>
      minStake < available ? minStake : available;

  /// The highest stake a team with [available] chips may place.
  int highestStakeFor(int available) =>
      maxStake != null && maxStake! < available ? maxStake! : available;

  /// Whether a team with [available] chips may bet [stake].
  bool allowsStake(int stake, int available) =>
      stake >= lowestStakeFor(available) && stake <= highestStakeFor(available);

  JsonMap toJson() => {
    'startingChips': startingChips,
    'minStake': minStake,
    if (maxStake != null) 'maxStake': maxStake,
    'chips': chips,
    'wagers': wagers,
    'settledTeamIds': settledTeamIds.toList(),
    'betting': betting,
    if (questionHidden) 'questionHidden': true,
    if (category != null) 'category': category,
  };

  @override
  List<Object?> get props => [
    startingChips,
    minStake,
    maxStake,
    chips,
    wagers,
    settledTeamIds,
    betting,
    questionHidden,
    category,
  ];
}

const Object _unset = Object();
