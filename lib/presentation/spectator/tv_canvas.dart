/// The TV picture at its fixed 1920×1080 size, scaled to the space it gets.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/net/quiz_client.dart';
import 'spectator_session_cubit.dart';
import 'tv_page.dart';

/// Shows [game] (a guest snapshot) exactly as a connected TV does.
class TvCanvas extends StatelessWidget {
  const TvCanvas({
    required this.game,
    this.joinUri,
    this.serverName,
    this.guestWifi,
    super.key,
  });

  final GameState game;
  final Uri? joinUri;
  final String? serverName;
  final GuestWifi? guestWifi;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: FittedBox(
          child: SizedBox(
            width: kTvCanvasWidth,
            height: kTvCanvasHeight,
            child: TvScreen(
              state: SpectatorSessionState(
                status: QuizClientStatus.connected,
                serverName: serverName,
                game: game,
                guestWifi: guestWifi,
                snapshotReceivedAt: DateTime.now(),
              ),
              joinUri: joinUri,
            ),
          ),
        ),
      ),
    ),
  );
}
