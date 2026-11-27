/// The preload progress of every device, shown to the host in the lobby.
library;

import 'package:flutter/material.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../common/media_preload_view.dart';
import '../l10n/app_localizations.dart';

/// One line per player device and TV: loaded, loading (%), switched off or
/// failed. Nothing for a quiz without uploads.
class MediaPreloadStatusView extends StatelessWidget {
  const MediaPreloadStatusView({required this.engine, super.key});

  final QuizEngineBloc engine;

  @override
  Widget build(BuildContext context) {
    final manifest = engine.mediaPreload.manifest;
    if (manifest.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return StreamBuilder<void>(
      stream: engine.mediaPreloadStatuses.changes,
      builder: (context, _) {
        final devices = engine.mediaPreloadStatuses.all.values.toList();
        return Column(
          key: const ValueKey('media-preload-status'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              context.tr('Medien-Sync ({0} Dateien, {1})', [
                manifest.items.length,
                formatMegabytes(manifest.totalBytes),
              ]),
              style: theme.textTheme.titleSmall,
            ),
            if (devices.isEmpty)
              Text(
                context.tr('Noch kein Gerät meldet seinen Stand.'),
                style: theme.textTheme.bodySmall,
              ),
            for (final device in devices)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(device.tv ? Icons.tv : Icons.smartphone),
                title: Text(device.name),
                trailing: _phase(context, device.status),
              ),
          ],
        );
      },
    );
  }

  Widget _phase(BuildContext context, MediaPreloadStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (status.phase) {
      MediaPreloadPhase.done => (
        Icons.check_circle,
        Colors.green.shade700,
        context.tr('alle Medien geladen'),
      ),
      MediaPreloadPhase.loading => (
        Icons.hourglass_top,
        scheme.primary,
        context.tr('lädt {0} %', [(status.fraction * 100).floor()]),
      ),
      MediaPreloadPhase.disabled => (
        Icons.block,
        scheme.outline,
        context.tr('Vorladen deaktiviert'),
      ),
      MediaPreloadPhase.failed => (
        Icons.warning_amber,
        scheme.error,
        context.tr('Fehler, neuer Versuch ({0} %)', [
          (status.fraction * 100).floor(),
        ]),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
  }
}
