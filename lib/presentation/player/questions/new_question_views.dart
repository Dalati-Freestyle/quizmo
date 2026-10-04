import 'dart:math';

import 'package:flutter/material.dart';

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
    children: [
      TextField(
        controller: controller,
        enabled: widget.enabled,
        maxLength: 2000,
        decoration: const InputDecoration(labelText: 'Deine Antwort'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => submit(),
      ),
      FilledButton(
        onPressed: widget.enabled && controller.text.trim().isNotEmpty
            ? submit
            : null,
        child: const Text('Antwort senden'),
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
    children: [
      for (final (i, item) in items.indexed)
        Row(
          children: [
            Text('${i + 1}. '),
            Expanded(child: Text(item.label)),
            IconButton(
              tooltip: '${item.label} nach oben',
              onPressed: widget.enabled && i > 0 ? () => move(i, -1) : null,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: '${item.label} nach unten',
              onPressed: widget.enabled && i < items.length - 1
                  ? () => move(i, 1)
                  : null,
              icon: const Icon(Icons.arrow_downward),
            ),
          ],
        ),
      FilledButton(
        onPressed: widget.enabled
            ? () => widget.onSubmit(items.map((i) => i.id).toList())
            : null,
        child: const Text('Reihenfolge senden'),
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
  Widget build(BuildContext context) => Column(
    children: [
      for (final left in widget.question.leftItems)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(left.label)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('${left.id}-${pairs[left.id]}'),
                  initialValue: pairs[left.id],
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Zuordnen'),
                  items: [
                    for (final right in widget.question.rightItems)
                      DropdownMenuItem(
                        value: right.id,
                        child: Text(right.label),
                      ),
                  ],
                  onChanged: widget.enabled
                      ? (value) => setState(() {
                          pairs.removeWhere(
                            (id, partner) => id != left.id && partner == value,
                          );
                          pairs[left.id] = value!;
                        })
                      : null,
                ),
              ),
            ],
          ),
        ),
      FilledButton(
        onPressed:
            widget.enabled &&
                pairs.length == widget.question.leftItems.length &&
                pairs.values.toSet().length == pairs.length
            ? () => widget.onSubmit({...pairs})
            : null,
        child: const Text('Zuordnung senden'),
      ),
    ],
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
    children: [
      TextField(
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: 'Deine Schätzung',
          suffixText: widget.question.unit,
        ),
        onChanged: (v) => setState(() => text = v),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: widget.enabled && value != null
            ? () => widget.onSubmit(value!)
            : null,
        child: const Text('Schätzung senden'),
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
        label: const Text('Wahr'),
      ),
      FilledButton.icon(
        onPressed: enabled ? () => onSubmit(false) : null,
        icon: const Icon(Icons.close),
        label: const Text('Falsch'),
      ),
    ],
  );
}
