/// The [Team] model: a group of players that share one score.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

/// A group of players that score together.
final class Team extends Equatable {
  /// Creates a team.
  const Team({
    required this.id,
    required this.name,
    this.colorValue = 0xFF5E6AD2,
  });

  /// Restores a team from [json].
  factory Team.fromJson(JsonMap json) => Team(
    id: json.readString('id'),
    name: json.readString('name'),
    colorValue: json.readInt('colorValue'),
  );

  /// Stable identifier referenced by `Player.teamId`.
  final String id;

  /// Display name.
  final String name;

  /// 32 bit ARGB accent colour.
  ///
  /// Stored as a plain `int` so that `lib/core` stays free of `dart:ui`.
  final int colorValue;

  /// Serializes the team.
  JsonMap toJson() => {'id': id, 'name': name, 'colorValue': colorValue};

  @override
  List<Object?> get props => [id, name, colorValue];
}
