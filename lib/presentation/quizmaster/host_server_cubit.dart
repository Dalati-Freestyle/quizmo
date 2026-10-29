/// Host side controller for the embedded server lifecycle.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../backend/server_contract.dart';
import '../../backend/server_launcher.dart';
import '../../backend/web_client_bundle.dart';
import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/net/lan_discovery.dart';
import '../discovery/lan_discovery_backend.dart';
import '../discovery/lan_host_list.dart' show lanDiscoveryProblemMessage;

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
    this.servesWebClient = false,
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

  /// Whether guests can join by simply opening [endpoint] in a browser.
  final bool servesWebClient;

  /// Whether hosting is possible on this platform at all.
  bool get isSupported => embeddedServerSupported;

  /// Returns a copy with the given fields replaced.
  HostServerState copyWith({
    HostServerStatus? status,
    ServerEndpoint? endpoint,
    int? port,
    String? error,
    List<ServerLogEntry>? logs,
    bool? servesWebClient,
    bool clearEndpoint = false,
    bool clearError = false,
  }) => HostServerState(
    status: status ?? this.status,
    endpoint: clearEndpoint ? null : endpoint ?? this.endpoint,
    port: port ?? this.port,
    error: clearError ? null : error ?? this.error,
    logs: logs ?? this.logs,
    servesWebClient: servesWebClient ?? this.servesWebClient,
  );

  @override
  List<Object?> get props => [
    status,
    endpoint,
    port,
    error,
    logs,
    servesWebClient,
  ];
}

/// Starts and stops the embedded host and mirrors its log feed.
class HostServerCubit extends Cubit<HostServerState> {
  /// Creates a controller that publishes the session owned by [engine].
  ///
  /// [webClient] is handed to the server so guests can load the Flutter Web
  /// player straight from the host; `null` keeps the host API-only.
  HostServerCubit({
    required QuizEngineBloc engine,
    this.serverName = 'Quizmo Host',
    WebClientBundle? webClient,
    LanDiscoveryCubit? discovery,
  }) : _engine = engine,
       _webClient = webClient,
       _discovery =
           discovery ?? LanDiscoveryCubit(backend: createLanDiscoveryBackend()),
       super(const HostServerState()) {
    _discoverySubscription = _discovery.stream.listen((state) {
      if (state.problem case final problem?) {
        _appendLog(
          ServerLogEntry(
            level: ServerLogLevel.warning,
            message:
                '${lanDiscoveryProblemMessage(problem)}'
                '${state.details == null ? "" : "\n${state.details}"}',
            atMicros: DateTime.now().microsecondsSinceEpoch,
          ),
        );
      } else if (state.publishedName case final name?) {
        _appendLog(
          ServerLogEntry(
            level: ServerLogLevel.info,
            message: 'LAN host published as "$name".',
            atMicros: DateTime.now().microsecondsSinceEpoch,
          ),
        );
      }
    });
  }

  /// Friendly name announced to clients.
  final String serverName;

  /// Maximum number of log lines retained for the dashboard.
  static const int maxLogLines = 100;

  final QuizEngineBloc _engine;
  final WebClientBundle? _webClient;
  final LanDiscoveryCubit _discovery;
  StreamSubscription<LanDiscoveryState>? _discoverySubscription;
  EmbeddedQuizServer? _server;
  StreamSubscription<ServerLogEntry>? _logSubscription;
  Future<void> _lifecycle = Future.value();
  bool _closing = false;

  /// Binds the server to [port].
  Future<void> start({int? port}) {
    if (_closing) return _lifecycle;
    return _lifecycle = _lifecycle.then((_) => _start(port: port));
  }

  Future<void> _start({int? port}) async {
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
      await _teardown();
      final server = createEmbeddedServer(
        engine: _engine,
        serverName: serverName,
        webClient: _webClient,
      );
      _server = server;
      _logSubscription = server.logs.listen(_appendLog);
      final endpoint = await server.start(port: targetPort);
      await _engine.persistRecovery?.call();
      emit(
        state.copyWith(
          status: HostServerStatus.running,
          endpoint: endpoint,
          port: endpoint.port,
          servesWebClient: server.servesWebClient,
        ),
      );
      if (endpoint.publicUri == null) {
        await _discovery.publish(name: serverName, port: endpoint.port);
      }
    } on Object catch (error) {
      await _teardown();
      emit(
        state.copyWith(
          status: HostServerStatus.failed,
          error: '$error',
          clearEndpoint: true,
          servesWebClient: false,
        ),
      );
    }
  }

  /// Stops the server and releases the port.
  Future<void> stop() {
    if (_closing) return _lifecycle;
    return _lifecycle = _lifecycle.then((_) => _stop());
  }

  Future<void> _stop() async {
    await _teardown();
    emit(
      state.copyWith(
        status: HostServerStatus.stopped,
        clearEndpoint: true,
        servesWebClient: false,
      ),
    );
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _lifecycle;
    await _teardown();
    await _discoverySubscription?.cancel();
    await _discovery.close();
    return super.close();
  }

  Future<void> setDiscoverySuspended(bool suspended) =>
      _discovery.setSuspended(suspended);

  Future<void> _teardown() async {
    await _discovery.stop();
    await _logSubscription?.cancel();
    _logSubscription = null;
    await _server?.dispose();
    _server = null;
  }

  void _appendLog(ServerLogEntry entry) {
    if (isClosed) return;
    if (entry.level == ServerLogLevel.error &&
        _server?.isRunning == false &&
        state.status == HostServerStatus.running) {
      unawaited(_discovery.stop());
      emit(
        state.copyWith(
          status: HostServerStatus.failed,
          error: entry.message,
          clearEndpoint: true,
          servesWebClient: false,
        ),
      );
    }
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
