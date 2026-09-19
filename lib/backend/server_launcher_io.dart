/// `dart:io` implementation of the embedded server factory.
library;

import '../core/engine/quiz_engine_bloc.dart';
import 'embedded_server.dart';
import 'server_contract.dart';

/// Whether this platform can host an embedded quiz server.
const bool embeddedServerSupported = true;

/// Default port used by the host dashboard.
const int defaultServerPort = kDefaultServerPort;

/// Creates a server that publishes the session owned by [engine].
EmbeddedQuizServer createEmbeddedServer({
  required QuizEngineBloc engine,
  String serverName = 'Quizmo Host',
}) => EmbeddedServer(engine: engine, serverName: serverName);

