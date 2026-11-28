/// Timeline of an audio or video medium and the jumps of the host.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// `0:42`, or `1:02:03` from one hour on.
String formatMediaTime(Duration time) {
  final seconds = time.inSeconds.abs();
  final text = seconds >= 3600
      ? '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}'
            ':${(seconds % 60).toString().padLeft(2, '0')}'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  return time.isNegative ? '-$text' : text;
}

/// Key of a medium in [TvMediaSeek]: the asset ID of an upload, or
/// `youtube:<id>`.
String? mediaSeekKey(MediaAttachment attachment) => switch (attachment) {
  VideoAttachment(:final youtubeId?) => 'youtube:$youtubeId',
  _ => attachment.asset?.id,
};

/// Position and length of a medium with a slider to jump. Shows only times,
/// never a title or file name.
class MediaTimeline extends StatefulWidget {
  const MediaTimeline({
    required this.position,
    required this.duration,
    this.onSeek,
    super.key,
  });

  final Duration position;

  /// Length of the medium; `null` while unknown.
  final Duration? duration;

  /// Jumps to a position; `null` disables the slider (paused by the host,
  /// still pictures).
  final ValueChanged<Duration>? onSeek;

  @override
  State<MediaTimeline> createState() => _MediaTimelineState();
}

class _MediaTimelineState extends State<MediaTimeline> {
  /// Position under the finger while it drags.
  double? _dragged;

  @override
  Widget build(BuildContext context) {
    final total = widget.duration?.inMilliseconds ?? 0;
    final position = widget.position.inMilliseconds.clamp(0, total);
    final value = (_dragged ?? position.toDouble()).clamp(0.0, total * 1.0);
    final shown = Duration(milliseconds: value.round());
    return Row(
      key: const ValueKey('media-timeline'),
      children: [
        Expanded(
          child: Slider(
            key: const ValueKey('media-timeline-slider'),
            value: total == 0 ? 0 : value,
            max: total == 0 ? 1 : total.toDouble(),
            semanticFormatterCallback: (value) =>
                formatMediaTime(Duration(milliseconds: value.round())),
            onChanged: widget.onSeek == null || total == 0
                ? null
                : (value) => setState(() => _dragged = value),
            onChangeEnd: widget.onSeek == null || total == 0
                ? null
                : (value) {
                    setState(() => _dragged = null);
                    widget.onSeek!(Duration(milliseconds: value.round()));
                  },
          ),
        ),
        Tooltip(
          message: context.tr('Position / Länge'),
          child: Text(
            widget.duration == null
                ? formatMediaTime(shown)
                : '${formatMediaTime(shown)} / ${formatMediaTime(widget.duration!)}',
            style: const TextStyle(
              fontSize: 18,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// Learns the jumps of the host (dashboard and preview) and passes them on to
/// the TV. Players have none: their jumps only count on their device.
class MediaSeekReporter extends InheritedWidget {
  const MediaSeekReporter({
    required this.onSeek,
    required super.child,
    super.key,
  });

  final void Function(String mediaKey, Duration position) onSeek;

  static MediaSeekReporter? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MediaSeekReporter>();

  @override
  bool updateShouldNotify(MediaSeekReporter oldWidget) => false;
}

/// The host's last jump for the media below (the TV only).
class MediaSeekCommand extends InheritedWidget {
  const MediaSeekCommand({required this.seek, required super.child, super.key});

  final TvMediaSeek? seek;

  static TvMediaSeek? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaSeekCommand>()?.seek;

  @override
  bool updateShouldNotify(MediaSeekCommand oldWidget) => oldWidget.seek != seek;
}

/// Follows the [MediaSeekCommand] for one medium: [onSeek] runs once for
/// every new jump of the host to this medium, not for one made before it
/// appeared.
mixin FollowsHostSeek<T extends StatefulWidget> on State<T> {
  int? _seenSeek;

  /// Call from `didChangeDependencies`.
  void followHostSeek(String? mediaKey, void Function(Duration) onSeek) {
    final seek = MediaSeekCommand.of(context);
    final first = _seenSeek == null;
    final revision = seek?.revision ?? 0;
    if (!first && revision != _seenSeek && seek!.mediaKey == mediaKey) {
      onSeek(seek.position);
    }
    _seenSeek = revision;
  }
}
