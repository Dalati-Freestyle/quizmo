import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'player_session_cubit.dart';

class SubmissionStatusView extends StatelessWidget {
  const SubmissionStatusView({required this.state, super.key});

  final PlayerSessionState state;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (state.submissionStatus) {
      SubmissionStatus.idle => (Icons.edit_outlined, ''),
      SubmissionStatus.sending => (
        Icons.schedule,
        'Sending. Waiting for host confirmation...',
      ),
      SubmissionStatus.uncertain => (
        Icons.help_outline,
        'Confirmation missing. Your answer may not have arrived.',
      ),
      SubmissionStatus.accepted when !state.isConnected => (
        Icons.history,
        'Last confirmed: the host accepted your submission.',
      ),
      SubmissionStatus.accepted => (
        Icons.check_circle_outline,
        'The host accepted your submission.',
      ),
      SubmissionStatus.rejected => (
        Icons.error_outline,
        'No submission accepted. Answer again if the round is still open.',
      ),
    };
    if (message.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr(message))),
          ],
        ),
      ),
    );
  }
}
