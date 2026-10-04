/// `dart:io` implementation of the embedded server factory.
library;

import '../core/engine/quiz_engine_bloc.dart';
import 'embedded_server.dart';
import 'server_contract.dart';
import 'web_client_bundle.dart';

/// Whether this platform can host an embedded quiz server.
const bool embeddedServerSupported = true;

/// Default port used by the host dashboard.
const int defaultServerPort = kDefaultServerPort;

/// Creates a server that publishes the session owned by [engine].
///
/// [webClient] is the static Flutter Web player served at `/`, so a guest only
/// needs the LAN address to join. Pass `null` to run API-only.
EmbeddedQuizServer createEmbeddedServer({
  required QuizEngineBloc engine,
  String serverName = 'Quizmo Host',
  WebClientBundle? webClient,
}) => EmbeddedServer(
  engine: engine,
  serverName: serverName,
  webClient: webClient,
);
