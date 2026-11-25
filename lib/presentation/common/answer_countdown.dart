/// Countdown after every team answered: until it ends, answers can be replaced.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Tells that every team answered and when the answers close.
class AnswerCountdownBanner extends StatefulWidget {
  const AnswerCountdownBanner({
    required this.deadlineMicros,
    required this.hostNowMicros,
    this.onSkip,
    this.fontSize,
    super.key,
  });

  /// `RoundState.answerDeadlineMicros`.
  final int deadlineMicros;

  /// Estimated host clock.
  final int Function() hostNowMicros;

  /// Closes the answers at once (host only).
  final VoidCallback? onSkip;
  final double? fontSize;

  @override
  State<AnswerCountdownBanner> createState() => _AnswerCountdownBannerState();
}

class _AnswerCountdownBannerState extends State<AnswerCountdownBanner> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = widget.deadlineMicros - widget.hostNowMicros();
    final seconds = left <= 0 ? 0 : (left / 1000000).ceil();
    return Container(
      key: const ValueKey('answer-countdown'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_bottom,
            size: widget.fontSize,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr(
                'Alle Teams haben geantwortet. Antworten schließen in {0} s.',
                [seconds],
              ),
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w600,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
          if (widget.onSkip case final onSkip?) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const ValueKey('skip-answer-countdown'),
              onPressed: onSkip,
              child: Text(context.tr('Jetzt schließen')),
            ),
          ],
        ],
      ),
    );
  }
}
