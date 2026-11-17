/// Platform independent contract of the embedded host.
///
/// Flutter Web cannot open a listening socket, so the presentation layer only
/// ever talks to this interface and obtains an instance through
/// `server_launcher.dart`, which resolves to an embedded LAN server on
/// `dart:io` platforms and a same-origin internet relay adapter on the web.
library;

import 'package:equatable/equatable.dart';

import 'lan_addresses.dart';

/// Severity of a [ServerLogEntry].
enum ServerLogLevel {
  /// Routine lifecycle information.
  info,

  /// Something unexpected that did not stop the server.
  warning,

  /// A failure that aborted an operation.
  error,
}

/// One line of the host's diagnostic feed.
final class ServerLogEntry extends Equatable {
  /// Creates a log entry.
  const ServerLogEntry({
    required this.level,
    required this.message,
    required this.atMicros,
  });

  /// Severity of the entry.
  final ServerLogLevel level;

  /// Human readable text.
  final String message;

  /// Host clock at the time of writing.
  final int atMicros;

  @override
  List<Object?> get props => [level, message, atMicros];
}

/// Role of an open socket.
enum ConnectionRole { player, spectator, lobby }

/// Liveness of one open socket; carries no address, token or code.
final class ConnectionHealth extends Equatable {
  /// Creates the value.
  const ConnectionHealth({
    required this.role,
    required this.silentForMicros,
    this.playerId,
  });

  /// What the socket is used for.
  final ConnectionRole role;

  /// Player behind a player socket.
  final String? playerId;

  /// Microseconds since the last frame arrived (heartbeats included).
  final int silentForMicros;

  @override
  List<Object?> get props => [role, playerId, silentForMicros];
}

/// A running device check: every player device is asked to confirm itself
/// by a tap. Carries player ids only, no address, token or code.
final class DeviceCheckStatus extends Equatable {
  /// Creates the value.
  const DeviceCheckStatus({
    required this.id,
    required this.startedAtMicros,
    this.confirmedPlayerIds = const {},
    this.confirmedScreenIds = const {},
  });

  /// Identifier sent to the devices.
  final String id;

  /// Host clock when the check started.
  final int startedAtMicros;

  /// Players whose device confirmed the check.
  final Set<String> confirmedPlayerIds;

  /// TV screens (socket ids, never addresses) that showed the check.
  final Set<String> confirmedScreenIds;

  /// Returns a copy in which [playerId] confirmed.
  DeviceCheckStatus confirm(String playerId) => DeviceCheckStatus(
    id: id,
    startedAtMicros: startedAtMicros,
    confirmedPlayerIds: Set.unmodifiable({...confirmedPlayerIds, playerId}),
    confirmedScreenIds: confirmedScreenIds,
  );

  /// Returns a copy in which the TV screen [screenId] confirmed.
  DeviceCheckStatus confirmScreen(String screenId) => DeviceCheckStatus(
    id: id,
    startedAtMicros: startedAtMicros,
    confirmedPlayerIds: confirmedPlayerIds,
    confirmedScreenIds: Set.unmodifiable({...confirmedScreenIds, screenId}),
  );

  @override
  List<Object?> get props => [
    id,
    startedAtMicros,
    confirmedPlayerIds,
    confirmedScreenIds,
  ];
}

/// Where a running server can be reached.
final class ServerEndpoint extends Equatable {
  /// Creates an endpoint description.
  const ServerEndpoint({
    required this.port,
    required this.addresses,
    this.publicUri,
    this.recoverySessionId,
  });

  final Uri? publicUri;
  final String? recoverySessionId;

  /// TCP port the server is bound to.
  final int port;

  /// LAN addresses (or the public relay hostname), **best candidate first** and
  /// loopback last.
  ///
  /// The order is produced by `sortLanAddresses` in `lan_addresses.dart`: a
  /// phone on Wi-Fi and mobile data at the same time reports several addresses
  /// and only one of them is routable for a guest.
  final List<String> addresses;

  /// The address a phone on the same Wi-Fi should use.
  String get lanAddress => addresses.firstWhere(
    (address) => address != kLoopbackAddress,
    orElse: () => addresses.isEmpty ? kLoopbackAddress : addresses.first,
  );

  /// Every address a guest could try, best first, without loopback.
  ///
  /// Rendered by the dashboard so the host can fall back to a second address
  /// when the announced one turns out to be unreachable.
  List<String> get joinableAddresses =>
      addresses.where((address) => address != kLoopbackAddress).toList();

  /// Base URI for [lanAddress].
  Uri get lanUri => uriFor(lanAddress);

  /// Base URI for a client running on the hosting device itself.
  Uri get loopbackUri => uriFor(kLoopbackAddress);

  /// Returns the base URI for [address].
  Uri uriFor(String address) {
    final uri = publicUri ?? Uri.parse('http://$address:$port');
    return recoverySessionId == null
        ? uri
        : uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'session': recoverySessionId!,
            },
          );
  }

  /// Address of the spectator (TV) screen served by the host at [address].
  ///
  /// Open it in the browser of a smart TV, a streaming stick or a casted tab.
  Uri tvUriFor(String address) =>
      uriFor(address).replace(path: '${uriFor(address).path}/tv');

  /// Spectator screen reachable from the local network.
  Uri get lanTvUri => tvUriFor(lanAddress);

  @override
  List<Object?> get props => [port, addresses, publicUri, recoverySessionId];
}

/// Raised when a server operation cannot be performed on this platform.
class EmbeddedServerUnsupportedError extends UnsupportedError {
  /// Creates the error with a platform specific [message].
  EmbeddedServerUnsupportedError(super.message);
}

/// An HTTP + web socket host that can be started from inside the app process.
abstract interface class EmbeddedQuizServer {
  /// Binds to [port] on all IPv4 interfaces and starts serving.
  Future<ServerEndpoint> start({int port});

  /// Closes every socket and releases the port.
  Future<void> stop();

  /// Whether the server is currently listening.
  bool get isRunning;

  /// The endpoint of the running server, or `null` while stopped.
  ServerEndpoint? get endpoint;

  /// Number of open web socket connections.
  int get connectionCount;

  /// Open sockets with the time since their last frame (technical check).
  List<ConnectionHealth> get connectionHealth;

  /// The running device check, or `null`.
  DeviceCheckStatus? get deviceCheck;

  /// Asks every player device to confirm itself by a tap; `null` while the
  /// server is stopped.
  DeviceCheckStatus? startDeviceCheck();

  /// Ends the device check on every player device.
  void stopDeviceCheck();

  /// Whether a non-empty web player bundle is being served at `/`.
  ///
  /// When `true`, a guest can join by opening [endpoint] in a browser; when
  /// `false`, they need the Quizmo app because `/` only answers with a
  /// placeholder.
  bool get servesWebClient;

  /// Diagnostic feed rendered on the host dashboard.
  Stream<ServerLogEntry> get logs;

  /// Releases the resources owned by this instance.
  Future<void> dispose();
}
