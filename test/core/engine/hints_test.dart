/// Hints of a question (quiz schema 13): showing, taking back, scoring,
/// redaction and the quiz file.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const int kEpoch = 1700000000000000;

const hints = [
  QuestionHint(text: 'First', cost: 2),
  QuestionHint(text: 'Second', cost: 3),
  QuestionHint(text: 'Third', cost: 50),
];

const truth = TrueFalseQuestion(
  id: 'q',
  prompt: 'True?',
  correctAnswer: true,
  timeLimit: Duration.zero,
  scoringRule: FixedPointsRule(correctPoints: 10, wrongPoints: -4),
  hints: hints,
);

const buzzer = BuzzerQuestion(
  id: 'b',
  prompt: 'Buzz',
  expectedAnswer: 'Gold',
  timeLimit: Duration.zero,
  scoringRule: FirstBuzzerRule(points: 10, penalty: -5, rankDecay: 0),
  hints: hints,
);

const teams = {
  'red': Team(id: 'red', name: 'Red'),
  'blue': Team(id: 'blue', name: 'Blue'),
};

final image = ImageAttachment(
  caption: 'Hint',
  asset: MediaAsset.upload(
    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]),
    'png',
  ),
);

Quiz quizWith(
  List<Question> questions, {
  QuizFormat format = const StandardFormat(),
}) => Quiz(
  id: 'quiz',
  name: 'Hints',
  description: 'Hints',
  category: 'Tests',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: questions,
  format: format,
);

void main() {
  late QuizEngineBloc engine;
  late int now;

  GameState game() => engine.state.game;

  Future<void> send(QuizEngineEvent event) async {
    now += 1000;
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> show() => send(
    ShowHintEvent(
      questionId: game().round.question!.id,
      shownHints: game().round.shownHintCount,
    ),
  );

  Future<void> takeBack() => send(
    TakeBackHintEvent(
      questionId: game().round.question!.id,
      shownHints: game().round.shownHintCount,
    ),
  );

  Future<void> answer(String player, {bool value = true}) async {
    now += 1000;
    await send(
      SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: player,
          questionId: 'q',
          clientTimestampMicros: now,
          clockOffsetMicros: 0,
          value: value,
        ),
      ),
    );
  }

  Future<void> join(String id, [String? teamId]) => send(
    PlayerJoinedEvent(
      Player(id: id, name: id, teamId: teamId, isConnected: true),
    ),
  );

  Future<void> open(QuizEngineBloc bloc, {bool withTeams = false}) async {
    engine = bloc;
    addTearDown(bloc.close);
    await join('ann', withTeams ? 'red' : null);
    await join('bob', withTeams ? 'blue' : null);
    await join('cid', withTeams ? 'blue' : null);
    await send(const StartGameEvent());
  }

  setUp(() => now = kEpoch);

  test('hints only reduce what an answer would have earned', () {
    const earned = ScoreDelta(10, reason: 'correct');
    expect(applyHintDeduction(earned, 4).points, 6);
    expect(applyHintDeduction(earned, 99).points, 0);
    expect(applyHintDeduction(earned, 0), earned);
    const lost = ScoreDelta(-5, reason: 'wrong');
    expect(applyHintDeduction(lost, 4), lost);
  });

  group('standard round', () {
    setUp(() async {
      await open(
        QuizEngineBloc(
          questionBank: const [truth, buzzer],
          buzzerGraceWindow: Duration.zero,
          now: () => now,
        ),
      );
    });

    test('only hints shown before the answer lower its points', () async {
      await send(const StartRoundEvent('q'));
      expect(game().reachablePoints, 10);
      await answer('ann');
      await show();
      await show();
      expect(game().reachablePoints, 5);
      await answer('bob');
      await answer('cid', value: false);
      expect(game().round.status, RoundStatus.revealed);
      expect(game().scores.scoreOf('ann'), 10);
      expect(game().scores.scoreOf('bob'), 5);
      // A wrong answer keeps the penalty of the question, unchanged.
      expect(game().scores.scoreOf('cid'), -4);
    });

    test('points never fall below 0', () async {
      await send(const StartRoundEvent('q'));
      await show();
      await show();
      await show();
      expect(game().reachablePoints, 0);
      await answer('ann');
      await send(const RevealRoundEvent());
      expect(game().scores.scoreOf('ann'), 0);
    });

    test('a hint taken back no longer counts for anybody', () async {
      await send(const StartRoundEvent('q'));
      await show();
      await show();
      await answer('ann');
      await takeBack();
      expect(game().round.shownHintCount, 1);
      await send(const RevealRoundEvent());
      expect(game().scores.scoreOf('ann'), 8);
    });

    test('a double tap shows one hint, and none after the reveal', () async {
      await send(const StartRoundEvent('q'));
      const tap = ShowHintEvent(questionId: 'q', shownHints: 0);
      await send(tap);
      await send(tap);
      expect(game().round.shownHintCount, 1);
      await send(const ShowHintEvent(questionId: 'b', shownHints: 1));
      expect(game().round.shownHintCount, 1);
      await send(const RevealRoundEvent());
      await show();
      await takeBack();
      expect(game().round.shownHintCount, 1);
    });

    test('a new question starts without shown hints', () async {
      await send(const StartRoundEvent('q'));
      await show();
      await send(const RevealRoundEvent());
      await send(const StartRoundEvent('b'));
      expect(game().round.shownHintCount, 0);
    });

    test('a buzzer press counts the hints visible when pressing', () async {
      await send(const StartRoundEvent('b'));
      await show();
      now += 1000;
      await send(
        BuzzerPressEvent(
          BuzzerPress(
            playerId: 'ann',
            questionId: 'b',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
          ),
        ),
      );
      await send(const LockBuzzerEvent());
      expect(game().round.activePlayerId, 'ann');
      await show();
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      expect(game().scores.scoreOf('ann'), 8);
    });

    test('guests only receive the content of shown hints', () async {
      await send(const StartRoundEvent('q'));
      QuestionHint guest(int i) =>
          game().redactedForPlayers().round.question!.hints[i];
      expect(guest(0).text, isEmpty);
      // The number of hints and their cost are public.
      expect(guest(1).cost, 3);
      await show();
      expect(guest(0).text, 'First');
      expect(guest(1).text, isEmpty);
      expect(
        jsonEncode(game().redactedForPlayers().toJson()),
        isNot(contains('Second')),
      );
      await takeBack();
      expect(guest(0).text, isEmpty);
      await send(const RevealRoundEvent());
      expect(
        jsonEncode(game().redactedForPlayers().toJson()),
        isNot(contains('First')),
      );
    });
  });

  group('jeopardy', () {
    Future<void> start({bool dailyDouble = false, int points = 100}) async {
      await open(
        QuizEngineBloc(
          questionBank: const [truth],
          teams: teams,
          mode: const TeamMode(),
          jeopardyBoard: JeopardyBoard(
            rowPoints: [points],
            allowSteal: true,
            penalizeWrongAnswers: true,
            categories: [
              JeopardyCategory(
                name: 'Mixed',
                cells: [
                  JeopardyCell(questionId: 'q', isDailyDouble: dailyDouble),
                ],
              ),
            ],
          ),
          now: () => now,
        ),
        withTeams: true,
      );
      await send(const SelectJeopardyCellEvent('q'));
    }

    test('the deduction applies to the row points', () async {
      await start();
      await show();
      expect(game().reachablePoints, 98);
      await answer('ann');
      await send(const RevealRoundEvent());
      expect(game().teamScores['red'], 98);
    });

    test('a right answer worth 0 points does not open a steal', () async {
      await start(points: 1);
      await show();
      await answer('ann');
      await send(const RevealRoundEvent());
      expect(game().round.status, RoundStatus.revealed);
      expect(game().teamScores['red'], 0);
    });

    test('the stealing teams also pay for hints shown before', () async {
      await start();
      await show();
      // The only player of the picking team missed: the steal opens.
      await answer('ann', value: false);
      expect(game().jeopardy!.isStealRound, isTrue);
      expect(game().round.shownHintCount, 1);
      await answer('bob');
      await send(const RevealRoundEvent());
      expect(game().teamScores['blue'], 98);
      expect(game().teamScores['red'], -100);
    });

    test('a Daily Double pays the wager minus the hints', () async {
      await start(dailyDouble: true);
      await send(const PlaceDailyDoubleWagerEvent(40));
      await show();
      await answer('ann');
      await send(const RevealRoundEvent());
      expect(game().teamScores['red'], 38);
    });
  });

  test('poker hints are free and wait for the betting to end', () async {
    await open(
      QuizEngineBloc(
        questionBank: const [truth],
        teams: teams,
        pokerStartingChips: 10,
        now: () => now,
      ),
      withTeams: true,
    );
    await send(const StartRoundEvent('q'));
    await show();
    expect(game().round.shownHintCount, 0);
    await send(
      const PlacePokerWagerEvent(playerId: 'ann', questionId: 'q', wager: 4),
    );
    await send(const OpenPokerAnswersEvent());
    await show();
    expect(game().round.shownHintCount, 1);
    expect(game().reachablePoints, isNull);
    await answer('ann');
    await send(const RevealRoundEvent());
    expect(game().poker!.chips['red'], 14);
  });

  test('the live round survives JSON and a recovery checkpoint', () async {
    final quiz = quizWith(const [truth]);
    await open(QuizEngineBloc(questionBank: quiz.questions, now: () => now));
    await send(const StartRoundEvent('q'));
    await show();
    expect(
      RoundState.fromJson(
        jsonDecode(jsonEncode(game().round.toJson())) as JsonMap,
      ),
      game().round,
    );
    final checkpoint = SessionCheckpoint(
      sessionId: 'session-0123456789abcdef',
      quiz: quiz,
      game: game().copyWith(recoveryPaused: true),
      savedAtMicros: now,
      resumeTokenHashes: {for (final id in game().players.keys) id: 'a' * 64},
    );
    final saved = SessionCheckpoint.decode(
      checkpoint.encode(),
      quizDocument: jsonEncode(quiz.toJson()),
    );
    expect(saved.game.round.hintTimesMicros, game().round.hintTimesMicros);

    // Resuming moves the hints along with the answers on the host timeline.
    final resumeAt = now + 1000000;
    final restored = QuizEngineBloc(
      questionBank: quiz.questions,
      restoredGame: saved.game,
      now: () => resumeAt,
    );
    addTearDown(restored.close);
    restored.add(const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime));
    await pumpEventQueue();
    expect(
      restored.state.game.round.hintTimesMicros.single -
          game().round.hintTimesMicros.single,
      resumeAt - saved.game.hostTimeMicros,
    );
  });

  group('quiz file', () {
    final rich = [
      QuestionHint(text: 'Look', media: [image], cost: 5),
      const QuestionHint(text: 'Free'),
    ];

    test('every question kind round-trips its hints with media', () {
      final question = {
        ...truth.toJson(),
        'hints': rich.map((h) => h.toJson()).toList(),
      };
      final base = Question.fromJson(question);
      final kinds = <Question>[
        base,
        BuzzerQuestion(id: 'b', prompt: 'B', expectedAnswer: 'x', hints: rich),
        ShortAnswerQuestion(
          id: 's',
          prompt: 'S',
          acceptedAnswers: const ['x'],
          hints: rich,
        ),
        EstimationQuestion(id: 'e', prompt: 'E', correctValue: 1, hints: rich),
        MultipleChoiceQuestion(
          id: 'm',
          prompt: 'M',
          options: const [
            AnswerOption(id: 'a', label: 'A'),
            AnswerOption(id: 'b', label: 'B'),
          ],
          correctOptionId: 'a',
          hints: rich,
        ),
        OrderingQuestion(
          id: 'o',
          prompt: 'O',
          items: const [
            AnswerOption(id: 'a', label: 'A'),
            AnswerOption(id: 'b', label: 'B'),
          ],
          correctOrder: const ['a', 'b'],
          hints: rich,
        ),
        MatchingQuestion(
          id: 'p',
          prompt: 'P',
          leftItems: const [
            AnswerOption(id: 'a', label: 'A'),
            AnswerOption(id: 'b', label: 'B'),
          ],
          rightItems: const [
            AnswerOption(id: 'x', label: 'X'),
            AnswerOption(id: 'y', label: 'Y'),
          ],
          correctPairs: const {'a': 'x', 'b': 'y'},
          hints: rich,
        ),
      ];
      final restored = parseQuizImport(exportQuizJson(quizWith(kinds)));
      expect(restored.questions, kinds);
      for (final question in restored.questions) {
        expect(question.hints, rich, reason: question.kindLabel);
        expect(question.redacted().hints.map((h) => h.text).join(), isEmpty);
        expect(
          question.redacted().hints.every((h) => h.media.isEmpty),
          isTrue,
          reason: question.kindLabel,
        );
        expect(question.withoutSolution().hints, rich);
      }
    });

    test('invalid hints are rejected', () {
      expect(
        quizWith([
          const TrueFalseQuestion(
            id: 'q',
            prompt: 'Q',
            correctAnswer: true,
            hints: [QuestionHint(cost: -1)],
          ),
        ]).validationErrors(),
        [
          'Ein Tipp braucht einen Text oder ein Medium.',
          'Der Punktabzug eines Tipps muss zwischen 0 und 1000000 liegen.',
        ],
      );
      expect(
        quizWith([
          TrueFalseQuestion(
            id: 'q',
            prompt: 'Q',
            correctAnswer: true,
            hints: List.filled(11, const QuestionHint(text: 'x')),
          ),
        ]).validationErrors(),
        ['Maximal zehn Tipps pro Frage.'],
      );
    });

    test('schema 12 files import without hints and may not contain any', () {
      final source = File(
        p.join('test', 'fixtures', 'quiz_v12_with_media.quizmo.json'),
      ).readAsStringSync();
      final quiz = parseQuizImport(source);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      expect(quiz.questions, hasLength(2));
      expect(quiz.questions.every((q) => q.hints.isEmpty), isTrue);
      expect(quiz.questions.first.media.single.asset!.bytes, isNotEmpty);
      expect(
        quiz.questions.first.solutionMedia.single.asset!.bytes,
        isNotEmpty,
      );
      expect(quiz.slides.single.title, 'Pause');
      expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);

      final json = jsonDecode(source) as JsonMap;
      ((json['questions'] as List).first as JsonMap)['hints'] = [
        {'text': 'x'},
      ];
      expect(() => Quiz.fromJson(json), throwsA(isA<JsonContractException>()));
    });
  });
}
