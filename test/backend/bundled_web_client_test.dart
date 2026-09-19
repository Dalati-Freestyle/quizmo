/// Smoke test of the real, generated web client bundle.
///
/// Skips unless `dart run tool/bundle_web_client.dart` has produced the
/// archive, so a fresh checkout (or CI without a web build) stays green while a
/// local run still verifies the whole chain: zip asset → bundle → HTTP.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/backend/web_client_bundle_io.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';

void main() {
  final bundleFile = File('assets/web_client/bundle.zip');
  final skipReason = bundleFile.existsSync()
      ? null
      : 'Run `dart run tool/bundle_web_client.dart` to generate '
            '${bundleFile.path}.';

  test('serves the packed Flutter Web build over HTTP', () async {
    final engine = QuizEngineBloc(
      questionBank: sampleQuestionBank,
      teams: sampleTeams,
    );
    addTearDown(engine.close);

    final server = EmbeddedServer(
      engine: engine,
      serverName: 'Bundle Host',
      webClient: zipWebClientBundleFromFile(bundleFile.path),
    );
    addTearDown(server.dispose);

    final endpoint = await server.start(port: 0);
    expect(server.servesWebClient, isTrue);

    final index = await http.get(endpoint.loopbackUri);
    expect(index.statusCode, 200);
    expect(index.headers['content-type'], startsWith('text/html'));
    expect(index.body, contains('flutter_bootstrap.js'));

    final bootstrap = await http.get(
      endpoint.loopbackUri.resolve('/flutter_bootstrap.js'),
    );
    expect(bootstrap.statusCode, 200);
    expect(bootstrap.headers['content-type'], startsWith('text/javascript'));

    // The API must still win over the static catch-all.
    final health = await http.get(endpoint.loopbackUri.resolve('/api/health'));
    expect(health.statusCode, 200);
  }, skip: skipReason);
}

