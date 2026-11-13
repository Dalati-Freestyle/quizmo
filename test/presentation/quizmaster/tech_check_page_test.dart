import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/lan_discovery.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/host_server_cubit.dart';
import 'package:quizmo/presentation/quizmaster/tech_check_page.dart';

import '../../helpers/fake_lan_discovery.dart';

void main() {
  testWidgets('shows every check with status and lets the host mark the TV '
      'as not required without touching the game', (tester) async {
    final engine = QuizEngineBloc(
      questionBank: const [
        TrueFalseQuestion(id: 'q', prompt: 'Q', correctAnswer: true),
      ],
    );
    final server = HostServerCubit(
      engine: engine,
      discovery: LanDiscoveryCubit(backend: FakeBackend()),
    );
    engine.add(const PlayerJoinedEvent(Player(id: 'p', name: 'Anna')));
    await tester.pump();
    final before = engine.state.game;

    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: TechCheckPage(
          engine: engine,
          server: server,
          questions: engine.state.game.questionBank,
        ),
      ),
    );
    await tester.pump();

    for (final id in [
      'hostServer',
      'reachability',
      'players',
      'latency',
      'tv',
      'media',
    ]) {
      expect(find.byKey(ValueKey('tech-check-$id')), findsOneWidget);
    }
    // The server is stopped: an actionable failure, not a silent success.
    expect(find.text('The host server is not running.'), findsOneWidget);
    expect(
      find.text('No clock synchronisation samples available.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('tech-check-ack-tv')));
    await tester.pump();
    expect(find.textContaining('acknowledged'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tech-check-required-tv')));
    await tester.pump();
    expect(find.text('Marked as not required for this game.'), findsOneWidget);

    expect(engine.state.game, before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await server.close();
      await engine.close();
    });
  });
}
