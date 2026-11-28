import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';

import '../helpers/mock_lan_discovery.dart';

MediaAsset svg(String color) => MediaAsset.upload(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" fill="$color"/></svg>',
    ),
  ),
  'svg',
);

final question = TrueFalseQuestion(
  id: 'q',
  prompt: 'Welches Land?',
  correctAnswer: true,
  media: [ImageAttachment(asset: svg('red'))],
  solutionMedia: [ImageAttachment(asset: svg('blue'))],
);

PlayerSessionState playing(RoundStatus status, {bool poker = false}) =>
    PlayerSessionState(
      status: QuizClientStatus.connected,
      playerId: 'p',
      game: GameState(
        isStarted: true,
        players: const {'p': Player(id: 'p', name: 'Ada', teamId: 't')},
        teams: const {'t': Team(id: 't', name: 'T')},
        // After the reveal the team is settled and may not answer any more.
        poker: poker
            ? const PokerState(
                startingChips: 10,
                chips: {'t': 14},
                wagers: {'t': 2},
                settledTeamIds: {'t'},
              )
            : null,
        round: RoundState(
          question: question,
          status: status,
          startedAtHostMicros: 1,
        ),
      ),
    );

void main() {
  for (final (status, poker) in [
    (RoundStatus.acceptingAnswers, false),
    (RoundStatus.revealed, false),
    (RoundStatus.revealed, true),
  ]) {
    testWidgets('a player enlarges and zooms a picture '
        '(${status.name}${poker ? ', poker' : ''})', (tester) async {
      mockLanDiscoveryUnavailable();
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
      await tester.pumpAndSettle();
      final cubit = tester
          .element(find.byType(Scaffold).first)
          .read<PlayerSessionCubit>();
      cubit.emit(playing(status, poker: poker));
      await tester.pump();
      await tester.pump();
      final enlarge = find.text('Vergrößern');
      expect(enlarge, findsOneWidget);
      await tester.ensureVisible(enlarge);
      await tester.tap(enlarge);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-zoom-dialog')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('media-zoom-dialog')),
          matching: find.byType(InteractiveViewer),
        ),
        findsOneWidget,
      );
    });
  }
}
