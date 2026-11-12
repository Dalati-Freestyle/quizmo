import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';

void main() {
  test(
    'players, TVs, REST polling and reconnects share the same reveal boundary',
    () async {
      final engine = QuizEngineBloc(
        revealMode: SolutionRevealMode.atEnd,
        questionBank: const [
          TrueFalseQuestion(id: 'q1', prompt: 'First?', correctAnswer: true),
          ShortAnswerQuestion(
            id: 'q2',
            prompt: 'Second?',
            acceptedAnswers: ['Berlin'],
            adminNotes: 'private host note',
          ),
        ],
      );
      final server = EmbeddedServer(engine: engine);
      final endpoint = await server.start(port: 0);
      final player = QuizClient(baseUri: endpoint.loopbackUri);
      final tv = QuizClient(baseUri: endpoint.loopbackUri);
      final lateTv = QuizClient(baseUri: endpoint.loopbackUri);
      addTearDown(() async {
        await player.dispose();
        await tv.dispose();
        await lateTv.dispose();
        await server.dispose();
        await engine.close();
      });
      await player.connect(name: 'Player', handshakeProbes: 1);
      await tv.watch();
      final start = player.games.firstWhere(
        (game) => game.round.status.acceptsInput,
      );
      engine.add(const StartRoundEvent('q1'));
      await start.timeout(const Duration(seconds: 5));
      final playerWaiting = player.games.firstWhere(
        (game) => game.completedQuestionIds.contains('q1'),
      );
      final tvWaiting = tv.games.firstWhere(
        (game) => game.completedQuestionIds.contains('q1'),
      );
      player.submitAnswer(
        (id, time, offset) => TrueFalseAnswer(
          playerId: id,
          questionId: 'q1',
          clientTimestampMicros: time,
          clockOffsetMicros: offset,
          value: true,
        ),
      );
      for (final snapshot in await Future.wait([
        playerWaiting,
        tvWaiting,
      ]).timeout(const Duration(seconds: 5))) {
        expect(snapshot.resultsHidden, isTrue);
        expect(snapshot.round.question!.hasSolution, isFalse);
        expect(snapshot.scores, const ScoreState());
        expect(snapshot.roundHistory, isEmpty);
        expect(snapshot.round.status, RoundStatus.locked);
      }
      final response = await http.get(
        endpoint.loopbackUri.resolve('/api/state'),
      );
      final polled = GameState.fromJson(jsonDecode(response.body) as JsonMap);
      expect(polled.scores, const ScoreState());
      expect(polled.roundHistory, isEmpty);
      expect(polled.round.question!.hasSolution, isFalse);

      final returning = player.games.firstWhere(
        (game) => game.completedQuestionIds.contains('q1'),
      );
      await player.connect(
        name: 'Player',
        handshakeProbes: 1,
        resumePlayerId: player.playerId,
        resumeToken: player.resumeToken,
      );
      expect(
        (await returning.timeout(const Duration(seconds: 5))).scores,
        const ScoreState(),
      );
      final next = player.games.firstWhere(
        (game) =>
            game.round.question?.id == 'q2' && game.round.status.acceptsInput,
      );
      engine.add(const NextQuestionEvent());
      await next.timeout(const Duration(seconds: 5));
      final playerReview = player.games.firstWhere(
        (game) => game.showFinalReview,
      );
      final tvReview = tv.games.firstWhere((game) => game.showFinalReview);
      player.submitAnswer(
        (id, time, offset) => ShortAnswer(
          playerId: id,
          questionId: 'q2',
          clientTimestampMicros: time,
          clockOffsetMicros: offset,
          text: 'Berlin',
        ),
      );
      for (final snapshot in await Future.wait([
        playerReview,
        tvReview,
      ]).timeout(const Duration(seconds: 5))) {
        expect(snapshot.roundHistory, hasLength(2));
        expect(snapshot.scores.scoreOf(player.playerId!), 20);
        expect(
          snapshot.roundHistory.every((r) => r.question!.hasSolution),
          isTrue,
        );
        expect(
          jsonEncode(snapshot.toJson()),
          isNot(contains('private host note')),
        );
      }
      final restored = lateTv.games.firstWhere((game) => game.showFinalReview);
      await lateTv.watch();
      expect(
        (await restored.timeout(const Duration(seconds: 5))).roundHistory,
        hasLength(2),
      );
    },
  );
}
