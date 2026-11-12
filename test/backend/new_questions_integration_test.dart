import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';

void main() {
  const items = [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ];
  final questions = <Question>[
    const ShortAnswerQuestion(
      id: 'short',
      prompt: 'City?',
      acceptedAnswers: ['Berlin'],
    ),
    const ShortAnswerQuestion(
      id: 'short-manual',
      prompt: 'City?',
      acceptedAnswers: ['Berlin'],
      manualGrading: true,
    ),
    const OrderingQuestion(
      id: 'order',
      prompt: 'Order?',
      items: items,
      correctOrder: ['b', 'a'],
    ),
    const MatchingQuestion(
      id: 'match',
      prompt: 'Match?',
      leftItems: items,
      rightItems: items,
      correctPairs: {'a': 'b', 'b': 'a'},
    ),
    const EstimationQuestion(
      id: 'estimate',
      prompt: 'Estimate?',
      correctValue: 100,
    ),
    const TrueFalseQuestion(id: 'true', prompt: 'True?', correctAnswer: true),
  ];
  for (final q in questions) {
    test(
      '${q.kindLabel}${q.requiresManualGrading ? ' (manual)' : ''} works over WebSocket in standard and Jeopardy',
      () async {
        for (final board in [false, true]) {
          final engine = QuizEngineBloc(
            questionBank: [q],
            teams: board ? {'team': const Team(id: 'team', name: 'Team')} : {},
            jeopardyBoard: board
                ? JeopardyBoard(
                    rowPoints: const [100],
                    categories: [
                      JeopardyCategory(
                        name: 'New types',
                        cells: [JeopardyCell(questionId: q.id)],
                      ),
                    ],
                  )
                : null,
          );
          final server = EmbeddedServer(engine: engine);
          final endpoint = await server.start(port: 0);
          final client = QuizClient(baseUri: endpoint.loopbackUri);
          try {
            await client.connect(
              name: 'Player',
              teamId: board ? 'team' : null,
              handshakeProbes: 1,
            );
            final started = client.games.firstWhere(
              (g) =>
                  g.round.question?.id == q.id && g.round.status.acceptsInput,
            );
            engine.add(StartRoundEvent(q.id));
            final hidden = await started.timeout(const Duration(seconds: 5));
            expect(hidden.round.question!.hasSolution, isFalse);
            final revealed = client.games.firstWhere(
              (g) => g.round.status == RoundStatus.revealed,
            );
            final grading = q.requiresManualGrading
                ? client.games.firstWhere(
                    (g) => g.round.status == RoundStatus.locked,
                  )
                : null;
            client.submitAnswer(
              (id, timestamp, offset) => switch (q) {
                ShortAnswerQuestion() => ShortAnswer(
                  playerId: 'spoofed',
                  questionId: q.id,
                  clientTimestampMicros: timestamp,
                  clockOffsetMicros: offset,
                  text: q.requiresManualGrading ? 'Hamburg' : 'Berln',
                ),
                OrderingQuestion() => OrderingAnswer(
                  playerId: id,
                  questionId: q.id,
                  clientTimestampMicros: timestamp,
                  clockOffsetMicros: offset,
                  itemIds: ['b', 'a'],
                ),
                MatchingQuestion() => MatchingAnswer(
                  playerId: id,
                  questionId: q.id,
                  clientTimestampMicros: timestamp,
                  clockOffsetMicros: offset,
                  pairs: {'a': 'b', 'b': 'a'},
                ),
                EstimationQuestion() => EstimationAnswer(
                  playerId: id,
                  questionId: q.id,
                  clientTimestampMicros: timestamp,
                  clockOffsetMicros: offset,
                  value: 90,
                ),
                TrueFalseQuestion() => TrueFalseAnswer(
                  playerId: id,
                  questionId: q.id,
                  clientTimestampMicros: timestamp,
                  clockOffsetMicros: offset,
                  value: true,
                ),
                MultipleChoiceQuestion() ||
                BuzzerQuestion() => throw StateError('Unexpected type'),
              },
            );
            if (grading != null) {
              final waiting = await grading.timeout(const Duration(seconds: 5));
              expect(waiting.round.question!.hasSolution, isFalse);
              expect(waiting.round.answerVerdicts, isEmpty);
              expect(waiting.scores.scoreOf(client.playerId!), 0);
              final judged = engine.stream.firstWhere(
                (state) =>
                    state.game.round.answerVerdicts[client.playerId!] == 1,
              );
              engine.add(
                JudgeAnswerEvent(
                  playerId: client.playerId!,
                  questionId: q.id,
                  startedAtHostMicros: waiting.round.startedAtHostMicros!,
                  wasCorrect: true,
                ),
              );
              await judged.timeout(const Duration(seconds: 5));
              engine.add(const RevealRoundEvent());
            }
            final result = await revealed.timeout(const Duration(seconds: 5));
            expect(result.round.question!.hasSolution, isTrue);
            if (q.requiresManualGrading) {
              expect(result.round.answerVerdicts, {client.playerId!: 1});
            }
            expect(
              result.scores.scoreOf(client.playerId!),
              q is EstimationQuestion ? (board ? 90 : 9) : (board ? 100 : 10),
            );
            expect(result.scores.scoreOf('spoofed'), 0);
          } finally {
            await client.dispose();
            await server.dispose();
            await engine.close();
          }
        }
      },
    );
  }
}
