/// Web stub of the embedded server factory.
///
/// Browsers cannot listen on a TCP port, so hosting is simply not available
/// there. The stub fails loudly instead of silently pretending to work.
library;

import '../core/engine/quiz_engine_bloc.dart';
import 'server_contract.dart';

/// Whether this platform can host an embedded quiz server.
const bool embeddedServerSupported = false;

/// Default port used by the host dashboard.
const int defaultServerPort = 8080;

/// Always throws: hosting requires a `dart:io` platform.
EmbeddedQuizServer createEmbeddedServer({
  required QuizEngineBloc engine,
  String serverName = 'Quizmo Host',
}) => throw EmbeddedServerUnsupportedError(
  'Hosting is unavailable in the browser. Run the host on Android, iOS, '
  'macOS, Windows or Linux and join this browser tab as a player.',
);

