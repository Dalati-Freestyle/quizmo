import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/media_aspect.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/common/info_slide_view.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

ImageAttachment picture(int width, int height, {String fill = 'red'}) =>
    ImageAttachment(
      asset: MediaAsset.upload(
        Uint8List.fromList(
          utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
            'height="$height"><rect width="$width" height="$height" '
            'fill="$fill"/></svg>',
          ),
        ),
        'svg',
      ),
    );

const _options = [
  AnswerOption(id: 'a', label: 'Berlin'),
  AnswerOption(id: 'b', label: 'Hamburg'),
  AnswerOption(id: 'c', label: 'München'),
  AnswerOption(id: 'd', label: 'Köln'),
  AnswerOption(id: 'e', label: 'Eine wirklich ziemlich lange Antwort'),
  AnswerOption(id: 'f', label: 'Bremen'),
];

List<Question> questions(List<MediaAttachment> media) => [
  MultipleChoiceQuestion(
    id: 'q',
    prompt: 'Welche Stadt ist das?',
    options: _options,
    correctOptionId: 'a',
    media: media,
    solutionMedia: [picture(1600, 900, fill: 'blue')],
  ),
  ShortAnswerQuestion(
    id: 'q',
    prompt: 'Eine lange Frage? ' * 20,
    acceptedAnswers: const ['x'],
    media: media,
  ),
  OrderingQuestion(
    id: 'q',
    prompt: 'Ordnen',
    items: _options,
    correctOrder: const ['a', 'b', 'c', 'd', 'e', 'f'],
    media: media,
  ),
  MatchingQuestion(
    id: 'q',
    prompt: 'Zuordnen',
    leftItems: _options,
    rightItems: _options,
    correctPairs: {for (final o in _options) o.id: o.id},
    media: media,
  ),
  EstimationQuestion(
    id: 'q',
    prompt: 'Schätzen',
    correctValue: 3,
    media: media,
  ),
  TrueFalseQuestion(
    id: 'q',
    prompt: 'Wahr?',
    correctAnswer: true,
    media: media,
  ),
  BuzzerQuestion(id: 'q', prompt: 'Buzzer', expectedAnswer: 'x', media: media),
];

void main() {
  final images = find.byKey(const ValueKey('media-image'));

  group('aspect ratios', () {
    test('are read from SVG, PNG, JPEG, WebP and MP4 headers', () {
      double? of(List<int> bytes, String mime) =>
          mediaAspectRatio(Uint8List.fromList(bytes), mime);
      expect(picture(320, 200).asset.aspectRatio, closeTo(1.6, 1e-9));
      expect(
        of(utf8.encode('<svg viewBox="0 0 30 10"></svg>'), 'image/svg+xml'),
        3,
      );
      expect(
        of([
          ...[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82],
          ...[0, 0, 2, 0, 0, 0, 1, 0],
        ], 'image/png'),
        2,
      );
      const frame = [0xFF, 0xC0, 0, 11, 8, 0, 100, 0, 200, 1, 0, 0, 0];
      expect(of([0xFF, 0xD8, ...frame], 'image/jpeg'), 2);
      // EXIF orientation 6: shown turned by 90 degrees.
      const exif = [
        0xFF, 0xE1, 0, 34, 0x45, 0x78, 0x69, 0x66, 0, 0, //
        0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0, //
        0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
      ];
      expect(of([0xFF, 0xD8, ...exif, ...frame], 'image/jpeg'), 0.5);
      expect(
        of([
          ...ascii.encode('RIFF0000WEBPVP8X'),
          ...[0, 0, 0, 0, 0, 0, 0, 0, 99, 0, 0, 49, 0, 0],
        ], 'image/webp'),
        2,
      );
      final header = List.filled(8, 0) + ascii.encode('tkhd');
      final body = List.filled(100, 0);
      body[4 + 20 + 16 + 0 + 1] = 1; // matrix a = 1.0
      body[4 + 20 + 16 + 36 + 0] = 2; // width 512
      body[4 + 20 + 16 + 40 + 0] = 1; // height 256
      expect(of(header + body, 'video/mp4'), 2);
      expect(of([1, 2, 3], 'image/png'), isNull);
      expect(of([1, 2, 3], 'audio/mpeg'), isNull);
    });

    test('travel with the reference, but never into quiz files', () {
      final image = picture(300, 100);
      final wire = MediaAttachment.fromJson(image.forWire());
      expect(wire.asset!.data, isNull);
      expect(wire.asset!.aspectRatio, 3);
      expect(jsonEncode(image.toJson()), isNot(contains('aspectRatio')));
    });
  });

  group('TV', () {
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

    GameState playing(Question question, {bool revealed = false}) => GameState(
      isStarted: true,
      players: const {'p': Player(id: 'p', name: 'Ada')},
      totalQuestionCount: 3,
      round: RoundState(
        question: question,
        startedAtHostMicros: 1,
        status: revealed ? RoundStatus.revealed : RoundStatus.acceptingAnswers,
      ),
    );

    testWidgets('a slide with only a picture fills the stage', (tester) async {
      await show(
        tester,
        GameState(
          isStarted: true,
          activeSlide: InfoSlide(id: 's', media: [picture(1600, 900)]),
        ),
      );
      final stage = tester.getSize(find.byType(InfoSlideView));
      final image = tester.getSize(images);
      expect(image.width, closeTo(stage.width, 1));
      expect(image.height, greaterThan(stage.height - 24));
      expect(find.text('Vergrößern'), findsNothing);
    });

    testWidgets('title and text leave the rest to the picture', (tester) async {
      await show(
        tester,
        GameState(
          isStarted: true,
          activeSlide: InfoSlide(
            id: 's',
            title: 'Ein Titel',
            text: 'Viel Text ' * 60,
            media: [picture(1600, 900)],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final stage = tester.getSize(find.byType(InfoSlideView));
      expect(tester.getSize(images).height, greaterThan(stage.height * 0.45));
    });

    for (final (name, media) in [
      ('landscape', [picture(1600, 900)]),
      ('portrait', [picture(600, 1400)]),
      ('very wide', [picture(3000, 200)]),
      ('tiny', [picture(8, 8)]),
      ('several', [picture(1600, 900), picture(900, 1600, fill: 'green')]),
    ]) {
      testWidgets('every kind shows $name pictures large and complete', (
        tester,
      ) async {
        for (final question in questions(media)) {
          for (final revealed in [false, true]) {
            await show(
              tester,
              playing(
                revealed ? question : question.redacted(),
                revealed: revealed,
              ),
            );
            final reason = '${question.kindLabel} revealed=$revealed';
            expect(tester.takeException(), isNull, reason: reason);
            expect(
              images,
              findsNWidgets(
                media.length + (revealed ? question.solutionMedia.length : 0),
              ),
              reason: reason,
            );
            // The box used to be 240 px high, whatever space was left.
            if (media.length == 1 && !revealed) {
              expect(
                tester.getSize(images.first).height,
                greaterThan(340),
                reason: reason,
              );
            }
            expect(find.text('Vergrößern'), findsNothing);
            if (question is MultipleChoiceQuestion) {
              for (final option in _options) {
                expect(find.text(option.label), findsOneWidget, reason: reason);
              }
              expect(
                find.ancestor(
                  of: find.text('Bremen'),
                  matching: find.byType(Scrollable),
                ),
                findsNothing,
                reason: 'nobody scrolls on a TV',
              );
            }
          }
        }
      });
    }

    testWidgets('hints next to media still fit', (tester) async {
      for (final question in questions([picture(1600, 900)])) {
        final hinted = Question.fromJson({
          ...question.toJson(),
          'hints': [
            QuestionHint(text: 'Ein Tipp', media: [picture(400, 400)]).toJson(),
          ],
        });
        await show(
          tester,
          GameState(
            isStarted: true,
            round: RoundState(
              question: hinted,
              startedAtHostMicros: 1,
              status: RoundStatus.acceptingAnswers,
              hintTimesMicros: const [2],
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: question.kindLabel);
        expect(images, findsNWidgets(2));
      }
    });
  });

  group('player and host', () {
    Future<void> show(
      WidgetTester tester,
      Size size,
      List<MediaAttachment> media, {
      double scale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: QuestionMediaView(media: media)),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('a phone uses the full width, never more than the screen', (
      tester,
    ) async {
      for (final size in [const Size(360, 740), const Size(740, 360)]) {
        for (final image in [
          picture(1600, 900),
          picture(900, 1600),
          picture(500, 500),
          picture(3000, 300),
          picture(4, 4),
        ]) {
          await show(tester, size, [image], scale: 2);
          final box = tester.getSize(images);
          expect(box.width, size.width);
          expect(box.height, lessThanOrEqualTo(size.height * 0.6 + 1));
        }
      }
      await show(tester, const Size(360, 740), [picture(1600, 900)]);
      expect(tester.getSize(images).height, closeTo(360 * 9 / 16, 1));
      expect(find.text('Vergrößern'), findsOneWidget);
    });

    testWidgets('several media stand side by side on a wide screen', (
      tester,
    ) async {
      final media = [picture(1600, 900), picture(1600, 900, fill: 'green')];
      await show(tester, const Size(1200, 900), media);
      expect(
        tester.getTopLeft(images.first).dy,
        tester.getTopLeft(images.last).dy,
      );
      await show(tester, const Size(360, 740), media);
      expect(
        tester.getTopLeft(images.first).dx,
        tester.getTopLeft(images.last).dx,
      );
    });

    testWidgets('the space is reserved while a picture loads', (tester) async {
      final image = picture(1000, 500);
      final reference = MediaAttachment.fromJson(image.forWire());
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuestionMediaView(media: [reference]),
            ),
          ),
        ),
      );
      final loading = tester.getSize(find.byType(QuestionMediaView)).height;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuestionMediaView(
                media: [ImageAttachment(asset: image.asset, zoom: false)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(QuestionMediaView).first).height,
        closeTo(loading, 1),
      );
    });

    testWidgets('the round monitor keeps its controls reachable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LiveRoundPanel(
                state: QuizEngineState(
                  game: GameState(
                    isStarted: true,
                    round: RoundState(
                      question: questions([picture(600, 1400)]).first,
                      startedAtHostMicros: 1,
                      status: RoundStatus.acceptingAnswers,
                    ),
                  ),
                ),
                onJudge: (_) {},
                onReveal: () {},
                onLock: () {},
                onNext: () {},
                onCloseRound: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(images).height, lessThan(900 * 0.43));
      expect(tester.getSize(images).height, greaterThan(300));
    });
  });
}
