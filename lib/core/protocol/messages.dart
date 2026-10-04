/// The JSON message contract shared by the embedded host and every client.
///
/// Both directions are modelled as `sealed` hierarchies, so handlers dispatch
/// with exhaustive pattern matching instead of `if (type == '...')` chains.
library;

import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../models/models.dart';

/// A message sent from a client to the embedded host.
sealed class ClientMessage extends Equatable {
  /// Const constructor for the sealed hierarchy.
  const ClientMessage();

  /// Serializes the message.
  JsonMap toJson();

  /// Encodes the message as a web socket text frame.
  String encode() => jsonEncode(toJson());

  /// Restores a message from [json].
  static ClientMessage fromJson(JsonMap json) =>
      switch (json.readString('type')) {
        JoinRequest._type => JoinRequest.fromJson(json),
        SyncPing._type => SyncPing.fromJson(json),
        ClockReport._type => ClockReport.fromJson(json),
        SubmissionMessage._type => SubmissionMessage.fromJson(json),
        WatchRequest._type => const WatchRequest(),
        'pokerWager' => PokerWagerMessage(
          questionId: json.readString('questionId'),
          wager: json.readInt('wager'),
        ),
        LeaveNotice._type => const LeaveNotice(),
        final unknown => throw JsonContractException(
          'Unknown client message "$unknown".',
        ),
      };

  /// Decodes a raw web socket frame.
  static ClientMessage decode(String raw) =>
      fromJson(jsonDecode(raw) as JsonMap);
}

/// Registers the connection as a named participant.
final class JoinRequest extends ClientMessage {
  /// Creates a join request.
  const JoinRequest({
    required this.name,
    this.teamId,
    this.resumePlayerId,
    this.clockOffsetMicros = 0,
    this.roundTripMicros = 0,
  });

  /// Restores the request from [json].
  factory JoinRequest.fromJson(JsonMap json) => JoinRequest(
    name: json.readString('name'),
    teamId: json.readStringOrNull('teamId'),
    resumePlayerId: json.readStringOrNull('resumePlayerId'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    roundTripMicros: json.readInt('roundTripMicros'),
  );

  static const String _type = 'join';

  /// Display name chosen by the participant.
  final String name;

  /// Optional team to score for.
  final String? teamId;

  /// Previously assigned player id, used to survive a reconnect.
  final String? resumePlayerId;

  /// Offset measured during the HTTP handshake.
  final int clockOffsetMicros;

  /// Round trip time of the best handshake probe.
  final int roundTripMicros;

  @override
  JsonMap toJson() => {
    'type': _type,
    'name': name,
    'teamId': teamId,
    'resumePlayerId': resumePlayerId,
    'clockOffsetMicros': clockOffsetMicros,
    'roundTripMicros': roundTripMicros,
  };

  @override
  List<Object?> get props => [
    name,
    teamId,
    resumePlayerId,
    clockOffsetMicros,
    roundTripMicros,
  ];
}

/// Re-runs the clock handshake over the already open socket.
final class SyncPing extends ClientMessage {
  /// Creates a ping stamped with the client clock.
  const SyncPing({required this.clientSentAtMicros});

  /// Restores the ping from [json].
  factory SyncPing.fromJson(JsonMap json) =>
      SyncPing(clientSentAtMicros: json.readInt('clientSentAtMicros'));

  static const String _type = 'syncPing';

  /// `t0` of the probe.
  final int clientSentAtMicros;

  @override
  JsonMap toJson() => {'type': _type, 'clientSentAtMicros': clientSentAtMicros};

  @override
  List<Object?> get props => [clientSentAtMicros];
}

/// Publishes a refreshed clock estimate to the host.
final class ClockReport extends ClientMessage {
  /// Creates a clock report.
  const ClockReport({
    required this.clockOffsetMicros,
    required this.roundTripMicros,
  });

  /// Restores the report from [json].
  factory ClockReport.fromJson(JsonMap json) => ClockReport(
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    roundTripMicros: json.readInt('roundTripMicros'),
  );

  static const String _type = 'clockReport';

  /// Current `client - host` offset.
  final int clockOffsetMicros;

  /// Round trip time backing the offset.
  final int roundTripMicros;

  @override
  JsonMap toJson() => {
    'type': _type,
    'clockOffsetMicros': clockOffsetMicros,
    'roundTripMicros': roundTripMicros,
  };

  @override
  List<Object?> get props => [clockOffsetMicros, roundTripMicros];
}

/// Carries any [AnswerSubmission] — a choice or a buzzer press.
///
/// One envelope for every submission kind keeps the protocol stable when new
/// question types are added: the payload stays polymorphic and the host simply
/// pattern matches on it.
final class SubmissionMessage extends ClientMessage {
  /// Wraps [submission] for transport.
  const SubmissionMessage(this.submission);

  /// Restores the envelope from [json].
  factory SubmissionMessage.fromJson(JsonMap json) =>
      SubmissionMessage(AnswerSubmission.fromJson(json.readObject('payload')));

  static const String _type = 'submission';

  /// The wrapped submission.
  final AnswerSubmission submission;

  @override
  JsonMap toJson() => {'type': _type, 'payload': submission.toJson()};

  @override
  List<Object?> get props => [submission];
}

/// Registers the connection as a read-only spectator, for example a TV.
///
/// A spectator is **not** a player: it creates no roster entry, needs no clock
/// handshake, cannot submit answers and only receives the redacted snapshots.
final class WatchRequest extends ClientMessage {
  /// Creates a watch request.
  const WatchRequest();

  static const String _type = 'watch';

  @override
  JsonMap toJson() => const {'type': _type};

  @override
  List<Object?> get props => const [];
}

/// Announces a graceful disconnect.
final class LeaveNotice extends ClientMessage {
  /// Creates a leave notice.
  const LeaveNotice();

  static const String _type = 'leave';

  @override
  JsonMap toJson() => const {'type': _type};

  @override
  List<Object?> get props => const [];
}

/// A message sent from the embedded host to a client.
sealed class ServerMessage extends Equatable {
  /// Const constructor for the sealed hierarchy.
  const ServerMessage();

  /// Serializes the message.
  JsonMap toJson();

  /// Encodes the message as a web socket text frame.
  String encode() => jsonEncode(toJson());

  /// Restores a message from [json].
  static ServerMessage fromJson(JsonMap json) =>
      switch (json.readString('type')) {
        WelcomeMessage._type => WelcomeMessage.fromJson(json),
        JoinAcceptedMessage._type => JoinAcceptedMessage.fromJson(json),
        WatchAcceptedMessage._type => const WatchAcceptedMessage(),
        SyncPong._type => SyncPong.fromJson(json),
        GameSnapshotMessage._type => GameSnapshotMessage.fromJson(json),
        ProtocolErrorMessage._type => ProtocolErrorMessage.fromJson(json),
        final unknown => throw JsonContractException(
          'Unknown server message "$unknown".',
        ),
      };

  /// Decodes a raw web socket frame.
  static ServerMessage decode(String raw) =>
      fromJson(jsonDecode(raw) as JsonMap);
}

/// Sent immediately after the socket upgrade, before the join handshake.
final class WelcomeMessage extends ServerMessage {
  /// Creates a welcome frame.
  const WelcomeMessage({
    required this.connectionId,
    required this.hostTimeMicros,
    required this.serverName,
  });

  /// Restores the frame from [json].
  factory WelcomeMessage.fromJson(JsonMap json) => WelcomeMessage(
    connectionId: json.readString('connectionId'),
    hostTimeMicros: json.readInt('hostTimeMicros'),
    serverName: json.readString('serverName'),
  );

  static const String _type = 'welcome';

  /// Transport level connection identifier.
  final String connectionId;

  /// Host clock at the time of the upgrade.
  final int hostTimeMicros;

  /// Friendly name of the hosting device.
  final String serverName;

  @override
  JsonMap toJson() => {
    'type': _type,
    'connectionId': connectionId,
    'hostTimeMicros': hostTimeMicros,
    'serverName': serverName,
  };

  @override
  List<Object?> get props => [connectionId, hostTimeMicros, serverName];
}

/// Confirms a [JoinRequest] and assigns the authoritative player id.
final class JoinAcceptedMessage extends ServerMessage {
  /// Creates a join confirmation.
  const JoinAcceptedMessage({
    required this.playerId,
    required this.hostTimeMicros,
  });

  /// Restores the frame from [json].
  factory JoinAcceptedMessage.fromJson(JsonMap json) => JoinAcceptedMessage(
    playerId: json.readString('playerId'),
    hostTimeMicros: json.readInt('hostTimeMicros'),
  );

  static const String _type = 'joinAccepted';

  /// Identifier every later submission is attributed to.
  final String playerId;

  /// Host clock at the time of the confirmation.
  final int hostTimeMicros;

  @override
  JsonMap toJson() => {
    'type': _type,
    'playerId': playerId,
    'hostTimeMicros': hostTimeMicros,
  };

  @override
  List<Object?> get props => [playerId, hostTimeMicros];
}

/// Confirms a [WatchRequest]; the first snapshot follows immediately.
final class WatchAcceptedMessage extends ServerMessage {
  /// Creates a watch confirmation.
  const WatchAcceptedMessage();

  static const String _type = 'watchAccepted';

  @override
  JsonMap toJson() => const {'type': _type};

  @override
  List<Object?> get props => const [];
}

/// Answers a [SyncPing] and closes one clock probe.
final class SyncPong extends ServerMessage {
  /// Creates a pong frame.
  const SyncPong({
    required this.clientSentAtMicros,
    required this.hostTimeMicros,
  });

  /// Restores the frame from [json].
  factory SyncPong.fromJson(JsonMap json) => SyncPong(
    clientSentAtMicros: json.readInt('clientSentAtMicros'),
    hostTimeMicros: json.readInt('hostTimeMicros'),
  );

  static const String _type = 'syncPong';

  /// `t0` echoed back so the client can match the probe.
  final int clientSentAtMicros;

  /// `t1` measured on the host clock.
  final int hostTimeMicros;

  @override
  JsonMap toJson() => {
    'type': _type,
    'clientSentAtMicros': clientSentAtMicros,
    'hostTimeMicros': hostTimeMicros,
  };

  @override
  List<Object?> get props => [clientSentAtMicros, hostTimeMicros];
}

/// Broadcasts the redacted session state after every engine transition.
final class GameSnapshotMessage extends ServerMessage {
  /// Wraps [game] for transport.
  const GameSnapshotMessage(this.game);

  /// Restores the frame from [json].
  factory GameSnapshotMessage.fromJson(JsonMap json) =>
      GameSnapshotMessage(GameState.fromJson(json.readObject('game')));

  static const String _type = 'snapshot';

  /// The player facing session snapshot.
  final GameState game;

  @override
  JsonMap toJson() => {'type': _type, 'game': game.toJson()};

  @override
  List<Object?> get props => [game];
}

/// Reports a rejected frame without tearing the connection down.
final class ProtocolErrorMessage extends ServerMessage {
  /// Creates an error frame.
  const ProtocolErrorMessage({required this.code, required this.message});

  /// Restores the frame from [json].
  factory ProtocolErrorMessage.fromJson(JsonMap json) => ProtocolErrorMessage(
    code: json.readString('code'),
    message: json.readString('message'),
  );

  static const String _type = 'error';

  /// Machine readable error code.
  final String code;

  /// Human readable explanation.
  final String message;

  @override
  JsonMap toJson() => {'type': _type, 'code': code, 'message': message};

  @override
  List<Object?> get props => [code, message];
}

final class PokerWagerMessage extends ClientMessage {
  const PokerWagerMessage({required this.questionId, required this.wager});
  final String questionId;
  final int wager;
  @override
  JsonMap toJson() => {
    'type': 'pokerWager',
    'questionId': questionId,
    'wager': wager,
  };
  @override
  List<Object?> get props => [questionId, wager];
}
