/// The answer clock stays visible on a phone while the player scrolls.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';

const _start = 1700000000000000;

void main() {
  testWidgets('the countdown floats above a long question on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final question = MultipleChoiceQuestion(
      id: 'q',
      prompt: 'A long question that needs scrolling on a phone?',
      timeLimit: const Duration(seconds: 30),
      options: [
        for (var i = 0; i < 12; i++)
          AnswerOption(id: 'o$i', label: 'A rather long answer option $i'),
      ],
    );
    final game = GameState(
      hostTimeMicros: _start,
      players: const {'p': Player(id: 'p', name: 'Ada')},
      round: RoundState(
        question: question.redacted(),
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: _start,
      ),
    );
    final snapshots = StreamController<GameState>.broadcast();
    addTearDown(snapshots.close);
    final cubit = PlayerSessionCubit.local(
      playerId: 'p',
      initialGame: game,
      snapshots: snapshots.stream,
      send: (_) {},
      now: () => _start + const Duration(seconds: 5).inMicroseconds,
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: PlayerGameColumn(state: cubit.state),
          ),
        ),
      ),
    );
    await tester.pump();
    final countdown = find.byKey(const ValueKey('round-countdown'));
    expect(countdown, findsOneWidget);
    final before = tester.getRect(countdown);
    final prompt = find.textContaining('A long question');
    final promptBefore = tester.getRect(prompt).top;

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -2000),
    );
    await tester.pump();

    final after = tester.getRect(countdown);
    expect(
      tester.getRect(prompt).top,
      lessThan(promptBefore - 100),
      reason: 'the question scrolled',
    );
    expect(after, before, reason: 'the clock does not scroll away');
    expect(after.top, greaterThanOrEqualTo(0));
    expect(after.bottom, lessThanOrEqualTo(640));
    expect(find.text('25 s'), findsOneWidget);
    // Stop the ticking countdown before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
