/// The question text on the TV is never cut off, and the answer counter of a
/// question without a board keeps a readable size.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';
import 'package:quizmo/presentation/spectator/tv_prompt.dart';

const _prompt =
    'Erkenne das Bundesland anhand großer Unternehmen mit Hauptsitz in dem '
    'jeweiligen Bundesland:\n\n'
    '- AIDA Cruises\n'
    '- Deutsche Seereederei\n'
    '- EEW Special Pipe Constructions\n'
    '- WEMAG';

Future<void> _show(WidgetTester tester, GameState game) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: QuizmoApp.buildTheme(Brightness.dark),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: TvScreen(
        state: SpectatorSessionState(
          status: QuizClientStatus.connected,
          game: game.redactedForPlayers(),
          snapshotReceivedAt: DateTime.now(),
        ),
        joinUri: Uri.parse('http://192.168.1.42:8080'),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

bool _shows(String text) => find
    .byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText().contains(text),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  for (final poker in [false, true]) {
    testWidgets(
      'a long prompt is complete on the TV${poker ? ' while betting' : ''}',
      (tester) async {
        await _show(
          tester,
          GameState(
            teams: const {
              'a': Team(id: 'a', name: 'chrome'),
              'b': Team(id: 'b', name: 'Fire'),
            },
            poker: poker
                ? PokerState.start(30, const ['a', 'b']).copyWith(betting: true)
                : null,
            round: const RoundState(
              question: ShortAnswerQuestion(
                id: 'q',
                prompt: _prompt,
                category: 'Deutschland',
                acceptedAnswers: ['Mecklenburg-Vorpommern'],
              ),
              status: RoundStatus.acceptingAnswers,
              startedAtHostMicros: 1,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(TvPrompt), findsOneWidget);
        for (final item in [
          'AIDA Cruises',
          'Deutsche Seereederei',
          'EEW Special Pipe Constructions',
          'WEMAG',
        ]) {
          expect(_shows(item), isTrue, reason: item);
        }
        // A cut off text still holds every item; its layout tells.
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('WEMAG'),
          ),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final prompt = tester.getRect(find.byType(TvPrompt));
        expect(prompt.bottom, lessThan(1080));

        // Regression: the counter of a question without a board was
        // scaled down to a few pixels.
        final counter = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              RegExp(r'^\d+ / \d+ ').hasMatch(widget.text.toPlainText()),
        );
        expect(counter, findsWidgets);
        // On screen, after every scaling of the canvas.
        expect(tester.getRect(counter.first).height, greaterThan(20));
      },
    );
  }
}
