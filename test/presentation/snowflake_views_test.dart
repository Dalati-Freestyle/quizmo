import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';
import 'package:quizmo/core/simulation/preview_session.dart';
import 'package:quizmo/presentation/common/question_result_view.dart';
import 'package:quizmo/presentation/common/session_notifications.dart';
import 'package:quizmo/presentation/common/snowflake_result_view.dart';
import 'package:quizmo/presentation/quizmaster/editor/question_editor.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_cubit.dart';

const _choice = MultipleChoiceQuestion(
  id: 'mc',
  prompt: 'Best season?',
  timeLimit: Duration.zero,
  scoringRule: FixedPointsRule(correctPoints: 12),
  options: [
    AnswerOption(id: 'a', label: 'Spring'),
    AnswerOption(id: 'b', label: 'Summer'),
    AnswerOption(id: 'c', label: 'Autumn'),
  ],
);

Quiz _quiz({
  QuizFormat format = const SnowflakeFormat(scoring: SnowflakeScoring.graded),
  List<Question> questions = const [
    _choice,
    TrueFalseQuestion(id: 'tf', prompt: 'True?', timeLimit: Duration.zero),
    OrderingQuestion(
      id: 'order',
      prompt: 'Rank',
      timeLimit: Duration.zero,
      items: [
        AnswerOption(id: 'x', label: 'X'),
        AnswerOption(id: 'y', label: 'Y'),
        AnswerOption(id: 'z', label: 'Z'),
      ],
    ),
    MatchingQuestion(
      id: 'match',
      prompt: 'Pair',
      timeLimit: Duration.zero,
      leftItems: [
        AnswerOption(id: 'l1', label: 'L1'),
        AnswerOption(id: 'l2', label: 'L2'),
      ],
      rightItems: [
        AnswerOption(id: 'r1', label: 'R1'),
        AnswerOption(id: 'r2', label: 'R2'),
      ],
    ),
  ],
}) => Quiz(
  id: 'quiz',
  name: 'Snowflakes',
  description: 'Rarest answer wins',
  category: 'Testing',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  format: format,
  questions: questions,
);

MultipleChoiceAnswer _pick(String player, String option) =>
    MultipleChoiceAnswer(
      playerId: player,
      questionId: 'mc',
      clientTimestampMicros: 1000001,
      clockOffsetMicros: 0,
      optionId: option,
    );

/// A revealed round: Ann alone picks Spring, two pick Summer, three Autumn.
Future<GameState> _revealedGame() async {
  final engine = QuizEngineBloc(
    questionBank: const [_choice],
    snowflakeScoring: SnowflakeScoring.graded,
    now: () => 1000000,
  );
  addTearDown(engine.close);
  const picks = {
    'Ann': 'a',
    'Ben': 'b',
    'Cem': 'b',
    'Dua': 'c',
    'Eli': 'c',
    'Fay': 'c',
  };
  for (final name in picks.keys) {
    engine.add(PlayerJoinedEvent(Player(id: name, name: name)));
  }
  engine.add(const StartRoundEvent('mc'));
  for (final entry in picks.entries) {
    engine.add(SubmitAnswerEvent(_pick(entry.key, entry.value)));
  }
  engine.add(const RevealRoundEvent());
  await pumpEventQueue();
  expect(engine.state.game.round.status, RoundStatus.revealed);
  return engine.state.game;
}

void main() {
  testWidgets('host, player and TV list the answers by rarity', (tester) async {
    final game = (await tester.runAsync(_revealedGame))!;
    // Players and TVs render the redacted snapshot.
    for (final (snapshot, host) in [
      (game, true),
      (game.redactedForPlayers(), false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuestionResultView(
                key: ValueKey(host),
                question: snapshot.round.question!,
                game: snapshot,
                host: host,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SnowflakeResultView), findsOneWidget);
      expect(find.text('Die seltenste Antwort gewinnt'), findsOneWidget);
      // No solution exists, so none is shown.
      expect(find.textContaining('Lösung'), findsNothing);
      final rows = tester
          .widgetList<Text>(find.textContaining('% der Punkte'))
          .map((text) => text.data!)
          .toList();
      expect(rows, [
        'Spring · 1× · 100 % der Punkte\nAnn',
        'Summer · 2× · 50 % der Punkte\nBen, Cem',
        'Autumn · 3× · 0 % der Punkte\nDua, Eli, Fay',
      ]);
    }
  });

  testWidgets('the feedback names rarity instead of right and wrong', (
    tester,
  ) async {
    final game = (await tester.runAsync(_revealedGame))!;
    expect(roundFeedback(game, 'Ann'), 'Seltenste Antwort! · +12 Punkte');
    expect(roundFeedback(game, 'Ben'), 'Ziemlich selten · +6 Punkte');
    expect(
      roundFeedback(game, 'Dua'),
      'Zu viele hatten dieselbe Antwort · 0 Punkte',
    );
  });

  test('the preview plays a whole snowflake quiz with bots', () async {
    final session = PreviewSession(_quiz());
    addTearDown(session.close);
    for (var i = 0; i < 6; i++) {
      session.addParticipant(name: 'Bot $i', bot: BotSettings());
    }
    session.send(const StartGameEvent());
    await session.flush();
    for (final question in session.quiz.questions) {
      session.send(StartRoundEvent(question.id));
      await session.advance(const Duration(seconds: 5));
      // Guests never see the others' answers before the reveal.
      if (session.engine.state.game.round.status != RoundStatus.revealed) {
        expect(session.guestGame.round.answers, isEmpty);
        session.send(const RevealRoundEvent());
        await session.flush();
      }
      final round = session.engine.state.game.round;
      expect(round.status, RoundStatus.revealed, reason: question.id);
      expect(round.answers, hasLength(6), reason: question.id);
      expect(session.guestGame.round.snowflakeGroups, isNotEmpty);
    }
    expect(session.engine.state.game.allQuestionsPlayed, isTrue);
  });

  group('editor', () {
    test('switching to the format drops the stored solutions', () async {
      final repository = InMemoryQuizRepository();
      final cubit = QuizEditorCubit(
        repository: repository,
        quiz: _quiz(
          format: const StandardFormat(),
          questions: const [
            TrueFalseQuestion(
              id: 'tf',
              prompt: 'True?',
              correctAnswer: true,
              adminNotes: 'keep me',
            ),
          ],
        ),
      );
      addTearDown(cubit.close);
      cubit.useSnowflakeFormat(scoring: SnowflakeScoring.graded);
      final question = cubit.state.draft.questions.single;
      expect(question.hasSolution, isFalse);
      expect(question.adminNotes, 'keep me');
      expect(
        cubit.state.draft.format,
        const SnowflakeFormat(scoring: SnowflakeScoring.graded),
      );
      final saved = await cubit.save();
      expect(saved, isNotNull);
      expect(parseQuizImport(exportQuizJson(saved!)), saved);
    });

    test('only the supported question kinds are offered', () {
      expect(
        questionTemplatesFor(const SnowflakeFormat()).map((t) => t.label),
        unorderedEquals([
          'Reihenfolge',
          'Zuordnung',
          'Wahr / Falsch',
          'Multiple choice',
        ]),
      );
      expect(questionTemplatesFor(const StandardFormat()), kQuestionTemplates);
    });
  });

  test('a finished import leaves the loading screen', () async {
    final cubit = QuizLibraryCubit(
      repository: InMemoryQuizRepository([_quiz().copyWith(id: 'existing')]),
    );
    addTearDown(cubit.close);
    await cubit.load();
    final imported = await cubit.importContents(exportQuizJson(_quiz()));
    expect(imported, isNotNull);
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.isBusy, isFalse);
    expect(cubit.state.quizzes, hasLength(2));

    await cubit.delete(imported!);
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.quizzes, hasLength(1));
  });
}
