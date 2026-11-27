/// Progress of preloading the media of the quiz on this device.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/net/media_preloader.dart';
import '../l10n/app_localizations.dart';
import 'question_media_view.dart';

/// `85 MB` from bytes.
String formatMegabytes(int bytes) {
  final mb = bytes / (1000 * 1000);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

/// "Media 12/30 · 85 MB / 140 MB" with a bar; nothing without media to
/// preload. Reads the preloader of the surrounding [SessionMediaAccess].
class MediaPreloadView extends StatelessWidget {
  const MediaPreloadView({this.large = false, super.key});

  /// Type sizes for the TV.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final preloader = SessionMediaAccess.preloaderOf(context);
    if (preloader == null) return const SizedBox.shrink();
    return StreamBuilder<MediaPreloadStatus>(
      stream: preloader.changes,
      builder: (context, _) => _content(context, preloader),
    );
  }

  Widget _content(BuildContext context, MediaPreloader preloader) {
    final manifest = preloader.manifest;
    if (manifest.items.isEmpty && manifest.onlineCount == 0) {
      return const SizedBox.shrink();
    }
    final status = preloader.status;
    final theme = Theme.of(context);
    final style = large
        ? const TextStyle(fontSize: 24)
        : theme.textTheme.bodySmall;
    final line = switch (status.phase) {
      MediaPreloadPhase.disabled => context.tr(
        'Vorladen ist aus: Medien laden, wenn eine Frage sie braucht.',
      ),
      MediaPreloadPhase.done => context.tr('Alle Medien geladen ({0})', [
        formatMegabytes(status.totalBytes),
      ]),
      MediaPreloadPhase.loading || MediaPreloadPhase.failed => context.tr(
        'Medien {0}/{1} · {2} / {3}',
        [
          status.loadedFiles,
          status.totalFiles,
          formatMegabytes(status.loadedBytes),
          formatMegabytes(status.totalBytes),
        ],
      ),
    };
    return Padding(
      key: const ValueKey('media-preload'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (manifest.items.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  switch (status.phase) {
                    MediaPreloadPhase.done => Icons.check_circle,
                    MediaPreloadPhase.disabled => Icons.block,
                    MediaPreloadPhase.failed => Icons.warning_amber,
                    MediaPreloadPhase.loading => Icons.downloading,
                  },
                  size: large ? 32 : 18,
                  color: status.phase == MediaPreloadPhase.failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line, style: style)),
              ],
            ),
            if (status.phase == MediaPreloadPhase.loading ||
                status.phase == MediaPreloadPhase.failed) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: status.fraction),
            ],
            if (status.phase == MediaPreloadPhase.failed)
              Text(
                context.tr('Download unterbrochen, wird erneut versucht …'),
                style: style?.copyWith(color: theme.colorScheme.error),
              ),
          ],
          if (manifest.onlineCount > 0)
            Text(
              context.tr(
                '{0} Online-Medien (YouTube, Karten) laden erst im Quiz.',
                [manifest.onlineCount],
              ),
              style: style?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }
}
