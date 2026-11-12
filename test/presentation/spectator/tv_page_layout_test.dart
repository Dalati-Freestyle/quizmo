/// Layout of the spectator page around the fixed TV canvas.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

void main() {
  testWidgets('the canvas keeps the full screen once the TV is connected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: QuizmoApp.buildTheme(Brightness.dark),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TvPage(
          hostUri: Uri.parse('http://127.0.0.1:1'),
          clientFactory: _ConnectedClient.new,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Regression: the join code field collapses once connected. The page
    // Stack used to shrink to 0×0 with it, which blanked the whole screen.
    expect(find.byType(TextField), findsNothing);
    expect(tester.getSize(find.byType(TvScreen)), const Size(1920, 1080));
    expect(tester.getSize(find.byType(FittedBox)), const Size(1280, 720));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// A host that accepts the spectator immediately and sends one lobby snapshot.
class _ConnectedClient extends QuizClient {
  _ConnectedClient(Uri baseUri) : super(baseUri: baseUri);

  final _fakeStatuses = StreamController<QuizClientStatus>.broadcast();
  final _fakeGames = StreamController<GameState>.broadcast();

  @override
  Stream<QuizClientStatus> get statuses => _fakeStatuses.stream;

  @override
  Stream<GameState> get games => _fakeGames.stream;

  @override
  Future<void> watch({
    String? joinCode,
    Duration joinTimeout = const Duration(seconds: 10),
  }) async {
    _fakeStatuses.add(QuizClientStatus.connected);
    _fakeGames.add(const GameState());
  }

  @override
  Future<void> dispose() async {
    await _fakeStatuses.close();
    await _fakeGames.close();
    await super.dispose();
  }
}
