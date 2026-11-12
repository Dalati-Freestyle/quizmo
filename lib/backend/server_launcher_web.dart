import '../core/engine/guest_wifi_cubit.dart';
import '../core/engine/quiz_engine_bloc.dart';
import 'relay_host.dart';
import 'server_contract.dart';
import 'web_client_bundle.dart';

const bool embeddedServerSupported = true;
const int defaultServerPort = 8080;

EmbeddedQuizServer createEmbeddedServer({
  required QuizEngineBloc engine,
  String serverName = 'Quizmo Host',
  WebClientBundle? webClient,
  GuestWifiCubit? guestWifi,
}) => RelayHost(
  engine: engine,
  origin: Uri.parse(Uri.base.origin),
  serverName: serverName,
);
