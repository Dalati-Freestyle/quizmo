import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/correction_history_panel.dart';

void main() {
  late QuizEngineBloc engine;

  Future<void> prepare(WidgetTester tester) async {
    engine = QuizEngineBloc(
      questionBank: const [BuzzerQuestion(id: 'q', prompt: 'Question')],
      now: () => 1700000000000000,
    );
    addTearDown(engine.close);
    engine.add(const PlayerJoinedEvent(Player(id: 'p', name: 'Player One')));
    await tester.pump();
    engine.add(const StartRoundEvent('q'));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocBuilder<QuizEngineBloc, QuizEngineState>(
              bloc: engine,
              builder: (_, state) =>
                  CorrectionHistoryPanel(game: state.game, engine: engine),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Korrekturverlauf'));
    await tester.pumpAndSettle();
  }

  testWidgets('point correction validates input and records optional reason', (
    tester,
  ) async {
    await prepare(tester);
    await tester.tap(find.text('Punkte korrigieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Korrektur anwenden'));
    await tester.pumpAndSettle();
    expect(find.text('Eine ganze Zahl ungleich 0 eingeben.'), findsOneWidget);
    expect(engine.state.game.corrections, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Änderung (+/-)'),
      '12',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Grund (optional)'),
      'Host correction',
    );
    await tester.tap(find.text('Korrektur anwenden'));
    await tester.pumpAndSettle();
    expect(engine.state.game.scores.scoreOf('p'), 12);
    expect(engine.state.game.corrections.single.reason, 'Host correction');
    expect(find.textContaining('Host correction'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(engine.close);
  });

  testWidgets(
    'undo requires explicit confirmation and retains the original entry',
    (tester) async {
      await prepare(tester);
      engine.add(
        CorrectScoreEvent(
          requestId: 'original',
          playerId: 'p',
          questionId: 'q',
          roundStartedAt: engine.state.game.round.startedAtHostMicros!,
          delta: 20,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rücknahme'));
      await tester.pumpAndSettle();
      expect(find.text('Korrektur zurücknehmen?'), findsOneWidget);
      expect(engine.state.game.scores.scoreOf('p'), 20);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(engine.state.game.corrections, hasLength(1));
      await tester.tap(find.byTooltip('Rücknahme'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Grund (optional)'),
        'Mistake',
      );
      await tester.tap(find.text('Rücknahme bestätigen'));
      await tester.pumpAndSettle();
      expect(engine.state.game.scores.scoreOf('p'), 0);
      expect(engine.state.game.corrections, hasLength(2));
      expect(engine.state.game.corrections.first.id, 'score-original');
      expect(engine.state.game.corrections.last.reversesId, 'score-original');
      expect(engine.state.game.corrections.last.reason, 'Mistake');
      final buttons = tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Rücknahme',
        ),
      );
      expect(buttons.every((button) => button.onPressed == null), isTrue);
      expect(tester.takeException(), isNull);
      await tester.runAsync(engine.close);
    },
  );
}
