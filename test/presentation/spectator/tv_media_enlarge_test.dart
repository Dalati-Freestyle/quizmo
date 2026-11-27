import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

ImageAttachment picture({bool zoom = true}) => ImageAttachment(
  zoom: zoom,
  asset: MediaAsset.upload(
    Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900">'
        '<rect width="1600" height="900" fill="red"/></svg>',
      ),
    ),
    'svg',
  ),
);

GameState playing(Question question, {bool revealed = false}) => GameState(
  isStarted: true,
  players: const {'p': Player(id: 'p', name: 'Ada')},
  totalQuestionCount: 1,
  round: RoundState(
    question: question,
    startedAtHostMicros: 1,
    status: revealed ? RoundStatus.revealed : RoundStatus.acceptingAnswers,
  ),
);

void main() {
  final enlarge = find.byKey(const ValueKey('media-enlarge'));
  final enlarged = find.byKey(const ValueKey('media-enlarged'));
  final image = find.byKey(const ValueKey('media-image'));

  Future<void> show(WidgetTester tester, GameState game) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
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
    await tester.pump(const Duration(milliseconds: 500));
  }

  final question = TrueFalseQuestion(
    id: 'q',
    prompt: 'Ist das rot?',
    correctAnswer: true,
    media: [picture()],
  );

  testWidgets('a picture on the TV can fill almost the whole screen', (
    tester,
  ) async {
    await show(tester, playing(question));
    final normal = tester.getSize(image);
    expect(enlarge, findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);

    await tester.tap(enlarge);
    await tester.pump();
    expect(enlarged, findsOneWidget);
    expect(image, findsOneWidget);
    final big = tester.getSize(image);
    expect(big.width, greaterThan(1920 * 0.9));
    expect(big.height, greaterThan(1080 * 0.9));
    expect(big.height, greaterThan(normal.height));

    // Esc closes it, the stage looks as before.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(enlarged, findsNothing);
    expect(tester.getSize(image), normal);

    // So do the button and a click next to the picture.
    await tester.tap(enlarge);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('media-shrink')));
    await tester.pump();
    expect(enlarged, findsNothing);
    await tester.tap(enlarge);
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(enlarged, findsNothing);
  });

  testWidgets('the reveal keeps the enlarged picture of the question', (
    tester,
  ) async {
    await show(tester, playing(question));
    await tester.tap(enlarge);
    await tester.pump();
    await show(tester, playing(question, revealed: true));
    expect(tester.takeException(), isNull);
    expect(enlarged, findsOneWidget);
  });

  testWidgets('pictures without zoom and audio get no button', (tester) async {
    await show(
      tester,
      playing(
        TrueFalseQuestion(
          id: 'q',
          prompt: 'Ist das rot?',
          correctAnswer: true,
          media: [picture(zoom: false)],
        ),
      ),
    );
    expect(image, findsOneWidget);
    expect(enlarge, findsNothing);
  });

  testWidgets('maps can be enlarged too', (tester) async {
    await show(
      tester,
      playing(
        const TrueFalseQuestion(
          id: 'q',
          prompt: 'Wo ist das?',
          correctAnswer: true,
          media: [GeoAttachment(latitude: 48.85, longitude: 2.29, zoom: 12)],
        ),
      ),
    );
    expect(enlarge, findsOneWidget);
  });
}
