import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// Which media of [question] are on screen in a round with [status].
///
/// After the reveal only the solution media are shown, when there are some;
/// [questionSide] switches back to the media of the question. Before the
/// reveal, or without solution media, the question media stay as they are.
({bool question, bool solution}) visibleQuestionMedia(
  Question question,
  RoundStatus status, {
  bool questionSide = false,
}) {
  final revealed = status == RoundStatus.revealed;
  final solution = revealed && question.solutionMedia.isNotEmpty;
  return (
    question: question.media.isNotEmpty && (!solution || questionSide),
    solution: solution && !(questionSide && question.media.isNotEmpty),
  );
}

/// Whether a [RevealMediaToggle] is offered: revealed, with media on both
/// sides.
bool offersRevealMediaToggle(Question question, RoundStatus status) =>
    status == RoundStatus.revealed &&
    question.media.isNotEmpty &&
    question.solutionMedia.isNotEmpty;

/// Switches between the media of the question and of the solution after the
/// reveal. The hidden side is removed, so two media never play together.
class RevealMediaToggle extends StatelessWidget {
  const RevealMediaToggle({
    required this.questionSide,
    required this.onChanged,
    super.key,
  });

  final bool questionSide;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SegmentedButton<bool>(
      key: const ValueKey('reveal-media-toggle'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: true,
          icon: const Icon(Icons.help_outline),
          label: Text(context.tr('Frage')),
        ),
        ButtonSegment(
          value: false,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(context.tr('Lösung')),
        ),
      ],
      selected: {questionSide},
      onSelectionChanged: (selection) => onChanged(selection.single),
    ),
  );
}

/// A [RevealMediaToggle] with its own choice, for one device (players).
/// It starts at the solution with every question.
class LocalRevealMedia extends StatefulWidget {
  const LocalRevealMedia({
    required this.question,
    required this.status,
    required this.builder,
    super.key,
  });

  final Question question;
  final RoundStatus status;

  /// Builds the media; [toggle] is `null` when there is nothing to switch.
  final Widget Function(
    BuildContext context,
    ({bool question, bool solution}) visible,
    Widget? toggle,
  )
  builder;

  @override
  State<LocalRevealMedia> createState() => _LocalRevealMediaState();
}

class _LocalRevealMediaState extends State<LocalRevealMedia> {
  bool _questionSide = false;

  @override
  void didUpdateWidget(LocalRevealMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id ||
        widget.status != RoundStatus.revealed) {
      _questionSide = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    visibleQuestionMedia(
      widget.question,
      widget.status,
      questionSide: _questionSide,
    ),
    offersRevealMediaToggle(widget.question, widget.status)
        ? RevealMediaToggle(
            questionSide: _questionSide,
            onChanged: (value) => setState(() => _questionSide = value),
          )
        : null,
  );
}
