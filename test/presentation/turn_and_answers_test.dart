import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/questions/multiple_choice_question_view.dart';
import 'package:quizmo/presentation/quizmaster/host_dashboard_page.dart';

import '../helpers/memory_recovery_store.dart';
import '../helpers/mock_lan_discovery.dart';

const question = MultipleChoiceQuestion(
  id: 'q',
  prompt: 'Pick A and C',
  allowMultipleAnswers: true,
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
    AnswerOption(id: 'c', label: 'C'),
  ],
);
const board = JeopardyBoard(
  rowPoints: [100],
  categories: [
    JeopardyCategory(
      name: 'Category',
      cells: [JeopardyCell(questionId: 'q')],
    ),
  ],
);

void main() {
  setUp(mockLanDiscoveryUnavailable);
  testWidgets(
    'multiple choice toggles options, submits once and then locks every button',
    (tester) async {
      final submitted = <List<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultipleChoiceQuestionView(
              question: question,
              status: RoundStatus.acceptingAnswers,
              selectedOptionId: null,
              onSelect: (_) => fail('Must submit a set'),
              onSubmitMultiple: submitted.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.tap(find.text('C'));
      await tester.pump();
      expect(submitted, isEmpty);
      await tester.tap(find.text('Antworten einloggen'));
      await tester.pump();
      expect(submitted, [
        ['a', 'c'],
      ]);
      await tester.tap(find.text('B'));
      await tester.tap(find.text('Antworten einloggen'));
      await tester.pump();
      expect(submitted.length, 1);
    },
  );

  testWidgets(
    'single option press locks immediately before any server snapshot',
    (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultipleChoiceQuestionView(
              question: const MultipleChoiceQuestion(
                id: 'q',
                prompt: 'Pick',
                options: [
                  AnswerOption(id: 'a', label: 'A'),
                  AnswerOption(id: 'b', label: 'B'),
                ],
              ),
              status: RoundStatus.acceptingAnswers,
              selectedOptionId: null,
              onSelect: submitted.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('A'));
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(submitted, ['a']);
    },
  );

  testWidgets('solo player sees own turn and other players cannot choose', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    final cubit = tester
        .element(find.byType(Scaffold))
        .read<PlayerSessionCubit>();
    final game = GameState(
      players: const {
        'p': Player(id: 'p', name: 'Player'),
        'other': Player(id: 'other', name: 'Other'),
      },
      jeopardy: const JeopardyState(board: board, currentTeamId: 'p'),
    );
    cubit.emit(
      PlayerSessionState(
        status: QuizClientStatus.connected,
        playerId: 'p',
        game: game.copyWith(isStarted: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Du bist dran! Wähle die nächste Frage.'), findsOneWidget);
    cubit.emit(
      PlayerSessionState(
        status: QuizClientStatus.connected,
        playerId: 'other',
        game: game.copyWith(isStarted: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Player ist dran.'), findsOneWidget);
    expect(find.text('Du bist dran! Wähle die nächste Frage.'), findsNothing);
  });

  testWidgets('host popup rejects and confirms the pending player selection', (
    tester,
  ) async {
    final quiz = Quiz(
      id: 'quiz',
      name: 'Quiz',
      description: 'Test',
      category: 'Test',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: const [
        TrueFalseQuestion(id: 'q', prompt: 'True?', correctAnswer: true),
      ],
      format: const JeopardyFormat(board),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HostDashboardPage(
          quiz: quiz,
          recoveryStore: MemoryRecoveryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final engine = tester.element(find.byType(Scaffold)).read<QuizEngineBloc>();
    engine.add(const PlayerJoinedEvent(Player(id: 'p', name: 'Player')));
    await tester.pumpAndSettle();
    engine.add(const SelectJeopardyCellEvent('q', playerId: 'p'));
    await tester.pumpAndSettle();
    expect(engine.state.game.jeopardy!.pendingPickQuestionId, isNull);
    expect(find.text('Fragenauswahl bestätigen'), findsNothing);
    await tester.ensureVisible(find.text('Quiz jetzt starten'));
    await tester.tap(find.text('Quiz jetzt starten'));
    await tester.pumpAndSettle();
    engine.add(const SelectJeopardyCellEvent('q', playerId: 'p'));
    await tester.pumpAndSettle();
    expect(find.text('Fragenauswahl bestätigen'), findsOneWidget);
    expect(engine.state.game.round.question, isNull);
    await tester.tap(find.text('Ablehnen'));
    await tester.pumpAndSettle();
    expect(engine.state.game.round.question, isNull);
    expect(engine.state.game.jeopardy!.pendingPickQuestionId, isNull);
    engine.add(const SelectJeopardyCellEvent('q', playerId: 'p'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();
    expect(engine.state.game.round.question!.id, 'q');
    expect(tester.takeException(), isNull);
  });
}
