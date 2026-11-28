import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/protocol/messages.dart';
import 'package:quizmo/core/simulation/preview_session.dart';
import 'package:quizmo/presentation/common/media_playback.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/game_sections.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

import '../core/simulation/preview_session_test.dart' show simulationQuiz;

// On Windows a YouTube attachment is only a button, so no player is needed.
VideoAttachment _video(String id) => VideoAttachment(youtubeId: id);

final _question = TrueFalseQuestion(
  id: 'q1',
  prompt: 'One?',
  correctAnswer: true,
  timeLimit: Duration.zero,
  media: [_video('dQw4w9WgXcQ')],
  solutionMedia: [_video('dQw4w9WgXcA')],
  hints: [
    QuestionHint(media: [_video('dQw4w9WgXcB')]),
  ],
);
final _second = TrueFalseQuestion(
  id: 'q2',
  prompt: 'Two?',
  correctAnswer: true,
  timeLimit: Duration.zero,
  media: [_video('dQw4w9WgXcC')],
);

void main() {
  late PreviewSession session;

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session = PreviewSession(
      simulationQuiz(questions: [_question, _second]).copyWith(
        slides: [
          InfoSlide(
            id: 'slide',
            title: 'Pause',
            media: [_video('dQw4w9WgXcD')],
            beforeQuestionId: 'q2',
          ),
        ],
      ),
    );
    addTearDown(session.close);
    session.send(const StartGameEvent());
    await tester.runAsync(session.flush);
  }

  Future<void> send(WidgetTester tester, QuizEngineEvent event) async {
    session.send(event);
    await tester.runAsync(session.flush);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The playback of the media with the YouTube id [id].
  MediaPlayback? playbackOf(WidgetTester tester, String id) {
    for (final view in tester.widgetList<QuestionMediaView>(
      find.byWidgetPredicate((w) => w.runtimeType == QuestionMediaView),
    )) {
      if (view.media.any((m) => m is VideoAttachment && m.youtubeId == id)) {
        return view.playback;
      }
    }
    return null;
  }

  Future<PlayerSessionCubit> showPlayer(WidgetTester tester) async {
    final id = session.addParticipant(name: 'Ada');
    await tester.runAsync(session.flush);
    final player = PlayerSessionCubit.local(
      playerId: id,
      initialGame: session.guestGame,
      snapshots: session.guestSnapshots,
      send: session.send,
      now: () => session.clock.nowMicros,
      answers: () => session.answersOf(id),
    );
    addTearDown(player.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: player,
            child: const LocalPlayerBoard(),
          ),
        ),
      ),
    );
    return player;
  }

  Future<void> showTv(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TvScreen(
          state: SpectatorSessionState(
            status: QuizClientStatus.connected,
            game: session.guestGame,
          ),
          joinUri: Uri.parse('http://localhost:8080'),
        ),
      ),
    ),
  );

  const windows = TargetPlatformVariant({TargetPlatform.windows});

  testWidgets('players never start by themselves, also after commands', (
    tester,
  ) async {
    await start(tester);
    await send(tester, const StartRoundEvent('q1'));
    await showPlayer(tester);
    await tester.pump();
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.onDemand);
    for (final action in [TvMediaAction.play, TvMediaAction.restart]) {
      await send(tester, ControlTvMediaEvent(action));
      expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.onDemand);
    }
    await send(tester, const ControlTvMediaEvent(TvMediaAction.pause));
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.paused);
    expect(find.text('Von der Spielleitung pausiert'), findsOneWidget);
    await send(tester, const ControlTvMediaEvent(TvMediaAction.pause));
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.paused);

    // A new hint ends the pause; the question stops, nothing starts.
    await send(tester, const ShowHintEvent(questionId: 'q1', shownHints: 0));
    expect(playbackOf(tester, 'dQw4w9WgXcB'), MediaPlayback.onDemand);
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.stopped);
    await send(tester, const ControlTvMediaEvent(TvMediaAction.pause));
    expect(playbackOf(tester, 'dQw4w9WgXcB'), MediaPlayback.paused);

    // So does the reveal, and the next question starts on demand again.
    await send(tester, const RevealRoundEvent());
    await tester.runAsync(() => session.advance(const Duration(seconds: 1)));
    await tester.pump();
    expect(playbackOf(tester, 'dQw4w9WgXcA'), MediaPlayback.onDemand);
    await send(tester, const StartRoundEvent('q2'));
    expect(playbackOf(tester, 'dQw4w9WgXcC'), MediaPlayback.onDemand);
    expect(tester.takeException(), isNull);
  }, variant: windows);

  testWidgets('a slide can be paused everywhere and starts fresh next time', (
    tester,
  ) async {
    await start(tester);
    await send(tester, const ShowSlideEvent('slide'));
    await showPlayer(tester);
    await tester.pump();
    expect(playbackOf(tester, 'dQw4w9WgXcD'), MediaPlayback.onDemand);
    await send(tester, const ControlTvMediaEvent(TvMediaAction.pause));
    expect(playbackOf(tester, 'dQw4w9WgXcD'), MediaPlayback.paused);

    await showTv(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(playbackOf(tester, 'dQw4w9WgXcD'), MediaPlayback.paused);
    session.send(const ControlTvMediaEvent(TvMediaAction.play));
    await tester.runAsync(session.flush);
    await showTv(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(playbackOf(tester, 'dQw4w9WgXcD'), MediaPlayback.automatic);

    session.send(const ControlTvMediaEvent(TvMediaAction.pause));
    session.send(const StartRoundEvent('q2'));
    await tester.runAsync(session.flush);
    expect(session.guestGame.tvMediaPaused, isFalse);
  }, variant: windows);

  testWidgets('the TV starts what is newest and keeps the rest still', (
    tester,
  ) async {
    await start(tester);
    await send(tester, const StartRoundEvent('q1'));
    await showTv(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.automatic);
    await send(tester, const ShowHintEvent(questionId: 'q1', shownHints: 0));
    await showTv(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(playbackOf(tester, 'dQw4w9WgXcB'), MediaPlayback.automatic);
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.stopped);
    await send(tester, const RevealRoundEvent());
    await tester.runAsync(() => session.advance(const Duration(seconds: 1)));
    await showTv(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(playbackOf(tester, 'dQw4w9WgXcA'), MediaPlayback.automatic);
    // The solution replaces the media of the question.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is QuestionMediaView &&
            w.media.any(
              (m) => m is VideoAttachment && m.youtubeId == 'dQw4w9WgXcQ',
            ),
      ),
      findsNothing,
    );
  }, variant: windows);

  testWidgets('the host device never starts, controls also serve slides', (
    tester,
  ) async {
    await start(tester);
    Future<Map<DashboardSection, Widget>> sections() async {
      late Map<DashboardSection, Widget> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = buildGameSections(
                context,
                engine: session.engine,
                engineState: session.engine.state,
                quizName: 'Quiz',
              );
              return Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      ?result[DashboardSection.media],
                      ?result[DashboardSection.liveRound],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      return result;
    }

    expect((await sections())[DashboardSection.media], isNull);
    await send(tester, const ShowSlideEvent('slide'));
    expect((await sections())[DashboardSection.media], isNotNull);
    await send(tester, const StartRoundEvent('q1'));
    await send(tester, const ControlTvMediaEvent(TvMediaAction.restart));
    await sections();
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.onDemand);
    expect(
      find.text('TV spielt, andere Geräte nur auf Wunsch.'),
      findsOneWidget,
    );
    await send(tester, const ControlTvMediaEvent(TvMediaAction.pause));
    await sections();
    expect(playbackOf(tester, 'dQw4w9WgXcQ'), MediaPlayback.paused);
    expect(find.text('Überall pausiert'), findsOneWidget);

    // A TV that may not start sound is reported to the host.
    expect(find.byKey(const ValueKey('tv-media-blocked')), findsNothing);
    session.engine.mediaScreens.report('tv', blocked: true);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(find.byKey(const ValueKey('tv-media-blocked')), findsOneWidget);
    session.engine.mediaScreens.report('tv', blocked: false);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(find.byKey(const ValueKey('tv-media-blocked')), findsNothing);
  }, variant: windows);

  test('the report of a TV survives the wire', () {
    const message = MediaBlockedReport(true);
    expect(ClientMessage.decode(message.encode()), message);
  });

  testWidgets('media inside a still picture never play', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StillMedia(
            child: QuestionMediaView(
              media: [_video('dQw4w9WgXcQ')],
              playback: MediaPlayback.automatic,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final ready = tester
        .widgetList<QuestionMediaView>(find.bySubtype<QuestionMediaView>())
        .last;
    expect(ready.playback, MediaPlayback.stopped);
  }, variant: windows);
}
