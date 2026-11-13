/// Small countdown of the running answer clock for the player view.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// Remaining answer time of [game]'s round at host instant [hostNowMicros].
///
/// Returns `null` when no answer clock runs: no question, answers closed,
/// poker betting, or no positive time limit. A restarted clock (Jeopardy
/// steal round, end of poker betting) counts from its restart. While the host
/// is paused for recovery the clock stands still at the snapshot time.
Duration? remainingAnswerTime(GameState game, int hostNowMicros) {
  final round = game.round;
  final question = round.question;
  if (question == null ||
      round.status != RoundStatus.acceptingAnswers ||
      round.timerStartedAtHostMicros == null ||
      (game.poker?.betting ?? false) ||
      question.timeLimit <= Duration.zero) {
    return null;
  }
  final now = game.recoveryPaused ? game.hostTimeMicros : hostNowMicros;
  final remaining = question.timeLimit - round.timerElapsedAt(now);
  return remaining.isNegative ? Duration.zero : remaining;
}

/// Shows the remaining answer time as a small chip.
///
/// [hostNowMicros] must return the host clock as estimated by the clock
/// synchronisation (local time minus the measured offset), so the value
/// matches the TV instead of the possibly skewed device clock.
class RoundCountdown extends StatefulWidget {
  /// Creates the countdown.
  const RoundCountdown({
    required this.game,
    required this.hostNowMicros,
    super.key,
  });

  /// Latest snapshot.
  final GameState game;

  /// Current host time estimate.
  final int Function() hostNowMicros;

  @override
  State<RoundCountdown> createState() => _RoundCountdownState();
}

class _RoundCountdownState extends State<RoundCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = remainingAnswerTime(widget.game, widget.hostNowMicros());
    if (remaining == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final urgent = remaining <= const Duration(seconds: 5);
    final expired = remaining == Duration.zero;
    final label = expired
        ? context.tr("Time's up")
        : '${(remaining.inMilliseconds / 1000).ceil()} s';
    return Semantics(
      liveRegion: urgent,
      label: context.tr('Verbleibende Zeit: {0}', [label]),
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('round-countdown'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: urgent ? scheme.errorContainer : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 16,
                color: urgent
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: urgent
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
