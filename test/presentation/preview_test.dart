import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';
import 'package:quizmo/core/simulation/preview_session.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_page.dart';
import 'package:quizmo/presentation/quizmaster/preview/quiz_preview_page.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';

import '../core/simulation/bot_decisions_test.dart' show simulationQuestions;
import '../core/simulation/preview_session_test.dart' show simulationQuiz, open;

Future<void> pressRestart(WidgetTester tester, String label) async {
  final callback = tester
      .widget<TextButton>(find.widgetWithText(TextButton, label))
      .onPressed;
  if (callback is! Future<void> Function()) {
    fail('Expected enabled asynchronous restart control.');
  }
  var completed = false;
  final restart = callback().whenComplete(() => completed = true);
  // Drain both stream cancellation and the simulation's fake-clock barriers.
  for (var i = 0; i < 50 && !completed; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    completed,
    isTrue,
    reason: 'Restart must finish and release old streams.',
  );
  await restart;
  await tester.pumpAndSettle();
}

void main() {
  test('preview TV clock never extrapolates beyond virtual host time', () {
    final received = DateTime.utc(2026);
    final state = SpectatorSessionState(
      extrapolateTime: false,
      snapshotReceivedAt: received,
      game: const GameState(
        hostTimeMicros: 5000000,
        round: RoundState(
          status: RoundStatus.acceptingAnswers,
          startedAtHostMicros: 0,
          question: TrueFalseQuestion(id: 'q', prompt: 'Q'),
        ),
      ),
    );
    expect(state.remainingTime(received), const Duration(seconds: 25));
    expect(
      state.remainingTime(received.add(const Duration(days: 1))),
      const Duration(seconds: 25),
    );
    expect(state.copyWith().extrapolateTime, isFalse);
  });

  for (final question in simulationQuestions) {
    for (final format in ['standard', 'jeopardy', 'poker']) {
      test('manual local player: $format / ${question.id}', () async {
        final quizFormat = switch (format) {
          'jeopardy' => JeopardyFormat(
            JeopardyBoard(
              categories: [
                JeopardyCategory(
                  name: 'Q',
                  cells: [JeopardyCell(questionId: question.id)],
                ),
              ],
              rowPoints: [100],
            ),
          ),
          'poker' => const PokerFormat(),
          _ => const StandardFormat(),
        };
        final session = PreviewSession(
          simulationQuiz(questions: [question], format: quizFormat),
        );
        addTearDown(session.close);
        final id = session.addParticipant(name: 'Manual');
        await session.flush();
        final player = PlayerSessionCubit.local(
          playerId: id,
          initialGame: session.guestGame,
          snapshots: session.guestSnapshots,
          send: session.send,
          now: () => session.clock.nowMicros,
        );
        addTearDown(player.close);
        await open(session, question.id);
        if (format == 'poker') {
          player.placePokerWager(10);
          await session.flush();
          session.send(const OpenPokerAnswersEvent());
          await session.flush();
        }
        expect(player.state.question!.hasSolution, isFalse);
        switch (question) {
          case BuzzerQuestion():
            player.buzz();
            await session.advance(const Duration(milliseconds: 350));
            session.send(const JudgeBuzzerEvent(wasCorrect: true));
          case MultipleChoiceQuestion(allowMultipleAnswers: true):
            player.chooseMultiple(question.solutionOptionIds);
          case MultipleChoiceQuestion():
            player.choose(question.solutionOptionIds.single);
          case ShortAnswerQuestion() ||
              OrderingQuestion() ||
              MatchingQuestion() ||
              EstimationQuestion() ||
              TrueFalseQuestion():
            player.submit(
              (id, timestamp, offset) => botAnswer(
                question,
                playerId: id,
                timestamp: timestamp,
                correct: true,
              ),
            );
        }
        await session.flush();
        expect(session.engine.state.game.completedQuestionIds, {question.id});
        expect(player.state.question!.hasSolution, isTrue);
        expect(
          session.engine.state.game.scores.byPlayer[id],
          format == 'poker' ? 0 : greaterThan(0),
        );
      });
    }
  }

  testWidgets(
    'editor launches unsaved draft, switches roles and leaves no persistence',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final quiz = simulationQuiz(
        questions: [
          const TrueFalseQuestion(
            id: 'secret',
            prompt: 'Visible question',
            correctAnswer: true,
            adminNotes: 'Private notes',
          ),
        ],
      );
      final repository = InMemoryQuizRepository();
      await repository.save(quiz);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: QuizEditorPage(
            repository: repository,
            quiz: quiz,
            createId: () => 'new',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Unsaved name',
      );
      await tester.tap(find.text('Preview quiz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Pause simulation'));
      await tester.pumpAndSettle();
      expect(find.text('Preview · Unsaved name'), findsOneWidget);
      expect(find.text('Embedded server'), findsNothing);
      expect(find.text('Saved game recovery'), findsNothing);
      await tester.tap(find.text('Start quiz now'));
      await tester.pumpAndSettle();
      final next = find.text('Start next pending question');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Private notes'), findsOneWidget);
      await tester.tap(find.text('Player'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalPlayerBoard), findsOneWidget);
      expect(find.text('Private notes'), findsNothing);
      final boardContext = tester.element(find.byType(LocalPlayerBoard));
      final local = boardContext.read<PlayerSessionCubit>();
      expect(local.state.question!.hasSolution, isFalse);
      local.submit(
        (id, time, offset) => TrueFalseAnswer(
          playerId: id,
          questionId: 'secret',
          clientTimestampMicros: time,
          clockOffsetMicros: offset,
          value: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(local.state.roundStatus, RoundStatus.revealed);
      await tester.tap(find.text('TV'));
      await tester.pumpAndSettle();
      final tv = tester.widget<TvScreen>(find.byType(TvScreen));
      expect(tv.state.game!.questionBank, isEmpty);
      expect(tv.state.game!.round.question!.adminNotes, isEmpty);
      await pressRestart(tester, 'Replay round');
      expect(
        tester
            .widget<TvScreen>(find.byType(TvScreen))
            .state
            .game!
            .round
            .answers,
        isEmpty,
      );
      await pressRestart(tester, 'Restart preview');
      expect(
        tester
            .widget<TvScreen>(find.byType(TvScreen))
            .state
            .game!
            .round
            .question,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QuizPreviewPage), findsNothing);
      expect((await repository.loadAll()).single, quiz);
      expect(find.text('Unsaved name'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bot dialog rejects invalid delay ranges and creates configurable bots',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: QuizPreviewPage(quiz: simulationQuiz(), seed: 1)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Pause simulation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add test participant'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Minimum delay (ms)'),
        '2000',
      );
      await tester.pump();
      final add = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(add.onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Maximum delay (ms)'),
        '2500',
      );
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Bot: 70% · 2000–2500 ms'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove test participant').last);
      await tester.pumpAndSettle();
      expect(find.text('Bot: 70% · 2000–2500 ms'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview controls and all three views fit a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: QuizPreviewPage(
          quiz: simulationQuiz(questions: [simulationQuestions.last]),
          seed: 1,
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Pause simulation'));
    await tester.tap(find.byTooltip('Pause simulation'));
    await tester.pumpAndSettle();
    for (final role in ['Player', 'TV', 'Host']) {
      await tester.ensureVisible(find.text(role));
      await tester.tap(find.text(role));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
