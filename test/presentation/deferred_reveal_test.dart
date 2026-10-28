import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_page.dart';
import 'package:quizmo/presentation/quizmaster/editor/selection_dropdown.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

const first = RoundState(
  status: RoundStatus.revealed,
  startedAtHostMicros: 1,
  question: TrueFalseQuestion(id: 'q1', prompt: 'First?', correctAnswer: true),
  answers: {
    'p': TrueFalseAnswer(
      playerId: 'p',
      questionId: 'q1',
      clientTimestampMicros: 2,
      clockOffsetMicros: 0,
      value: true,
    ),
  },
);
const second = RoundState(
  status: RoundStatus.revealed,
  startedAtHostMicros: 3,
  question: ShortAnswerQuestion(
    id: 'q2',
    prompt: 'Second?',
    acceptedAnswers: ['Berlin'],
    manualGrading: true,
    solutionMedia: [CodeAttachment(code: 'secret solution', language: 'text')],
    adminNotes: 'private host note',
  ),
  answers: {
    'p': ShortAnswer(
      playerId: 'p',
      questionId: 'q2',
      clientTimestampMicros: 4,
      clockOffsetMicros: 0,
      text: 'Hamburg',
    ),
  },
  answerVerdicts: {'p': 1},
);
const host = GameState(
  revealMode: SolutionRevealMode.atEnd,
  players: {'p': Player(id: 'p', name: 'Spieler')},
  round: first,
  roundHistory: [first],
  scores: ScoreState(byPlayer: {'p': 20}),
  completedQuestionIds: {'q1'},
);
final finished = host
    .copyWith(
      isFinished: true,
      round: second,
      roundHistory: [first, second],
      completedQuestionIds: {'q1', 'q2'},
    )
    .redactedForPlayers();

void main() {
  for (final mode in SolutionRevealMode.values) {
    testWidgets('editor persists reveal mode ${mode.name}', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = InMemoryQuizRepository();
      final quiz = Quiz(
        id: 'quiz',
        name: 'Reveal quiz',
        description: 'Description',
        category: 'Test',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        format: StandardFormat(
          revealMode: mode == SolutionRevealMode.atEnd
              ? SolutionRevealMode.afterEachQuestion
              : SolutionRevealMode.atEnd,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QuizEditorPage(
            repository: repository,
            quiz: quiz,
            createId: () => 'new',
          ),
        ),
      );
      final dropdown = find.byType(SelectionDropdown<SolutionRevealMode>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              mode == SolutionRevealMode.atEnd
                  ? 'Am Quizende'
                  : 'Nach jeder Frage',
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save quiz'));
      await tester.pumpAndSettle();
      expect(
        (await repository.loadAll()).single.format,
        StandardFormat(revealMode: mode),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'player waits without feedback, then sees all questions and own answers',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
      await tester.pumpAndSettle();
      final cubit = tester
          .element(find.byType(Scaffold))
          .read<PlayerSessionCubit>();
      cubit.emit(
        PlayerSessionState(
          status: QuizClientStatus.connected,
          playerId: 'p',
          game: host.redactedForPlayers(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Frage abgeschlossen. Die Auflösung folgt am Quizende.'),
        findsOneWidget,
      );
      expect(find.text('20'), findsNothing);
      expect(find.textContaining('Richtig!'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      cubit.emit(cubit.state.copyWith(game: finished));
      await tester.pumpAndSettle();
      expect(find.text('Quiz-Auflösung'), findsOneWidget);
      expect(find.text('1. First?'), findsOneWidget);
      expect(find.text('2. Second?'), findsOneWidget);
      expect(find.text('Dein Punktestand: 20'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('2. Second?'));
      await tester.pumpAndSettle();
      expect(find.text('Deine Antwort: Hamburg'), findsOneWidget);
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.textContaining('private host note'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV hides interim scores and rotates the final solution overview',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> show(GameState game) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvScreen(
              state: SpectatorSessionState(
                status: QuizClientStatus.connected,
                game: game,
              ),
              joinUri: Uri.parse('http://localhost:8080'),
            ),
          ),
        ),
      );
      await show(host.redactedForPlayers());
      expect(
        find.text('Punktestand bis zum Quizende verborgen.'),
        findsOneWidget,
      );
      expect(find.textContaining('Lösung:'), findsNothing);
      await show(finished);
      await tester.pumpAndSettle();
      expect(find.text('Quiz-Auflösung · 1 / 2'), findsOneWidget);
      expect(find.text('First?'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.text('Quiz-Auflösung · 2 / 2'), findsOneWidget);
      expect(find.text('Lösung: Berlin'), findsOneWidget);
      await tester.tap(find.byTooltip('Automatischen Wechsel pausieren'));
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Quiz-Auflösung · 2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Vorherige Lösung'));
      await tester.pumpAndSettle();
      expect(find.text('Quiz-Auflösung · 1 / 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 20));
      expect(tester.takeException(), isNull);
    },
  );
}
