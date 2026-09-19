/// Platform independent contract of the embedded host.
///
/// Flutter Web cannot open a listening socket, so the presentation layer only
/// ever talks to this interface and obtains an instance through
/// `server_launcher.dart`, which resolves to a real implementation on
/// `dart:io` platforms and to an explicit "unsupported" stub on the web.
library;

import 'package:equatable/equatable.dart';

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

/// Where a running server can be reached.
final class ServerEndpoint extends Equatable {
  /// Creates an endpoint description.
  const ServerEndpoint({required this.port, required this.addresses});

  /// TCP port the server is bound to.
  final int port;

  /// Every IPv4 address the server answers on, loopback first.
  final List<String> addresses;

  /// The address a phone on the same Wi-Fi should use.
  String get lanAddress => addresses.firstWhere(
    (address) => address != '127.0.0.1',
    orElse: () => addresses.isEmpty ? '127.0.0.1' : addresses.first,
  );

  /// Base URI for [lanAddress].
  Uri get lanUri => uriFor(lanAddress);

  /// Base URI for a client running on the hosting device itself.
  Uri get loopbackUri => uriFor('127.0.0.1');

  /// Returns the base URI for [address].
  Uri uriFor(String address) => Uri.parse('http://$address:$port');

  @override
  List<Object?> get props => [port, addresses];
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

  /// Diagnostic feed rendered on the host dashboard.
  Stream<ServerLogEntry> get logs;

  /// Releases the resources owned by this instance.
  Future<void> dispose();
}

