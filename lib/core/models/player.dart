/// The [Player] model: one connected client of the hosted session.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

const Object _unset = Object();

/// A single connected client.
///
/// The host keeps the measured clock quality per player so the dashboard can
/// show who is trustworthy for fast buzzer rounds.
final class Player extends Equatable {
  /// Creates a player.
  const Player({
    required this.id,
    required this.name,
    this.teamId,
    this.isConnected = true,
    this.clockOffsetMicros = 0,
    this.roundTripMicros = 0,
  });

  /// Restores a player from [json].
  factory Player.fromJson(JsonMap json) => Player(
    id: json.readString('id'),
    name: json.readString('name'),
    teamId: json.readStringOrNull('teamId'),
    isConnected: json.readBool('isConnected', orElse: true),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    roundTripMicros: json.readInt('roundTripMicros'),
  );

  /// Server assigned identifier, stable across reconnects.
  final String id;

  /// Display name chosen on the join screen.
  final String name;

  /// Team this player scores for, or `null` in solo mode.
  final String? teamId;

  /// Whether the web socket is currently open.
  final bool isConnected;

  /// How far this client's clock runs ahead of the host clock.
  final int clockOffsetMicros;

  /// Round trip time of the best sync probe.
  final int roundTripMicros;

  /// Estimated one way latency between this client and the host.
  Duration get latency =>
      Duration(microseconds: roundTripMicros ~/ 2);

  /// Whether the client completed at least one clock handshake.
  bool get isClockSynced => roundTripMicros > 0;

  /// Returns a copy with the given fields replaced.
  Player copyWith({
    String? name,
    Object? teamId = _unset,
    bool? isConnected,
    int? clockOffsetMicros,
    int? roundTripMicros,
  }) => Player(
    id: id,
    name: name ?? this.name,
    teamId: identical(teamId, _unset) ? this.teamId : teamId as String?,
    isConnected: isConnected ?? this.isConnected,
    clockOffsetMicros: clockOffsetMicros ?? this.clockOffsetMicros,
    roundTripMicros: roundTripMicros ?? this.roundTripMicros,
  );

  /// Serializes the player.
  JsonMap toJson() => {
    'id': id,
    'name': name,
    'teamId': teamId,
    'isConnected': isConnected,
    'clockOffsetMicros': clockOffsetMicros,
    'roundTripMicros': roundTripMicros,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    teamId,
    isConnected,
    clockOffsetMicros,
    roundTripMicros,
  ];
}



