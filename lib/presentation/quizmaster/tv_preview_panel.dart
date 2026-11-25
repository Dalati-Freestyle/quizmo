/// The admin section "TV preview": what the TV shows right now, small and live.
library;

import 'package:flutter/material.dart';

import '../../core/data/game_protocol_builder.dart';
import '../../core/models/models.dart';
import '../common/media_playback.dart';
import '../l10n/app_localizations.dart';
import '../spectator/tv_canvas.dart';

/// Only a picture: no input, no focus, no sound and nothing read out twice.
class TvPreviewPanel extends StatelessWidget {
  const TvPreviewPanel({
    required this.game,
    required this.quizName,
    this.joinUri,
    this.guestWifi,
    super.key,
  });

  /// The host's full state; the panel shows its guest snapshot only.
  final GameState game;
  final String quizName;
  final Uri? joinUri;
  final GuestWifi? guestWifi;

  Widget _canvas(GameState snapshot) => StillMedia(
    child: IgnorePointer(
      child: ExcludeFocus(
        child: ExcludeSemantics(
          child: TvCanvas(
            game: snapshot,
            joinUri: joinUri,
            serverName: quizName,
            guestWifi: guestWifi,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The bytes of uploaded media are at hand: no request to the own server.
    final snapshot = guestSnapshotOf(
      game,
      title: quizName,
      includeMediaData: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: context.tr('Verkleinerte TV-Ansicht'),
          child: AspectRatio(
            key: const ValueKey('tv-preview'),
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _canvas(snapshot),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('tv-preview-enlarge'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => Dialog(
                insetPadding: const EdgeInsets.all(24),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _canvas(snapshot)),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IconButton.filledTonal(
                          tooltip: context.tr('Schließen'),
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.fullscreen),
            label: Text(context.tr('Größer ansehen')),
          ),
        ),
      ],
    );
  }
}
