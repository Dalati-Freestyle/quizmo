/// Player renderer for `MultipleChoiceQuestion`.
library;

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';

/// Shows the prompt and the selectable options.
///
/// After the round is revealed the widget switches into a result mode that
/// marks the correct option and the player's own pick.
class MultipleChoiceQuestionView extends StatelessWidget {
  /// Creates the view.
  const MultipleChoiceQuestionView({
    required this.question,
    required this.status,
    required this.selectedOptionId,
    required this.onSelect,
    super.key,
  });

  /// The question on stage, redacted until the reveal.
  final MultipleChoiceQuestion question;

  /// Lifecycle of the round.
  final RoundStatus status;

  /// Option this client already submitted, if any.
  final String? selectedOptionId;

  /// Invoked with the chosen option id.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocked = !status.acceptsInput || selectedOptionId != null;

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
        const SizedBox(height: 24),
        for (final option in question.options) ...[
          _OptionTile(
            option: option,
            isSelected: option.id == selectedOptionId,
            isCorrect: question.correctOptionId == null
                ? null
                : question.correctOptionId == option.id,
            enabled: !isLocked,
            onTap: () => onSelect(option.id),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Text(
          switch (status) {
            RoundStatus.revealed =>
              question.correctOptionId == selectedOptionId
                  ? 'Correct!'
                  : 'Not this time.',
            _ when selectedOptionId != null =>
              'Answer locked in. Waiting for the quizmaster…',
            _ => 'Pick one answer — faster answers score more.',
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.isSelected,
    required this.isCorrect,
    required this.enabled,
    required this.onTap,
  });

  final AnswerOption option;
  final bool isSelected;

  /// `null` while the solution is still redacted.
  final bool? isCorrect;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, border) = switch ((isCorrect, isSelected)) {
      (true, _) => (scheme.tertiaryContainer, scheme.tertiary),
      (false, true) => (scheme.errorContainer, scheme.error),
      (_, true) => (scheme.primaryContainer, scheme.primary),
      _ => (
        scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        scheme.outlineVariant,
      ),
    };

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: isSelected ? 2 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isCorrect == true || isSelected) const SizedBox(width: 12),
              if (isCorrect == true)
                const Icon(Icons.check_circle, size: 20)
              else if (isSelected)
                const Icon(Icons.radio_button_checked, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
