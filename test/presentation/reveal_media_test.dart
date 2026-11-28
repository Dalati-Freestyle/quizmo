import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/common/media_playback.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/common/reveal_media.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

AudioAttachment audio(int seed) => AudioAttachment(
  asset: MediaAsset.upload(
    Uint8List.fromList([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, seed]),
    'mp3',
  ),
);

final questionAudio = audio(1);
final solutionAudio = audio(2);

final question = TrueFalseQuestion(
  id: 'q',
  prompt: 'Welches Lied ist das?',
  correctAnswer: true,
  media: [questionAudio],
  solutionMedia: [solutionAudio],
);

const next = TrueFalseQuestion(id: 'q2', prompt: 'Und jetzt?');

/// The media lists currently on screen.
List<List<MediaAttachment>> shownMedia(WidgetTester tester) => [
  for (final view in tester.widgetList<QuestionMediaView>(
    find.byType(QuestionMediaView),
  ))
    view.media,
];

void main() {
  group('engine', () {
    late QuizEngineBloc engine;
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    setUp(() {
      engine = QuizEngineBloc(questionBank: [question, next]);
    });
    tearDown(() => engine.close());

    test('the host switches the TV only after the reveal', () async {
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'Ada')));
      await send(const StartRoundEvent('q'));
      await send(const ShowRevealMediaEvent(questionMedia: true));
      expect(engine.state.game.round.showsQuestionMedia, isFalse);

      await send(const RevealRoundEvent());
      await send(const ShowRevealMediaEvent(questionMedia: true));
      expect(engine.state.game.round.showsQuestionMedia, isTrue);
      // Guests follow the host.
      expect(
        engine.state.game.redactedForPlayers().round.showsQuestionMedia,
        isTrue,
      );
      final saved = RoundState.fromJson(engine.state.game.round.toJson());
      expect(saved.showsQuestionMedia, isTrue);

      await send(const NextQuestionEvent());
      expect(engine.state.game.round.question?.id, 'q2');
      expect(engine.state.game.round.showsQuestionMedia, isFalse);
    });

    test('a question without solution media cannot switch', () async {
      engine = QuizEngineBloc(questionBank: [next]);
      await send(const StartRoundEvent('q2'));
      await send(const RevealRoundEvent());
      await send(const ShowRevealMediaEvent(questionMedia: true));
      expect(engine.state.game.round.showsQuestionMedia, isFalse);
    });
  });

  test('which media are visible', () {
    final before = visibleQuestionMedia(question, RoundStatus.acceptingAnswers);
    expect((before.question, before.solution), (true, false));
    final after = visibleQuestionMedia(question, RoundStatus.revealed);
    expect((after.question, after.solution), (false, true));
    final back = visibleQuestionMedia(
      question,
      RoundStatus.revealed,
      questionSide: true,
    );
    expect((back.question, back.solution), (true, false));
    final none = visibleQuestionMedia(
      TrueFalseQuestion(id: 'x', prompt: '?', media: [questionAudio]),
      RoundStatus.revealed,
    );
    expect((none.question, none.solution), (true, false));
    expect(
      offersRevealMediaToggle(
        TrueFalseQuestion(id: 'x', prompt: '?', media: [questionAudio]),
        RoundStatus.revealed,
      ),
      isFalse,
    );
  });

  group('TV', () {
    Future<void> show(WidgetTester tester, GameState game) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // No players: the test only looks at what is on stage.
            body: StillMedia(
              child: TvScreen(
                state: SpectatorSessionState(
                  status: QuizClientStatus.connected,
                  game: game,
                ),
                joinUri: Uri.parse('http://localhost:8080'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    GameState playing({required bool revealed, bool questionSide = false}) =>
        GameState(
          isStarted: true,
          players: const {'p': Player(id: 'p', name: 'Ada')},
          totalQuestionCount: 2,
          round: RoundState(
            question: question,
            startedAtHostMicros: 1,
            status: revealed
                ? RoundStatus.revealed
                : RoundStatus.acceptingAnswers,
            showsQuestionMedia: questionSide,
          ),
        );

    testWidgets('shows only the solution audio after the reveal', (
      tester,
    ) async {
      await show(tester, playing(revealed: false));
      expect(shownMedia(tester).first, [questionAudio]);
      expect(
        shownMedia(tester).expand((m) => m),
        isNot(contains(solutionAudio)),
      );

      await show(tester, playing(revealed: true));
      final shown = shownMedia(tester).expand((m) => m).toSet();
      expect(shown, contains(solutionAudio));
      expect(shown, isNot(contains(questionAudio)));

      await show(tester, playing(revealed: true, questionSide: true));
      final back = shownMedia(tester).expand((m) => m).toSet();
      expect(back, contains(questionAudio));
      expect(back, isNot(contains(solutionAudio)));
    });
  });

  testWidgets('a player switches on the own device, default is the solution', (
    tester,
  ) async {
    var status = RoundStatus.revealed;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StillMedia(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return LocalRevealMedia(
                  question: question,
                  status: status,
                  builder: (context, visible, toggle) => Column(
                    children: [
                      ?toggle,
                      if (visible.question)
                        QuestionMediaView(media: question.media),
                      if (visible.solution)
                        QuestionMediaView(media: question.solutionMedia),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(shownMedia(tester), [
      [solutionAudio],
    ]);
    await tester.tap(find.text('Frage'));
    await tester.pump();
    expect(shownMedia(tester), [
      [questionAudio],
    ]);
    await tester.tap(find.text('Lösung'));
    await tester.pump();
    expect(shownMedia(tester), [
      [solutionAudio],
    ]);
    // A new round starts with the media of the question again.
    await tester.tap(find.text('Frage'));
    await tester.pump();
    update(() => status = RoundStatus.acceptingAnswers);
    await tester.pump();
    expect(find.byKey(const ValueKey('reveal-media-toggle')), findsNothing);
    update(() => status = RoundStatus.revealed);
    await tester.pump();
    expect(shownMedia(tester), [
      [solutionAudio],
    ]);
  });
}
