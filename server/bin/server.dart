import 'dart:async';
import 'dart:io';

// The standalone dependency graph in server/ shares these pure Dart sources.
// ignore: avoid_relative_lib_imports
import '../../lib/backend/internet_server.dart';
// ignore: avoid_relative_lib_imports
import '../../lib/backend/web_client_bundle_io.dart';

Future<void> main() async {
  final origin = Platform.environment['PUBLIC_ORIGIN'];
  if (origin == null) {
    throw ArgumentError('Set PUBLIC_ORIGIN=https://quiz.example.com');
  }
  final server = InternetServer(
    publicOrigin: Uri.parse(origin),
    webClient: DirectoryWebClientBundle(
      Directory(Platform.environment['WEB_ROOT'] ?? 'build/web'),
    ),
  );
  final port = await server.start(
    port: int.parse(Platform.environment['PORT'] ?? '8080'),
    address: Platform.environment['BIND_ADDRESS'] ?? '127.0.0.1',
  );
  stdout.writeln('Quizmo relay listening on port $port for $origin');
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Future<void> shutdown(ProcessSignal _) async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await server.close();
  }

  subscriptions.add(ProcessSignal.sigint.watch().listen(shutdown));
  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(shutdown));
  }
}
