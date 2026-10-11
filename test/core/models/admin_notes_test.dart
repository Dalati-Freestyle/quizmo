import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final questions =
      <Question>[
            const MultipleChoiceQuestion(
              id: 'mc',
              prompt: '?',
              options: [
                AnswerOption(id: 'a', label: 'A'),
                AnswerOption(id: 'b', label: 'B'),
              ],
              correctOptionId: 'a',
            ),
            const BuzzerQuestion(id: 'buzz', prompt: '?', expectedAnswer: 'A'),
            const ShortAnswerQuestion(
              id: 'short',
              prompt: '?',
              acceptedAnswers: ['A'],
            ),
            const OrderingQuestion(
              id: 'order',
              prompt: '?',
              items: [
                AnswerOption(id: 'a', label: 'A'),
                AnswerOption(id: 'b', label: 'B'),
              ],
              correctOrder: ['a', 'b'],
            ),
            const MatchingQuestion(
              id: 'match',
              prompt: '?',
              leftItems: [
                AnswerOption(id: 'a', label: 'A'),
                AnswerOption(id: 'b', label: 'B'),
              ],
              rightItems: [
                AnswerOption(id: 'x', label: 'X'),
                AnswerOption(id: 'y', label: 'Y'),
              ],
              correctPairs: {'a': 'x', 'b': 'y'},
            ),
            const EstimationQuestion(
              id: 'estimate',
              prompt: '?',
              correctValue: 42,
            ),
            const TrueFalseQuestion(id: 'tf', prompt: '?', correctAnswer: true),
          ]
          .map(
            (q) => Question.fromJson({
              ...q.toJson(),
              'adminNotes': 'Secret host instruction',
            }),
          )
          .toList();

  test(
    'every question saves notes but redacts them before and after reveal',
    () {
      final quiz = Quiz(
        id: 'quiz',
        name: 'Quiz',
        description: 'Description',
        category: 'Category',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        questions: questions,
      );
      final restored = parseQuizImport(exportQuizJson(quiz));
      expect(restored, quiz);
      expect(restored.schemaVersion, Quiz.currentSchemaVersion);
      for (final question in restored.questions) {
        expect(question.adminNotes, 'Secret host instruction');
        expect(question.redacted().adminNotes, isEmpty);
        for (final status in [
          RoundStatus.acceptingAnswers,
          RoundStatus.revealed,
        ]) {
          final game = GameState(
            questionBank: questions,
            round: RoundState(question: question, status: status),
          );
          final wire = game.redactedForPlayers();
          expect(wire.questionBank, isEmpty);
          expect(wire.round.question!.adminNotes, isEmpty);
          expect(
            wire.round.question!.hasSolution,
            status == RoundStatus.revealed,
          );
          expect(
            wire.toJson().toString(),
            isNot(contains('Secret host instruction')),
          );
        }
      }
    },
  );
  for (final fixture in [
    'quiz_v1_before_media',
    'quiz_v1_with_media',
    'quiz_v2_with_media',
  ]) {
    test(
      '$fixture imports with empty notes and preserves media on latest export',
      () {
        final quiz = parseQuizImport(
          File('test/fixtures/$fixture.quizmo.json').readAsStringSync(),
        );
        expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
        expect(quiz.questions.every((q) => q.adminNotes.isEmpty), isTrue);
        expect(parseQuizImport(exportQuizJson(quiz)), quiz);
      },
    );
  }
}
