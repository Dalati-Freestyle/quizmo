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
    super.key,
  });

  final InfoSlide slide;
  final bool large;
  final MediaPlayback playback;
  final int playbackRevision;
  final int commandRevision;
  final Uri? baseUri;

  @override
  Widget build(BuildContext context) => large ? _tv(context) : _page(context);

  bool get _hasTitle => slide.title.trim().isNotEmpty;
  bool get _hasText => slide.text.trim().isNotEmpty;

  QuestionMediaView _media({required bool fill}) => QuestionMediaView(
    key: ValueKey('slide-media-${slide.id}'),
    media: slide.media,
    baseUri: baseUri,
    playback: playback,
    playbackRevision: playbackRevision,
    commandRevision: commandRevision,
    fill: fill,
  );

  Widget _page(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasTitle)
          Text(
            slide.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        if (_hasText) ...[
          const SizedBox(height: 8),
          Text(slide.text, style: theme.textTheme.bodyLarge),
        ],
        if (slide.media.isNotEmpty) ...[
          const SizedBox(height: 12),
          _media(fill: false),
        ],
      ],
    );
  }

  /// Media fill the whole stage; title and text leave them what they can.
  Widget _tv(BuildContext context) {
    final theme = Theme.of(context);
    final hasMedia = slide.media.isNotEmpty;
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasTitle)
          Text(
            slide.title,
            textAlign: TextAlign.center,
            maxLines: hasMedia ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: hasMedia ? 64 : 96,
              fontWeight: FontWeight.w900,
            ),
          ),
        if (_hasText) ...[
          SizedBox(height: hasMedia ? 12 : 24),
          Text(
            slide.text,
            textAlign: TextAlign.center,
            maxLines: hasMedia ? 4 : 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: hasMedia ? 34 : 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    if (!hasMedia) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: 1600, child: words),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasTitle || _hasText)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.45,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(width: constraints.maxWidth, child: words),
                ),
              ),
            ),
          Expanded(child: _media(fill: true)),
        ],
      ),
    );
  }
}
