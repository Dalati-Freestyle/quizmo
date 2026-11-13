import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool active}) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: QuizmoApp.buildTheme(Brightness.dark),
        home: Scaffold(
          body: TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: const GameState(),
              snapshotReceivedAt: DateTime.now(),
              deviceCheckActive: active,
            ),
            joinUri: Uri.parse('http://192.168.0.2:8080'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the TV shows the device test of the tech check', (tester) async {
    await pump(tester, active: true);
    expect(find.byKey(const ValueKey('tv-device-check')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await pump(tester, active: false);
    expect(find.byKey(const ValueKey('tv-device-check')), findsNothing);
  });
}
