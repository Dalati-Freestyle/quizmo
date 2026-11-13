import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';

import '../helpers/mock_lan_discovery.dart';

void main() {
  setUp(mockLanDiscoveryUnavailable);

  testWidgets('players confirm the device check with one tap', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    await tester.pumpAndSettle();
    final cubit = tester
        .element(find.byType(Scaffold))
        .read<PlayerSessionCubit>();
    cubit.emit(
      const PlayerSessionState(
        status: QuizClientStatus.connected,
        playerId: 'p',
        game: GameState(players: {'p': Player(id: 'p', name: 'Ada')}),
        deviceCheckId: 'check-1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCheckBanner), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('device-check-tap')));
    await tester.pumpAndSettle();
    expect(cubit.state.deviceCheckId, isNull);
    expect(find.byType(DeviceCheckBanner), findsNothing);
  });
}
