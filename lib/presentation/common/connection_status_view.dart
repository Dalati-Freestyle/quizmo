import 'package:flutter/material.dart';

import '../../core/net/quiz_client.dart';
import '../l10n/app_localizations.dart';

class ConnectionStatusView extends StatelessWidget {
  const ConnectionStatusView({required this.status, super.key});

  final QuizClientStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (status) {
      QuizClientStatus.connecting => (
        Icons.wifi_find,
        'Connecting to the host...',
      ),
      QuizClientStatus.connected => (Icons.wifi, 'Connected to the host'),
      QuizClientStatus.reconnecting => (
        Icons.sync,
        'Connection interrupted. Reconnecting to the room...',
      ),
      QuizClientStatus.closed => (Icons.link_off, 'Connection ended'),
      QuizClientStatus.disconnected ||
      QuizClientStatus.failed => (Icons.wifi_off, 'Not connected'),
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr(message))),
          ],
        ),
      ),
    );
  }
}
