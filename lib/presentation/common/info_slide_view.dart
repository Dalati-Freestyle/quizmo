/// Renders an interstitial slide on the TV and on the player devices.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import 'question_media_view.dart';
import 'media_playback.dart';

/// Title, text and media of [slide].
///
/// [large] is the TV layout (fixed 1920×1080 canvas, text ≥ 22 px).
class InfoSlideView extends StatelessWidget {
  /// Creates the view of [slide].
  const InfoSlideView({
    required this.slide,
    this.large = false,
    this.playback = MediaPlayback.onDemand,
    this.playbackRevision = 0,
    this.commandRevision = 0,
    this.baseUri,
    this.maxVideoHeight = 300,
    super.key,
  });

  final InfoSlide slide;
  final bool large;
  final MediaPlayback playback;
  final int playbackRevision;
  final int commandRevision;
  final Uri? baseUri;
  final double maxVideoHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: large
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      children: [
        if (slide.title.trim().isNotEmpty)
          Text(
            slide.title,
            textAlign: large ? TextAlign.center : TextAlign.start,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: large
                ? const TextStyle(fontSize: 96, fontWeight: FontWeight.w900)
                : theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
          ),
        if (slide.text.trim().isNotEmpty) ...[
          SizedBox(height: large ? 24 : 8),
          Text(
            slide.text,
            textAlign: large ? TextAlign.center : TextAlign.start,
            maxLines: large ? 6 : null,
            overflow: large ? TextOverflow.ellipsis : null,
            style: large
                ? TextStyle(
                    fontSize: 40,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyLarge,
          ),
        ],
        if (slide.media.isNotEmpty) ...[
          SizedBox(height: large ? 32 : 12),
          QuestionMediaView(
            key: ValueKey('slide-media-${slide.id}'),
            media: slide.media,
            baseUri: baseUri,
            playback: playback,
            playbackRevision: playbackRevision,
            commandRevision: commandRevision,
            maxVideoHeight: maxVideoHeight,
          ),
        ],
      ],
    );
  }
}
