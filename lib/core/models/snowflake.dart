/// Rules of the "Biggest Snowflake" format.
///
/// The format has no stored solutions: the rarest answer of a round wins.
library;

import 'json.dart';

/// Who scores in a "Biggest Snowflake" round.
enum SnowflakeScoring {
  /// Only the players with the rarest answer score.
  winnerOnly,

  /// The share falls with every step of falling uniqueness; the most common
  /// answer scores nothing.
  graded;

  /// Restores the rule from its serialized name.
  static SnowflakeScoring fromName(String name) =>
      SnowflakeScoring.values.firstWhere(
        (scoring) => scoring.name == name,
        orElse: () =>
            throw JsonContractException('Unknown snowflake scoring "$name".'),
      );
}

/// One distinct answer of a round and the players who gave it.
final class SnowflakeGroup {
  /// Creates a group.
  const SnowflakeGroup({
    required this.key,
    required this.playerIds,
    required this.share,
  });

  /// Canonical answer key (`Question.uniquenessKey`).
  final String key;

  /// Players who gave this answer, in submission order.
  final List<String> playerIds;

  /// Fraction of the points this answer earns, from `0` to `1`.
  final double share;
}
