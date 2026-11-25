import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/models/models.dart';

/// How a question view behaves when the team shares one answer: it stays
/// editable after sending, and sending again replaces [valid].
final class TeamAnswerMode {
  const TeamAnswerMode({this.valid, this.own});

  /// The answer of the team that counts right now.
  final AnswerSubmission? valid;

  /// The last answer this player sent.
  final AnswerSubmission? own;
}

/// Submit button that stays coloured once the answer was sent, so the
/// player keeps seeing that the press counted.
class AnswerSubmitButton extends StatelessWidget {
  const AnswerSubmitButton({
    required this.label,
    required this.sent,
    required this.onPressed,
    this.replaces = false,
    super.key,
  });

  final String label;
  final bool sent;

  /// Whether sending replaces an answer the team already gave.
  final bool replaces;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!sent) {
      return FilledButton(
        onPressed: onPressed,
        child: Text(replaces ? context.tr('Antwort ersetzen') : label),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('answer-sent'),
      onPressed: null,
      style: FilledButton.styleFrom(
        disabledBackgroundColor: scheme.tertiary,
        disabledForegroundColor: scheme.onTertiary,
      ),
      icon: const Icon(Icons.check_circle),
      label: Text(context.tr('Gesendet')),
    );
  }
}

class ShortAnswerQuestionView extends StatefulWidget {
  const ShortAnswerQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    this.submitted = false,
    this.team,
    this.onChanged,
    super.key,
  });
  final ShortAnswerQuestion question;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  /// Whether this player's answer was sent in the running round.
  final bool submitted;

  /// Set when the team shares one answer.
  final TeamAnswerMode? team;

  /// Called with every change of the input, before it is sent.
  final ValueChanged<String?>? onChanged;
  @override
  State<ShortAnswerQuestionView> createState() =>
      _ShortAnswerQuestionViewState();
}

class _ShortAnswerQuestionViewState extends State<ShortAnswerQuestionView> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: controller,
        enabled: widget.enabled,
        maxLength: 2000,
        decoration: InputDecoration(labelText: context.tr("Deine Antwort")),
        onChanged: (text) {
          setState(() {});
          widget.onChanged?.call(text.trim().isEmpty ? null : text.trim());
        },
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 16),
      AnswerSubmitButton(
        sent: sent,
        replaces: widget.team?.valid != null,
        onPressed: widget.enabled && controller.text.trim().isNotEmpty
            ? submit
            : null,
        label: context.tr("Antwort senden"),
      ),
    ],
  );
  bool get sent => switch (widget.team) {
    null => widget.submitted,
    TeamAnswerMode(valid: ShortAnswer(:final text)) =>
      text.trim() == controller.text.trim(),
    _ => false,
  };
  void submit() {
    if (widget.enabled && !sent && controller.text.trim().isNotEmpty) {
      widget.onSubmit(controller.text.trim());
    }
  }
}

class OrderingQuestionView extends StatefulWidget {
  const OrderingQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    this.submitted = false,
    this.team,
    this.onChanged,
    super.key,
  });
  final OrderingQuestion question;
  final bool enabled;
  final ValueChanged<List<String>> onSubmit;
  final bool submitted;

  /// Set when the team shares one answer.
  final TeamAnswerMode? team;

  /// Called with every change of the input, before it is sent.
  final ValueChanged<List<String>>? onChanged;
  @override
  State<OrderingQuestionView> createState() => _OrderingQuestionViewState();
}

class _OrderingQuestionViewState extends State<OrderingQuestionView> {
  late List<AnswerOption> items;
  @override
  void initState() {
    super.initState();
    items = [...widget.question.items]
      ..shuffle(Random(widget.question.id.hashCode));
  }

  void move(int index, int offset) {
    setState(() {
      final item = items.removeAt(index);
      items.insert(index + offset, item);
    });
    widget.onChanged?.call([for (final item in items) item.id]);
  }

  bool get sent => switch (widget.team) {
    null => widget.submitted,
    TeamAnswerMode(valid: OrderingAnswer(:final itemIds)) => sameOrder(
      itemIds,
      [for (final item in items) item.id],
    ),
    _ => false,
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, item) in items.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text('${i + 1}.'),
              const SizedBox(width: 12),
              Expanded(child: Text(item.label)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.tr("{0} nach oben", [item.label]),
                onPressed: widget.enabled && i > 0 ? () => move(i, -1) : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: context.tr("{0} nach unten", [item.label]),
                onPressed: widget.enabled && i < items.length - 1
                    ? () => move(i, 1)
                    : null,
                icon: const Icon(Icons.arrow_downward),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      AnswerSubmitButton(
        sent: sent,
        replaces: widget.team?.valid != null,
        onPressed: widget.enabled
            ? () => widget.onSubmit(items.map((i) => i.id).toList())
            : null,
        label: context.tr("Reihenfolge senden"),
      ),
    ],
  );
}

class MatchingQuestionView extends StatefulWidget {
  const MatchingQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    this.submitted = false,
    this.team,
    this.onChanged,
    super.key,
  });
  final MatchingQuestion question;
  final bool enabled;
  final ValueChanged<Map<String, String>> onSubmit;
  final bool submitted;

  /// Set when the team shares one answer.
  final TeamAnswerMode? team;

  /// Called with every change of the input, before it is sent.
  final ValueChanged<Map<String, String>>? onChanged;
  @override
  State<MatchingQuestionView> createState() => _MatchingQuestionViewState();
}

class _MatchingQuestionViewState extends State<MatchingQuestionView> {
  final pairs = <String, String>{};

  bool get sent => switch (widget.team) {
    null => widget.submitted,
    TeamAnswerMode(valid: MatchingAnswer(pairs: final valid)) =>
      valid.length == pairs.length &&
          valid.entries.every((entry) => pairs[entry.key] == entry.value),
    _ => false,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
          480;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final left in widget.question.leftItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Builder(
                builder: (context) {
                  final label = Text(left.label);
                  final used = pairs.values.toSet();
                  final options = [
                    ...widget.question.rightItems.where(
                      (r) => !used.contains(r.id),
                    ),
                    ...widget.question.rightItems.where(
                      (r) => used.contains(r.id),
                    ),
                  ];
                  final selected = options
                      .where((r) => r.id == pairs[left.id])
                      .firstOrNull;
                  final field = OutlinedButton.icon(
                    icon: const Icon(Icons.expand_more),
                    label: Text(selected?.label ?? context.tr("Zuordnen")),
                    onPressed: !widget.enabled
                        ? null
                        : () async {
                            final value = await showModalBottomSheet<String>(
                              context: context,
                              showDragHandle: true,
                              isScrollControlled: true,
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * .9,
                              ),
                              builder: (context) => PointerInterceptor(
                                child: SafeArea(
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      ListTile(title: Text(left.label)),
                                      if (selected != null)
                                        ListTile(
                                          title: Text(
                                            context.tr("Auswahl löschen"),
                                          ),
                                          onTap: () =>
                                              Navigator.pop(context, ''),
                                        ),
                                      for (final right in options)
                                        ListTile(
                                          title: Text(right.label),
                                          selected: right.id == selected?.id,
                                          enabled:
                                              !used.contains(right.id) ||
                                              right.id == selected?.id,
                                          onTap: () =>
                                              Navigator.pop(context, right.id),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                            if (!mounted || !widget.enabled || value == null) {
                              return;
                            }
                            setState(() {
                              if (value.isEmpty) {
                                pairs.remove(left.id);
                              } else {
                                pairs[left.id] = value;
                              }
                            });
                            widget.onChanged?.call({...pairs});
                          },
                  );
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [label, const SizedBox(height: 12), field],
                        )
                      : Row(
                          children: [
                            Expanded(child: label),
                            const SizedBox(width: 16),
                            Expanded(child: field),
                          ],
                        );
                },
              ),
            ),
          const SizedBox(height: 16),
          AnswerSubmitButton(
            sent: sent,
            replaces: widget.team?.valid != null,
            onPressed:
                widget.enabled &&
                    pairs.length == widget.question.leftItems.length &&
                    pairs.values.toSet().length == pairs.length
                ? () => widget.onSubmit({...pairs})
                : null,
            label: context.tr("Zuordnung senden"),
          ),
        ],
      );
    },
  );
}

class EstimationQuestionView extends StatefulWidget {
  const EstimationQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    this.submitted = false,
    this.team,
    this.onChanged,
    super.key,
  });
  final EstimationQuestion question;
  final bool enabled;
  final ValueChanged<double> onSubmit;
  final bool submitted;

  /// Set when the team shares one answer.
  final TeamAnswerMode? team;

  /// Called with every change of the input, before it is sent.
  final ValueChanged<double?>? onChanged;
  @override
  State<EstimationQuestionView> createState() => _EstimationQuestionViewState();
}

class _EstimationQuestionViewState extends State<EstimationQuestionView> {
  String text = '';
  double? get value {
    final v = double.tryParse(text.replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

  bool get sent => switch (widget.team) {
    null => widget.submitted,
    TeamAnswerMode(valid: EstimationAnswer(value: final valid)) =>
      valid == value,
    _ => false,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: context.tr("Deine Schätzung"),
          suffixText: widget.question.unit,
        ),
        onChanged: (v) {
          setState(() => text = v);
          widget.onChanged?.call(value);
        },
      ),
      const SizedBox(height: 16),
      AnswerSubmitButton(
        sent: sent,
        replaces: widget.team?.valid != null,
        onPressed: widget.enabled && value != null
            ? () => widget.onSubmit(value!)
            : null,
        label: context.tr("Schätzung senden"),
      ),
    ],
  );
}

class TrueFalseQuestionView extends StatefulWidget {
  const TrueFalseQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    this.submitted = false,
    this.chosen,
    this.team,
    super.key,
  });
  final TrueFalseQuestion question;
  final bool enabled;
  final ValueChanged<bool> onSubmit;
  final bool submitted;

  /// The answer of this player from the snapshot, when it is known.
  final bool? chosen;

  /// Set when the team shares one answer.
  final TeamAnswerMode? team;

  @override
  State<TrueFalseQuestionView> createState() => _TrueFalseQuestionViewState();
}

class _TrueFalseQuestionViewState extends State<TrueFalseQuestionView> {
  bool? _pressed;

  @override
  void didUpdateWidget(TrueFalseQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rejected answer unlocks the buttons again: forget the old press.
    if (oldWidget.submitted && !widget.submitted) _pressed = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final team = widget.team;
    // In a team the own last press stays marked while it may be replaced.
    final chosen =
        (team == null ? null : _pressed) ??
        widget.chosen ??
        (widget.submitted ? _pressed : null);
    final counts = switch (team?.valid) {
      TrueFalseAnswer(:final value) => value,
      _ => null,
    };
    Widget option(bool value, IconData icon, String label) {
      final selected = chosen == value;
      return FilledButton.icon(
        key: ValueKey('true-false-$value'),
        onPressed:
            widget.enabled && (team == null ? chosen == null : counts != value)
            ? () {
                setState(() => _pressed = value);
                widget.onSubmit(value);
              }
            : null,
        style: selected
            ? FilledButton.styleFrom(
                disabledBackgroundColor: scheme.tertiary,
                disabledForegroundColor: scheme.onTertiary,
                side: BorderSide(color: scheme.onTertiaryContainer, width: 2),
              )
            : null,
        icon: Icon(selected ? Icons.check_circle : icon),
        label: Text(
          [
            context.tr(label),
            if (counts == value) context.tr('Teamantwort'),
          ].join(' · '),
        ),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        option(true, Icons.check, "Wahr"),
        option(false, Icons.close, "Falsch"),
      ],
    );
  }
}
