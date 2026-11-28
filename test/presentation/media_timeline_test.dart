import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/media_timeline.dart';

/// Records the host's jumps it follows.
class _Follower extends StatefulWidget {
  const _Follower(this.mediaKey, this.jumps);
  final String mediaKey;
  final List<Duration> jumps;
  @override
  State<_Follower> createState() => _FollowerState();
}

class _FollowerState extends State<_Follower> with FollowsHostSeek {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    followHostSeek(widget.mediaKey, widget.jumps.add);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

TvMediaSeek seek(String key, int seconds, int revision) => TvMediaSeek(
  mediaKey: key,
  positionMicros: seconds * 1000000,
  revision: revision,
);

void main() {
  test('times read like a player', () {
    expect(formatMediaTime(const Duration(seconds: 42)), '0:42');
    expect(formatMediaTime(const Duration(minutes: 3, seconds: 15)), '3:15');
    expect(formatMediaTime(const Duration(hours: 1, seconds: 3)), '1:00:03');
    expect(
      mediaSeekKey(const VideoAttachment(youtubeId: 'abc')),
      'youtube:abc',
    );
  });

  testWidgets('tapping and dragging the timeline jumps', (tester) async {
    final jumps = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: MediaTimeline(
              position: const Duration(seconds: 42),
              duration: const Duration(minutes: 3, seconds: 15),
              onSeek: jumps.add,
            ),
          ),
        ),
      ),
    );
    expect(find.text('0:42 / 3:15'), findsOneWidget);
    final slider = find.byKey(const ValueKey('media-timeline-slider'));
    await tester.tap(slider);
    await tester.pump();
    expect(jumps, hasLength(1));
    expect(
      jumps.single.inSeconds,
      closeTo(195 / 2, 15),
      reason: 'the middle of the slider',
    );
    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pump();
    expect(jumps.last, Duration.zero);
  });

  testWidgets('a timeline without a jump target stays still', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaTimeline(
            position: Duration(seconds: 5),
            duration: Duration(seconds: 10),
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
  });

  testWidgets('the TV follows new jumps of the host to its medium', (
    tester,
  ) async {
    final jumps = <Duration>[];
    Future<void> show(TvMediaSeek? command) => tester.pumpWidget(
      MediaSeekCommand(seek: command, child: _Follower('a', jumps)),
    );
    // A jump made before the medium appeared does not count.
    await show(seek('a', 10, 1));
    expect(jumps, isEmpty);
    await show(seek('a', 20, 2));
    expect(jumps, [const Duration(seconds: 20)]);
    await show(seek('b', 30, 3));
    expect(jumps, hasLength(1));
    await show(seek('a', 40, 4));
    expect(jumps.last, const Duration(seconds: 40));
  });

  test('the host jump reaches the guests', () async {
    final engine = QuizEngineBloc(
      questionBank: const [TrueFalseQuestion(id: 'q', prompt: '?')],
    );
    addTearDown(engine.close);
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    await send(
      const SeekTvMediaEvent(mediaKey: 'a', position: Duration(seconds: 3)),
    );
    expect(engine.state.game.tvMediaSeek, isNull);
    await send(const StartRoundEvent('q'));
    await send(
      const SeekTvMediaEvent(mediaKey: 'a', position: Duration(seconds: 3)),
    );
    await send(
      const SeekTvMediaEvent(mediaKey: 'a', position: Duration(seconds: 3)),
    );
    final jump = engine.state.game.tvMediaSeek!;
    expect(
      (jump.mediaKey, jump.position, jump.revision),
      ('a', const Duration(seconds: 3), 2),
    );
    expect(engine.state.game.redactedForPlayers().tvMediaSeek, jump);
    expect(GameState.fromJson(engine.state.game.toJson()).tvMediaSeek, jump);
  });
}
