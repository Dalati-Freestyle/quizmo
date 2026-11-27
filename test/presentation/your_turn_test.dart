import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/your_turn.dart';

import '../helpers/mock_lan_discovery.dart';

const question = TrueFalseQuestion(id: 'q', prompt: 'Wahr?');
const buzzer = BuzzerQuestion(id: 'b', prompt: 'Wer?');

PlayerSessionState playing({
  Question q = question,
  RoundStatus status = RoundStatus.acceptingAnswers,
  int startedAt = 1,
  String? submitted,
  bool hasBuzzed = false,
  PokerState? poker,
  bool connected = true,
}) => PlayerSessionState(
  status: connected
      ? QuizClientStatus.connected
      : QuizClientStatus.reconnecting,
  playerId: 'p',
  lastSubmittedOptionId: submitted,
  hasBuzzed: hasBuzzed,
  game: GameState(
    isStarted: true,
    players: const {'p': Player(id: 'p', name: 'Ada', teamId: 't')},
    teams: poker == null ? const {} : const {'t': Team(id: 't', name: 'T')},
    poker: poker,
    round: RoundState(
      question: q,
      status: status,
      startedAtHostMicros: startedAt,
    ),
  ),
);

void main() {
  setUp(YourTurnSignal.reset);

  test('knows what the host waits for', () {
    expect(pendingTurn(playing()), PlayerTurn.answer);
    expect(pendingTurn(playing(submitted: 'submitted')), isNull);
    expect(pendingTurn(playing(status: RoundStatus.revealed)), isNull);
    expect(pendingTurn(playing(connected: false)), isNull);
    expect(pendingTurn(playing(q: buzzer)), PlayerTurn.buzz);
    expect(pendingTurn(playing(q: buzzer, hasBuzzed: true)), isNull);
    expect(pendingTurn(const PlayerSessionState()), isNull);
    const betting = PokerState(
      startingChips: 100,
      chips: {'t': 100},
      betting: true,
    );
    expect(pendingTurn(playing(poker: betting)), PlayerTurn.stake);
    expect(
      pendingTurn(playing(poker: betting.copyWith(wagers: const {'t': 10}))),
      isNull,
    );
    // Bankrupt teams have nothing to bet.
    expect(
      pendingTurn(playing(poker: betting.copyWith(chips: const {'t': 0}))),
      isNull,
    );
    // The category phase only offers optional jokers.
    expect(
      pendingTurn(playing(poker: betting.copyWith(questionHidden: true))),
      isNull,
    );
  });

  group('signal', () {
    late List<MethodCall> haptics;
    setUp(() {
      haptics = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Future<void> show(WidgetTester tester, PlayerSessionState state) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: YourTurnSignal(state: state, child: const SizedBox()),
            ),
          ),
        );

    final notice = find.byKey(const ValueKey('your-turn'));

    testWidgets('shows once per action and goes away by itself', (
      tester,
    ) async {
      await show(tester, playing(status: RoundStatus.idle));
      expect(notice, findsNothing);
      await show(tester, playing());
      expect(notice, findsOneWidget);
      expect(find.text('Du bist dran!'), findsOneWidget);
      expect(haptics, hasLength(1));
      await tester.pump(YourTurnSignal.duration);
      await tester.pump();
      expect(notice, findsNothing);

      // A reconnect or a new page for the same question stays quiet.
      await show(tester, playing(connected: false));
      await show(tester, playing());
      await tester.pumpWidget(const SizedBox());
      await show(tester, playing());
      expect(notice, findsNothing);
      expect(haptics, hasLength(1));

      // The next question signals again.
      await show(tester, playing(startedAt: 2));
      expect(notice, findsOneWidget);
      expect(haptics, hasLength(2));
      await tester.pump(YourTurnSignal.duration);
    });

    testWidgets('an answer ends the notice at once', (tester) async {
      await show(tester, playing());
      expect(notice, findsOneWidget);
      await show(tester, playing(submitted: 'submitted'));
      await tester.pump();
      expect(notice, findsNothing);
      await tester.pump(YourTurnSignal.duration);
    });
  });

  testWidgets('the app bar is red while the host waits for the player', (
    tester,
  ) async {
    mockLanDiscoveryUnavailable();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    await tester.pumpAndSettle();
    final cubit = tester
        .element(find.byType(Scaffold).first)
        .read<PlayerSessionCubit>();
    Color? barColor() => tester
        .widget<AppBar>(find.byKey(const ValueKey('player-app-bar')))
        .backgroundColor;
    final error = Theme.of(tester.element(find.byType(AppBar)))
        .colorScheme
        .error;
    expect(barColor(), isNot(error));
    cubit.emit(playing());
    // The bloc delivers the state in a microtask.
    await tester.pump();
    await tester.pump();
    expect(barColor(), error);
    expect(find.text('Du bist dran!'), findsOneWidget);
    cubit.emit(playing(submitted: 'submitted'));
    await tester.pump();
    await tester.pump();
    expect(barColor(), isNot(error));
    await tester.pump(YourTurnSignal.duration);
  });
}
