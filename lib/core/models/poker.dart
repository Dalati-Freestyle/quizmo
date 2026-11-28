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
    this.eliminations = const {},
    this.betting = false,
    this.questionHidden = false,
    this.category,
    this.stakesBeforeReveal = false,
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

  factory PokerState.fromJson(JsonMap json) {
    final chips = json.readIntMap('chips');
    final wagers = json.readIntMap('wagers');
    final settled = json.readStringList('settledTeamIds').toSet();
    return PokerState(
      startingChips: json.readInt('startingChips'),
      // Checkpoints and snapshots of older versions have no stake limits.
      minStake: json.readIntOrNull('minStake') ?? 0,
      maxStake: json.readIntOrNull('maxStake'),
      chips: chips,
      wagers: wagers,
      settledTeamIds: settled,
      // Saved games of older versions did not record when a team went out; those
      // teams count as the first ones to leave.
      eliminations: json['eliminations'] == null
          ? {
              for (final entry in chips.entries)
                if (entry.value == 0 &&
                    (settled.contains(entry.key) ||
                        (wagers[entry.key] ?? 0) == 0))
                  entry.key: 0,
            }
          : json.readIntMap('eliminations'),
      betting: json.readBool('betting'),
      questionHidden: json.readBool('questionHidden'),
      category: json.readStringOrNull('category'),
      stakesBeforeReveal: json.readBool('stakesBeforeReveal', orElse: false),
    );
  }

  final int startingChips;

  /// Smallest stake a team with chips must place (0: sitting out is allowed).
  final int minStake;

  /// Largest stake per question, or `null` when a team may bet all its chips.
  final int? maxStake;

  final Map<String, int> chips;
  final Map<String, int> wagers;
  final Set<String> settledTeamIds;

  /// Teams that lost all their chips, with the number of the played question
  /// whose settlement (or correction) took the last ones. `0` means that the
  /// moment is unknown (saved games of older versions).
  final Map<String, int> eliminations;

  /// Chips [teamId] owns: its balance plus a stake that is still reserved.
  int ownedBy(String teamId) =>
      (chips[teamId] ?? 0) +
      (settledTeamIds.contains(teamId) ? 0 : wagers[teamId] ?? 0);

  /// A copy in which every team of [teamIds] (default: all) without chips is
  /// out since [question] and no team with chips is out. Teams that are out
  /// already keep their moment.
  PokerState withEliminations(int question, {Iterable<String>? teamIds}) {
    final updated = {...eliminations};
    for (final id in teamIds ?? chips.keys) {
      if (ownedBy(id) > 0) {
        updated.remove(id);
      } else {
        updated.putIfAbsent(id, () => question);
      }
    }
    return copyWith(eliminations: updated);
  }

  /// A copy in which no team with chips counts as eliminated.
  PokerState withReturnedTeams() => copyWith(
    eliminations: {
      for (final entry in eliminations.entries)
        if (ownedBy(entry.key) == 0) entry.key: entry.value,
    },
  );
  final bool betting;

  /// Category phase before the reveal: guests only see [category] and may
  /// play the jokers that are played before the question is known
  /// (`Joker.beforeReveal`). Always part of the betting.
  final bool questionHidden;

  /// The category phase comes from a category slide (host setting "category
  /// slide before every question"): teams bet on the category while the
  /// question is hidden, and closing the betting reveals it.
  final bool stakesBeforeReveal;

  /// Whether teams may place stakes now.
  bool get acceptsStakes => betting && (!questionHidden || stakesBeforeReveal);

  /// Category of the question on stage while [questionHidden].
  final String? category;

  PokerState copyWith({
    Map<String, int>? chips,
    Map<String, int>? wagers,
    Set<String>? settledTeamIds,
    Map<String, int>? eliminations,
    bool? betting,
    bool? questionHidden,
    Object? category = _unset,
    bool? stakesBeforeReveal,
  }) => PokerState(
    startingChips: startingChips,
    minStake: minStake,
    maxStake: maxStake,
    chips: chips ?? this.chips,
    wagers: wagers ?? this.wagers,
    settledTeamIds: settledTeamIds ?? this.settledTeamIds,
    eliminations: eliminations ?? this.eliminations,
    betting: betting ?? this.betting,
    questionHidden: questionHidden ?? this.questionHidden,
    category: identical(category, _unset) ? this.category : category as String?,
    stakesBeforeReveal: stakesBeforeReveal ?? this.stakesBeforeReveal,
  );

  /// Chips [teamId] can bet: its balance plus the stake it already reserved.
  int availableFor(String? teamId) =>
      (chips[teamId] ?? 0) + (wagers[teamId] ?? 0);

  /// Whether every team of [teamIds] that can bet (it has chips) placed a
  /// stake; `false` while no team can bet. Bankrupt teams are not waited for.
  bool allStakesIn(Iterable<String> teamIds) {
    final bettors = [
      for (final id in teamIds)
        if (availableFor(id) > 0) id,
    ];
    return bettors.isNotEmpty && bettors.every(wagers.containsKey);
  }

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
    'eliminations': eliminations,
    'betting': betting,
    if (questionHidden) 'questionHidden': true,
    if (category != null) 'category': category,
    if (stakesBeforeReveal) 'stakesBeforeReveal': true,
  };

  @override
  List<Object?> get props => [
    startingChips,
    minStake,
    maxStake,
    chips,
    wagers,
    settledTeamIds,
    eliminations,
    betting,
    questionHidden,
    category,
    stakesBeforeReveal,
  ];
}

const Object _unset = Object();
