/// Layout of the spectator page around the fixed TV canvas.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/common/media_volume.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

import '../media_volume_test.dart';

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
    expect(tester.getSize(find.byType(FittedBox).first), const Size(1280, 720));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the TV plays every medium with its stored volume', (
    tester,
  ) async {
    final store = MemoryVolumeStore((level: 0.25, muted: false));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TvPage(
          hostUri: Uri.parse('http://127.0.0.1:1'),
          clientFactory: _ConnectedClient.new,
          volumeStore: store,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final scope = tester.widget<MediaVolumeScope>(
      find.byType(MediaVolumeScope),
    );
    expect(scope.notifier!.effective, 0.25);
    scope.notifier!.toggleMute();
    await tester.pump();
    expect(store.stored, (level: 0.25, muted: true));

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
