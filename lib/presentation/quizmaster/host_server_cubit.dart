/// Host side controller for the embedded server lifecycle.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../backend/server_contract.dart';
import '../../backend/server_launcher.dart';
import '../../core/engine/quiz_engine_bloc.dart';

/// Lifecycle of the embedded server.
enum HostServerStatus {
  /// Not listening.
  stopped,

  /// Binding the port.
  starting,

  /// Listening and accepting clients.
  running,

  /// The last start attempt failed.
  failed,
}

/// UI state of the server control card.
final class HostServerState extends Equatable {
  /// Creates a server control state.
  const HostServerState({
    this.status = HostServerStatus.stopped,
    this.endpoint,
    this.port = defaultServerPort,
    this.error,
    this.logs = const [],
  });

  /// Current lifecycle position.
  final HostServerStatus status;

  /// Where the running server can be reached.
  final ServerEndpoint? endpoint;

  /// Port the next start attempt will use.
  final int port;

  /// Message of the last failure.
  final String? error;

  /// Most recent diagnostic lines, newest last.
  final List<ServerLogEntry> logs;

  /// Whether hosting is possible on this platform at all.
  bool get isSupported => embeddedServerSupported;

  /// Returns a copy with the given fields replaced.
  HostServerState copyWith({
    HostServerStatus? status,
    ServerEndpoint? endpoint,
    int? port,
    String? error,
    List<ServerLogEntry>? logs,
    bool clearEndpoint = false,
    bool clearError = false,
  }) => HostServerState(
    status: status ?? this.status,
    endpoint: clearEndpoint ? null : endpoint ?? this.endpoint,
    port: port ?? this.port,
    error: clearError ? null : error ?? this.error,
    logs: logs ?? this.logs,
  );

  @override
  List<Object?> get props => [status, endpoint, port, error, logs];
}

/// Starts and stops the embedded host and mirrors its log feed.
class HostServerCubit extends Cubit<HostServerState> {
  /// Creates a controller that publishes the session owned by [engine].
  HostServerCubit({required QuizEngineBloc engine, this.serverName = 'Quizmo Host'})
    : _engine = engine,
      super(const HostServerState());

  /// Friendly name announced to clients.
  final String serverName;

  /// Maximum number of log lines retained for the dashboard.
  static const int maxLogLines = 100;

  final QuizEngineBloc _engine;
  EmbeddedQuizServer? _server;
  StreamSubscription<ServerLogEntry>? _logSubscription;

  /// Binds the server to [port].
  Future<void> start({int? port}) async {
    if (state.status == HostServerStatus.running ||
        state.status == HostServerStatus.starting) {
      return;
    }
    final targetPort = port ?? state.port;
    emit(
      state.copyWith(
        status: HostServerStatus.starting,
        port: targetPort,
        clearError: true,
      ),
    );

    try {
      final server = createEmbeddedServer(
        engine: _engine,
        serverName: serverName,
      );
      _server = server;
      _logSubscription = server.logs.listen(_appendLog);
      final endpoint = await server.start(port: targetPort);
      emit(
        state.copyWith(
          status: HostServerStatus.running,
          endpoint: endpoint,
          port: endpoint.port,
        ),
      );
    } on Object catch (error) {
      await _teardown();
      emit(
        state.copyWith(
          status: HostServerStatus.failed,
          error: '$error',
          clearEndpoint: true,
        ),
      );
    }
  }

  /// Stops the server and releases the port.
  Future<void> stop() async {
    await _teardown();
    emit(
      state.copyWith(status: HostServerStatus.stopped, clearEndpoint: true),
    );
  }

  @override
  Future<void> close() async {
    await _teardown();
    return super.close();
  }

  Future<void> _teardown() async {
    await _logSubscription?.cancel();
    _logSubscription = null;
    await _server?.dispose();
    _server = null;
  }

  void _appendLog(ServerLogEntry entry) {
    if (isClosed) return;
    final logs = [...state.logs, entry];
    emit(
      state.copyWith(
        logs: logs.length > maxLogLines
            ? logs.sublist(logs.length - maxLogLines)
            : logs,
      ),
    );
  }
}

