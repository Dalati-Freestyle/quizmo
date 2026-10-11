import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/models/models.dart';

class ShortAnswerQuestionView extends StatefulWidget {
  const ShortAnswerQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });
  final ShortAnswerQuestion question;
  final bool enabled;
  final ValueChanged<String> onSubmit;
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
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: widget.enabled && controller.text.trim().isNotEmpty
            ? submit
            : null,
        child: Text(context.tr("Antwort senden")),
      ),
    ],
  );
  void submit() {
    if (widget.enabled && controller.text.trim().isNotEmpty) {
      widget.onSubmit(controller.text.trim());
    }
  }
}

class OrderingQuestionView extends StatefulWidget {
  const OrderingQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });
  final OrderingQuestion question;
  final bool enabled;
  final ValueChanged<List<String>> onSubmit;
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

  void move(int index, int offset) => setState(() {
    final item = items.removeAt(index);
    items.insert(index + offset, item);
  });
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
      FilledButton(
        onPressed: widget.enabled
            ? () => widget.onSubmit(items.map((i) => i.id).toList())
            : null,
        child: Text(context.tr("Reihenfolge senden")),
      ),
    ],
  );
}

class MatchingQuestionView extends StatefulWidget {
  const MatchingQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });
  final MatchingQuestion question;
  final bool enabled;
  final ValueChanged<Map<String, String>> onSubmit;
  @override
  State<MatchingQuestionView> createState() => _MatchingQuestionViewState();
}

class _MatchingQuestionViewState extends State<MatchingQuestionView> {
  final pairs = <String, String>{};
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
                  final field = DropdownButtonFormField<String>(
                    key: ValueKey('${left.id}-${pairs[left.id]}'),
                    initialValue: pairs[left.id],
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    decoration: InputDecoration(
                      labelText: context.tr("Zuordnen"),
                    ),
                    selectedItemBuilder: (context) => [
                      if (pairs[left.id] != null) Text(context.tr("Zuordnen")),
                      for (final right in options)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(right.label),
                        ),
                    ],
                    items: [
                      if (pairs[left.id] != null)
                        DropdownMenuItem(
                          value: '',
                          child: Text(context.tr("Auswahl löschen")),
                        ),
                      for (final right in options)
                        DropdownMenuItem(
                          value: right.id,
                          enabled:
                              !used.contains(right.id) ||
                              pairs[left.id] == right.id,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              right.label,
                              style: used.contains(right.id)
                                  ? TextStyle(
                                      color: Theme.of(context).disabledColor,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                    onChanged: widget.enabled
                        ? (value) => setState(() {
                            if (value == null || value.isEmpty) {
                              pairs.remove(left.id);
                            } else {
                              pairs[left.id] = value;
                            }
                          })
                        : null,
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
          FilledButton(
            onPressed:
                widget.enabled &&
                    pairs.length == widget.question.leftItems.length &&
                    pairs.values.toSet().length == pairs.length
                ? () => widget.onSubmit({...pairs})
                : null,
            child: Text(context.tr("Zuordnung senden")),
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
    super.key,
  });
  final EstimationQuestion question;
  final bool enabled;
  final ValueChanged<double> onSubmit;
  @override
  State<EstimationQuestionView> createState() => _EstimationQuestionViewState();
}

class _EstimationQuestionViewState extends State<EstimationQuestionView> {
  String text = '';
  double? get value {
    final v = double.tryParse(text.replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

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
        onChanged: (v) => setState(() => text = v),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: widget.enabled && value != null
            ? () => widget.onSubmit(value!)
            : null,
        child: Text(context.tr("Schätzung senden")),
      ),
    ],
  );
}

class TrueFalseQuestionView extends StatelessWidget {
  const TrueFalseQuestionView({
    required this.question,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });
  final TrueFalseQuestion question;
  final bool enabled;
  final ValueChanged<bool> onSubmit;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 16,
    children: [
      FilledButton.icon(
        onPressed: enabled ? () => onSubmit(true) : null,
        icon: const Icon(Icons.check),
        label: Text(context.tr("Wahr")),
      ),
      FilledButton.icon(
        onPressed: enabled ? () => onSubmit(false) : null,
        icon: const Icon(Icons.close),
        label: Text(context.tr("Falsch")),
      ),
    ],
  );
}
