import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const question = MultipleChoiceQuestion(
  id: 'q',
  prompt: 'Select A and C',
  allowMultipleAnswers: true,
  correctOptionIds: ['a', 'c'],
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
    AnswerOption(id: 'c', label: 'C'),
  ],
);
MultipleChoiceAnswer answer(List<String> ids, {String player = 'p'}) =>
    MultipleChoiceAnswer(
      playerId: player,
      questionId: 'q',
      clientTimestampMicros: 1000001,
      clockOffsetMicros: 0,
      optionIds: ids,
    );

void main() {
  test(
    'only the exact solution set scores; invalid or duplicate IDs are rejected',
    () {
      expect(question.accuracy(answer(['c', 'a'])), 1);
      for (final ids in [
        ['a'],
        ['a', 'b', 'c'],
        ['b'],
        ['a', 'a', 'c'],
        ['x'],
      ]) {
        expect(question.accuracy(answer(ids)), 0);
      }
      expect(question.accepts(answer([])), isFalse);
      expect(question.accepts(answer(['a', 'a'])), isFalse);
      expect(question.accepts(answer(['x'])), isFalse);
      expect(question.solutionLabel, 'A / C');
      final restored = AnswerSubmission.fromJson(answer(['a', 'c']).toJson());
      expect(restored, answer(['a', 'c']));
      expect(
        (restored.withPlayerId(
          'real',
        ) as MultipleChoiceAnswer).selectedOptionIds,
        ['a', 'c'],
      );
    },
  );

  test('redaction preserves selection mode while hiding every solution', () {
    final hidden = Question.fromJson(
      question.redacted().toJson(),
    ) as MultipleChoiceQuestion;
    expect(hidden.allowMultipleAnswers, isTrue);
    expect(hidden.correctOptionId, isNull);
    expect(hidden.correctOptionIds, isNull);
    expect(hidden.hasSolution, isFalse);
  });

  test(
    'first submitted answer is permanent and later attempts cannot change it',
    () async {
      final engine = QuizEngineBloc(
        questionBank: const [question],
        now: () => 1000000,
      );
      addTearDown(engine.close);
      for (final id in ['p', 'other']) {
        engine.add(PlayerJoinedEvent(Player(id: id, name: id)));
      }
      await pumpEventQueue();
      engine.add(const StartRoundEvent('q'));
      await pumpEventQueue();
      engine.add(SubmitAnswerEvent(answer(['a'])));
      await pumpEventQueue();
      engine.add(SubmitAnswerEvent(answer(['a', 'c'])));
      await pumpEventQueue();
      expect(
        (engine.state.game.round.answers['p'] as MultipleChoiceAnswer)
            .selectedOptionIds,
        ['a'],
      );
      engine.add(SubmitAnswerEvent(answer(['c', 'a'], player: 'other')));
      await pumpEventQueue();
      expect(engine.state.game.scores.scoreOf('p'), 0);
      expect(engine.state.game.scores.scoreOf('other'), greaterThan(0));
    },
  );

  test(
    'schema 3 exports multiple solutions and malformed import never persists',
    () async {
      final quiz = Quiz(
        id: 'quiz',
        name: 'Quiz',
        description: 'Multiple answers',
        category: 'Testing',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        questions: const [question],
      );
      final contents = exportQuizJson(quiz);
      expect(parseQuizImport(contents), quiz);
      expect(jsonDecode(contents)['schemaVersion'], Quiz.currentSchemaVersion);
      final repository = InMemoryQuizRepository();
      await repository.save(quiz);
      for (final ids in [
        <String>[],
        ['x'],
        ['a', 'a'],
      ]) {
        final json = quiz.toJson();
        json['questions'] = [
          {...question.toJson(), 'correctOptionIds': ids},
        ];
        await expectLater(
          importQuiz(
            contents: jsonEncode(json),
            repository: repository,
            createId: () => 'new',
          ),
          throwsA(isA<QuizImportException>()),
        );
        expect(await repository.loadAll(), [quiz]);
      }
    },
  );

  test(
    'multiple solutions preserve old fixture question and solution media',
    () {
      final legacy = parseQuizImport(
        File('test/fixtures/quiz_v1_with_media.quizmo.json').readAsStringSync(),
      );
      final original = legacy.questions.first;
      final multi = Question.fromJson({
        ...question.toJson(),
        'media': original.media.map((m) => m.toJson()).toList(),
        'solutionMedia': original.solutionMedia.map((m) => m.toJson()).toList(),
      });
      final updated = legacy.copyWith(
        questions: [multi],
        format: const StandardFormat(),
      );
      final restored = parseQuizImport(exportQuizJson(updated));
      expect(restored.questions.single, multi);
      expect(restored.questions.single.media, original.media);
      expect(restored.questions.single.solutionMedia, original.solutionMedia);
    },
  );

  test(
    'poker pays only the complete solution set and keeps submissions secret',
    () async {
      final engine = QuizEngineBloc(
        questionBank: const [question],
        teams: const {
          'a': Team(id: 'a', name: 'A'),
          'b': Team(id: 'b', name: 'B'),
        },
        pokerStartingChips: 100,
        now: () => 1000000,
      );
      addTearDown(engine.close);
      Future<void> send(QuizEngineEvent event) async {
        engine.add(event);
        await pumpEventQueue();
      }

      await send(
        const PlayerJoinedEvent(Player(id: 'p', name: 'P', teamId: 'a')),
      );
      await send(
        const PlayerJoinedEvent(
          Player(id: 'other', name: 'Other', teamId: 'b'),
        ),
      );
      await send(const StartRoundEvent('q'));
      await send(
        const PlacePokerWagerEvent(playerId: 'p', questionId: 'q', wager: 20),
      );
      await send(
        const PlacePokerWagerEvent(
          playerId: 'other',
          questionId: 'q',
          wager: 30,
        ),
      );
      await send(const OpenPokerAnswersEvent());
      await send(SubmitAnswerEvent(answer(['a'])));
      expect(engine.state.game.redactedForPlayers().round.answers, isEmpty);
      await send(SubmitAnswerEvent(answer(['c', 'a'], player: 'other')));
      expect(engine.state.game.poker!.chips, {'a': 80, 'b': 130});
      expect(engine.state.game.round.status, RoundStatus.revealed);
    },
  );

  test('board applies row points to a multiple-answer question', () async {
    final engine = QuizEngineBloc(
      questionBank: const [question],
      jeopardyBoard: const JeopardyBoard(
        rowPoints: [250],
        categories: [
          JeopardyCategory(
            name: 'C',
            cells: [JeopardyCell(questionId: 'q')],
          ),
        ],
      ),
      now: () => 1000000,
    );
    addTearDown(engine.close);
    engine.add(const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
    await pumpEventQueue();
    engine.add(const SelectJeopardyCellEvent('q'));
    await pumpEventQueue();
    engine.add(SubmitAnswerEvent(answer(['c', 'a'])));
    await pumpEventQueue();
    expect(engine.state.game.scores.scoreOf('p'), 250);
  });
}
