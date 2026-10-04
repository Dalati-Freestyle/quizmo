/// Player renderer for `BuzzerQuestion`.
library;

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/sync/clock.dart';
import '../../common/buzzer_button.dart';

/// Shows the prompt and the latency compensated buzzer.
class BuzzerQuestionView extends StatelessWidget {
  /// Creates the view.
  const BuzzerQuestionView({
    required this.question,
    required this.round,
    required this.playerId,
    required this.hasBuzzed,
    required this.onBuzz,
    required this.clockOffsetMicros,
    required this.roundTripMicros,
    super.key,
  });

  /// The question on stage, redacted until the reveal.
  final BuzzerQuestion question;

  /// Authoritative round state pushed by the host.
  final RoundState round;

  /// Identifier of this client.
  final String? playerId;

  /// Whether this client already pressed during the current window.
  final bool hasBuzzed;

  /// Invoked synchronously on pointer down.
  final VoidCallback onBuzz;

  /// Measured `client - host` offset, rendered for transparency.
  final int clockOffsetMicros;

  /// Round trip time backing the offset.
  final int roundTripMicros;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = playerId;
    final isLockedOut = id != null && round.lockedOutPlayerIds.contains(id);
    final hasFloor = id != null && round.activePlayerId == id;
    final rank = id == null ? -1 : round.rankOf(id);

    final mode = switch (round.status) {
      _ when hasFloor => BuzzerMode.won,
      RoundStatus.acceptingAnswers when isLockedOut => BuzzerMode.locked,
      RoundStatus.acceptingAnswers when hasBuzzed => BuzzerMode.submitted,
      RoundStatus.acceptingAnswers => BuzzerMode.ready,
      _ => BuzzerMode.locked,
    };

    final hint = switch (mode) {
      BuzzerMode.won => 'You have the floor — answer out loud!',
      BuzzerMode.submitted =>
        rank >= 0 ? 'Queued at position ${rank + 1}' : 'Sent…',
      BuzzerMode.locked when isLockedOut => 'Locked out this round',
      BuzzerMode.locked => 'Buzzer closed',
      BuzzerMode.ready => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          question.prompt,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: AspectRatio(
              aspectRatio: 1,
              child: BuzzerButton(mode: mode, hint: hint, onPressed: onBuzz),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _LatencyBadge(
          clockOffsetMicros: clockOffsetMicros,
          roundTripMicros: roundTripMicros,
        ),
        if (round.status == RoundStatus.revealed &&
            question.expectedAnswer != null) ...[
          const SizedBox(height: 16),
          Text(
            'Answer: ${question.expectedAnswer}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.tertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({
    required this.clockOffsetMicros,
    required this.roundTripMicros,
  });

  final int clockOffsetMicros;
  final int roundTripMicros;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          roundTripMicros == 0
              ? 'Clock not synced yet'
              : 'Latency ${formatMicrosAsMillis(roundTripMicros ~/ 2)} · '
                    'clock offset ${formatSignedMicrosAsMillis(clockOffsetMicros)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
