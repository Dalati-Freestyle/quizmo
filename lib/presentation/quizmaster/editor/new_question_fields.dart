import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/models/models.dart';

class NewQuestionFields extends StatefulWidget {
  const NewQuestionFields({
    required this.question,
    required this.onChanged,
    super.key,
  });
  final Question question;
  final ValueChanged<Map<String, Object?>> onChanged;
  @override
  State<NewQuestionFields> createState() => _NewQuestionFieldsState();
}

class _NewQuestionFieldsState extends State<NewQuestionFields> {
  late String content;
  late int edits;
  late String unit;
  late String scale;
  late bool truth;
  @override
  void initState() {
    super.initState();
    final q = widget.question;
    content = switch (q) {
      ShortAnswerQuestion(:final acceptedAnswers) =>
        (acceptedAnswers ?? []).join('\n'),
      OrderingQuestion(:final items, :final correctOrder) =>
        (correctOrder ?? items.map((i) => i.id))
            .map(
              (id) => items.where((i) => i.id == id).firstOrNull?.label ?? '',
            )
            .join('\n'),
      MatchingQuestion(
        :final leftItems,
        :final rightItems,
        :final correctPairs,
      ) =>
        leftItems
            .map(
              (i) =>
                  '${i.label} = ${rightItems.where((r) => r.id == correctPairs?[i.id]).firstOrNull?.label ?? ''}',
            )
            .join('\n'),
      EstimationQuestion(:final correctValue) => correctValue?.toString() ?? '',
      TrueFalseQuestion() || MultipleChoiceQuestion() || BuzzerQuestion() => '',
    };
    edits = q is ShortAnswerQuestion ? q.maxEdits : 1;
    unit = q is EstimationQuestion ? q.unit : '';
    scale = q is EstimationQuestion ? '${q.zeroScale}' : '1';
    truth = q is TrueFalseQuestion ? q.correctAnswer ?? true : true;
  }

  List<String> get lines => content
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  void changed() {
    final fields = switch (widget.question) {
      ShortAnswerQuestion() => <String, Object?>{
        'acceptedAnswers': lines,
        'maxEdits': edits,
      },
      OrderingQuestion() => _orderingFields(),
      MatchingQuestion() => _matchingFields(),
      EstimationQuestion() => <String, Object?>{
        'correctValue': double.tryParse(content.replaceAll(',', '.')),
        'unit': unit,
        'zeroScale': double.tryParse(scale.replaceAll(',', '.')),
      },
      TrueFalseQuestion() => <String, Object?>{'correctAnswer': truth},
      MultipleChoiceQuestion() || BuzzerQuestion() => <String, Object?>{},
    };
    widget.onChanged(fields);
  }

  Map<String, Object?> _orderingFields() {
    final sorted = [...lines]..sort();
    return {
      'items': [
        for (final (i, label) in sorted.indexed)
          {'id': 'item-$i', 'label': label},
      ],
      'correctOrder': [
        for (final label in lines) 'item-${sorted.indexOf(label)}',
      ],
    };
  }

  Map<String, Object?> _matchingFields() {
    final pairs = lines.map((l) => l.split('=')).toList();
    // IDs and public order are independent of the solution pairing.
    final right = pairs.map((p) => p.length == 2 ? p[1].trim() : '').toList()
      ..sort();
    return {
      'leftItems': [
        for (final (i, p) in pairs.indexed)
          {'id': 'left-$i', 'label': p.length == 2 ? p[0].trim() : ''},
      ],
      'rightItems': [
        for (final (i, label) in right.indexed)
          {'id': 'right-$i', 'label': label},
      ],
      'correctPairs': {
        for (final (i, p) in pairs.indexed)
          'left-$i': 'right-${right.indexOf(p.length == 2 ? p[1].trim() : '')}',
      },
    };
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr("Lösung und Einstellungen"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (widget.question is TrueFalseQuestion)
            SwitchListTile(
              title: Text(
                truth
                    ? context.tr("Lösung: Wahr")
                    : context.tr("Lösung: Falsch"),
              ),
              value: truth,
              onChanged: (v) {
                setState(() => truth = v);
                changed();
              },
            )
          else
            TextFormField(
              initialValue: content,
              minLines: widget.question is EstimationQuestion ? 1 : 3,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: switch (widget.question) {
                  ShortAnswerQuestion() => context.tr(
                    "Akzeptierte Antworten – eine pro Zeile",
                  ),
                  OrderingQuestion() => context.tr(
                    "Elemente in korrekter Reihenfolge – eines pro Zeile",
                  ),
                  MatchingQuestion() => context.tr(
                    "Paare – pro Zeile: links = rechts",
                  ),
                  EstimationQuestion() => context.tr("Korrekte Zahl"),
                  TrueFalseQuestion() ||
                  MultipleChoiceQuestion() ||
                  BuzzerQuestion() => 'Lösung',
                },
              ),
              onChanged: (v) {
                content = v;
                changed();
              },
            ),
          const SizedBox(height: 20),
          if (widget.question is ShortAnswerQuestion)
            DropdownButtonFormField<int>(
              initialValue: edits,
              decoration: InputDecoration(
                labelText: context.tr("Erlaubte Zeichenänderungen"),
              ),
              items: [
                for (var i = 0; i <= 5; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) {
                edits = v!;
                changed();
              },
            ),
          if (widget.question is EstimationQuestion) ...[
            TextFormField(
              initialValue: unit,
              decoration: InputDecoration(
                labelText: context.tr("Einheit (optional)"),
              ),
              onChanged: (v) {
                unit = v;
                changed();
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              initialValue: scale,
              decoration: InputDecoration(
                labelText: context.tr("Abweichung für 0 Punkte bei Zielwert 0"),
              ),
              onChanged: (v) {
                scale = v;
                changed();
              },
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                "Punkte = Maximalpunkte × max(0, 1 − relative Abweichung).",
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
