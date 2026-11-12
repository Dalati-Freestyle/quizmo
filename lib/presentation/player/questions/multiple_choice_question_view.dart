/// Player renderer for `MultipleChoiceQuestion`.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/models/models.dart';

/// Shows the prompt and the selectable options.
///
/// After the round is revealed the widget switches into a result mode that
/// marks the correct option and the player's own pick.
class MultipleChoiceQuestionView extends StatefulWidget {
  /// Creates the view.
  const MultipleChoiceQuestionView({
    required this.question,
    required this.status,
    required this.selectedOptionId,
    required this.onSelect,
    this.selectedOptionIds = const [],
    this.onSubmitMultiple,
    this.enabled = true,
    this.submissionAccepted = false,
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

  final List<String> selectedOptionIds;
  final ValueChanged<List<String>>? onSubmitMultiple;
  final bool enabled;
  final bool submissionAccepted;
  @override
  State<MultipleChoiceQuestionView> createState() =>
      _MultipleChoiceQuestionViewState();
}

class _MultipleChoiceQuestionViewState
    extends State<MultipleChoiceQuestionView> {
  final Set<String> draft = {};
  bool submitted = false;
  @override
  void didUpdateWidget(covariant MultipleChoiceQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedOptionId != null && widget.selectedOptionId == null) {
      submitted = false;
    }
  }

  MultipleChoiceQuestion get question => widget.question;
  RoundStatus get status => widget.status;
  String? get selectedOptionId => widget.selectedOptionId;
  Set<String> get selected => widget.selectedOptionIds.isNotEmpty
      ? widget.selectedOptionIds.toSet()
      : {
          if (selectedOptionId != null && selectedOptionId != 'submitted')
            selectedOptionId!,
          ...draft,
        };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocked =
        !widget.enabled ||
        !status.acceptsInput ||
        selectedOptionId != null ||
        submitted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in question.options) ...[
          _OptionTile(
            option: option,
            isSelected: selected.contains(option.id),
            isCorrect: !question.hasSolution
                ? null
                : question.isCorrect(option.id),
            enabled: !isLocked,
            onTap: () {
              if (isLocked || submitted || widget.selectedOptionId != null) {
                return;
              }
              setState(() {
                if (question.allowMultipleAnswers) {
                  if (!draft.add(option.id)) draft.remove(option.id);
                } else {
                  draft.add(option.id);
                  submitted = true;
                }
              });
              if (!question.allowMultipleAnswers) widget.onSelect(option.id);
            },
          ),
          const SizedBox(height: 10),
        ],
        if (question.allowMultipleAnswers)
          FilledButton(
            onPressed:
                !isLocked && draft.isNotEmpty && widget.onSubmitMultiple != null
                ? () {
                    if (submitted || widget.selectedOptionId != null) return;
                    setState(() => submitted = true);
                    widget.onSubmitMultiple!(draft.toList());
                  }
                : null,
            child: Text(context.tr("Antworten einloggen")),
          ),
        const SizedBox(height: 16),
        Text(question.prompt, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          switch (status) {
            RoundStatus.revealed =>
              isPermutation(selected.toList(), question.solutionOptionIds)
                  ? 'Correct!'
                  : context.tr("Not this time."),
            _ when selectedOptionId != null || submitted => context.tr(
              widget.submissionAccepted
                  ? 'The host accepted your submission.'
                  : 'Sending. Waiting for host confirmation...',
            ),
            _ =>
              question.allowMultipleAnswers
                  ? context.tr(
                      "Wähle alle richtigen Antworten und logge sie ein.",
                    )
                  : context.tr(
                      "Ein Druck loggt deine Antwort verbindlich ein.",
                    ),
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
