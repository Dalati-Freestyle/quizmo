import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';

import '../helpers/mock_lan_discovery.dart';

const prompt =
    'Welchen akademischen Abschluss hat Money Boy?\n'
    '*(auch Why SL Know Plug …; bürgerlich Sebastian Meisinger)*';

PlayerSessionState playing(Question question, {PokerState? poker}) =>
    PlayerSessionState(
      status: QuizClientStatus.connected,
      playerId: 'p',
      game: GameState(
        isStarted: true,
        players: const {'p': Player(id: 'p', name: 'Ada', teamId: 't')},
        teams: const {'t': Team(id: 't', name: 'T')},
        poker: poker,
        round: RoundState(
          question: question,
          status: RoundStatus.acceptingAnswers,
          startedAtHostMicros: 1,
        ),
      ),
    );

/// Whether some span on screen shows [text] in italics.
bool showsItalic(WidgetTester tester, String text) {
  var found = false;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          (span.text?.contains(text) ?? false) &&
          span.style?.fontStyle == FontStyle.italic) {
        found = true;
      }
      return !found;
    });
  }
  return found;
}

void main() {
  Future<PlayerSessionCubit> open(WidgetTester tester) async {
    mockLanDiscoveryUnavailable();
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    await tester.pumpAndSettle();
    return tester
        .element(find.byType(Scaffold).first)
        .read<PlayerSessionCubit>();
  }

  for (final question in [
    const ShortAnswerQuestion(
      id: 's',
      prompt: prompt,
      acceptedAnswers: ['Dr.'],
    ),
    const MultipleChoiceQuestion(
      id: 'm',
      prompt: prompt,
      options: [
        AnswerOption(id: 'a', label: 'Dr.'),
        AnswerOption(id: 'b', label: 'Prof.'),
      ],
    ),
  ]) {
    testWidgets(
      'players render the prompt as Markdown (${question.kindLabel})',
      (tester) async {
        final cubit = await open(tester);
        cubit.emit(playing(question));
        await tester.pump();
        await tester.pump();
        expect(showsItalic(tester, 'Sebastian Meisinger'), isTrue);
        expect(find.textContaining('*(', findRichText: true), findsNothing);
      },
    );
  }

  testWidgets('the poker betting view renders the prompt as Markdown', (
    tester,
  ) async {
    final cubit = await open(tester);
    cubit.emit(
      playing(
        const ShortAnswerQuestion(id: 's', prompt: prompt),
        poker: const PokerState(
          startingChips: 100,
          chips: {'t': 100},
          betting: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(showsItalic(tester, 'Sebastian Meisinger'), isTrue);
    expect(find.textContaining('*(', findRichText: true), findsNothing);
  });
}
