import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/questions/new_question_views.dart';

const _leftLabel = 'Eine lange Beschreibung, die mehrere Zeilen benötigt';
const _rightLabel = 'Eine ausführliche Antwort mit mehreren Wörtern und Zeilen';
const _matching = MatchingQuestion(
  id: 'matching',
  prompt: 'Ordne die Begriffe zu.',
  leftItems: [AnswerOption(id: 'a', label: _leftLabel)],
  rightItems: [
    AnswerOption(id: 'x', label: _rightLabel),
    AnswerOption(
      id: 'y',
      label: 'Eine andere ausführliche Antwort zur Auswahl',
    ),
  ],
);

Future<void> _pumpPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: QuizmoApp.buildTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(1.5)),
        child: child!,
      ),
      home: child,
    ),
  );
}

void main() {
  const questions = <Question>[
    ShortAnswerQuestion(id: 'short', prompt: _leftLabel),
    EstimationQuestion(id: 'estimate', prompt: _leftLabel, unit: 'Kilometer'),
    TrueFalseQuestion(id: 'boolean', prompt: _leftLabel),
    OrderingQuestion(
      id: 'order',
      prompt: _leftLabel,
      items: [
        AnswerOption(id: 'a', label: _leftLabel),
        AnswerOption(id: 'b', label: _rightLabel),
      ],
    ),
    _matching,
    MultipleChoiceQuestion(
      id: 'choice',
      prompt: _leftLabel,
      options: [
        AnswerOption(id: 'a', label: _leftLabel),
        AnswerOption(id: 'b', label: _rightLabel),
      ],
    ),
    BuzzerQuestion(id: 'buzzer', prompt: _leftLabel),
  ];
  for (final size in [const Size(320, 640), const Size(740, 360)]) {
    for (final question in questions) {
      testWidgets('${question.kindLabel} fits $size with large text', (
        tester,
      ) async {
        await _pumpPhone(tester, const PlayerPage());
        tester.view.physicalSize = size;
        final cubit = tester
            .element(find.byType(Scaffold))
            .read<PlayerSessionCubit>();
        cubit.emit(
          PlayerSessionState(
            status: QuizClientStatus.connected,
            playerId: 'p',
            game: GameState(
              players: const {'p': Player(id: 'p', name: 'Spieler')},
              round: RoundState(
                question: question,
                status: RoundStatus.acceptingAnswers,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(question.prompt), findsWidgets);
        expect(tester.takeException(), isNull);
        final input = find.byType(TextField);
        if (input.evaluate().isNotEmpty) {
          await tester.ensureVisible(input);
          await tester.tap(input);
          tester.view.viewInsets = const FakeViewPadding(bottom: 200);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(FilledButton).first);
          expect(find.byType(FilledButton).first.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('matching keeps long labels clear of the field and menu rows', (
    tester,
  ) async {
    await _pumpPhone(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: MatchingQuestionView(
            question: _matching,
            enabled: true,
            onSubmit: (_) {},
          ),
        ),
      ),
    );
    final field = find.byType(DropdownButtonFormField<String>);
    expect(
      tester.getRect(field).top - tester.getRect(find.text(_leftLabel)).bottom,
      greaterThanOrEqualTo(8),
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    final options = find.byType(DropdownMenuItem<String>).hitTestable();
    expect(options, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      final item = options.at(i);
      final text = find.descendant(of: item, matching: find.byType(Text));
      final itemRect = tester.getRect(item);
      final textRect = tester.getRect(text);
      expect(textRect.top, greaterThanOrEqualTo(itemRect.top));
      expect(textRect.bottom, lessThanOrEqualTo(itemRect.bottom));
    }
    await tester.tap(find.text(_rightLabel).last);
    await tester.pumpAndSettle();
    final selectedText = find.text(_rightLabel).hitTestable();
    final fieldRect = tester.getRect(field);
    expect(
      tester.getRect(selectedText).bottom,
      lessThanOrEqualTo(fieldRect.bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('answer page separates the prompt, field, button and solution', (
    tester,
  ) async {
    const question = ShortAnswerQuestion(
      id: 'short',
      prompt: 'Welche Stadt ist die Hauptstadt von Deutschland?',
      acceptedAnswers: ['Berlin'],
    );
    await _pumpPhone(tester, const PlayerPage());
    final cubit = tester
        .element(find.byType(Scaffold))
        .read<PlayerSessionCubit>();
    cubit.emit(
      const PlayerSessionState(
        status: QuizClientStatus.connected,
        playerId: 'p',
        game: GameState(
          players: {'p': Player(id: 'p', name: 'Spieler')},
          round: RoundState(question: question, status: RoundStatus.revealed),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final promptRect = tester.getRect(find.text(question.prompt));
    final fieldRect = tester.getRect(find.byType(TextField));
    final buttonRect = tester.getRect(find.byType(FilledButton));
    final solutionRect = tester.getRect(
      find.text('Lösung: ${question.solutionLabel}'),
    );
    expect(fieldRect.top - promptRect.bottom, greaterThanOrEqualTo(16));
    expect(buttonRect.top - fieldRect.bottom, greaterThanOrEqualTo(12));
    expect(solutionRect.top - buttonRect.bottom, greaterThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });
}
