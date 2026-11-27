import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/engine/answer_evaluation.dart';
import '../../../core/models/models.dart';

/// Shown where a solution would be entered in a quiz without solutions.
const kNoSolutionHint =
    'In diesem Modus gibt es keine richtige Lösung: Es punktet die seltenste Antwort.';

class NewQuestionFields extends StatefulWidget {
  const NewQuestionFields({
    required this.question,
    required this.onChanged,
    this.showSolution = true,
    super.key,
  });

  /// Whether the solution is edited; `false` in a quiz without solutions.
  final bool showSolution;
  final Question question;
  final ValueChanged<Map<String, Object?>> onChanged;
  @override
  State<NewQuestionFields> createState() => _NewQuestionFieldsState();
}

class _NewQuestionFieldsState extends State<NewQuestionFields> {
  late String content;
  late int edits;
  late bool manualGrading;
  late String unit;
  late String scale;
  late String minAccepted;
  late String maxAccepted;
  late bool toleranceOnly;

  /// `null`: not chosen yet (after a change of the kind).
  late bool? truth;

  /// Whether the lines of an ordering are the right order; asked for when
  /// the order is unknown (after a change of the kind).
  late bool orderConfirmed;
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
        [
          // Without a stored pairing the items are listed side by side.
          for (final (index, i) in leftItems.indexed)
            '${i.label} = ${(correctPairs == null ? rightItems.elementAtOrNull(index) : rightItems.where((r) => r.id == correctPairs[i.id]).firstOrNull)?.label ?? ''}',
        ].join('\n'),
      EstimationQuestion(:final correctValue) => _number(correctValue),
      LocationQuestion() ||
      TrueFalseQuestion() ||
      MultipleChoiceQuestion() ||
      BuzzerQuestion() => '',
    };
    edits = q is ShortAnswerQuestion ? q.maxEdits : 1;
    manualGrading = q is ShortAnswerQuestion && q.manualGrading;
    unit = q is EstimationQuestion ? q.unit : '';
    scale = q is EstimationQuestion ? _number(q.zeroScale) : '1';
    minAccepted = q is EstimationQuestion ? _number(q.minAccepted) : '';
    maxAccepted = q is EstimationQuestion ? _number(q.maxAccepted) : '';
    toleranceOnly = q is EstimationQuestion && q.toleranceOnly;
    truth = q is TrueFalseQuestion ? q.correctAnswer : true;
    orderConfirmed = q is! OrderingQuestion || q.correctOrder != null;
  }

  static String _number(double? value) =>
      value == null ? '' : formatNumber(value);

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  String? _optionalNumber(String? text) =>
      (text ?? '').trim().isEmpty || (_parse(text!)?.isFinite ?? false)
      ? null
      : context.tr('Endliche Zahl angeben.');

  /// The limits are required in the mode "tolerance only".
  String? _boundary(String? text) =>
      toleranceOnly && (text ?? '').trim().isEmpty
      ? context.tr('Pflichtfeld bei „Nur Toleranz“.')
      : _optionalNumber(text);

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
        'manualGrading': manualGrading,
      },
      OrderingQuestion() => _orderingFields(),
      MatchingQuestion() => _matchingFields(),
      EstimationQuestion() => <String, Object?>{
        'correctValue': _parse(content),
        'unit': unit,
        'zeroScale': _parse(scale),
        'minAccepted': _parse(minAccepted),
        'maxAccepted': _parse(maxAccepted),
        'toleranceOnly': toleranceOnly,
      },
      TrueFalseQuestion() => <String, Object?>{
        if (widget.showSolution) 'correctAnswer': truth,
      },
      LocationQuestion() ||
      MultipleChoiceQuestion() ||
      BuzzerQuestion() => <String, Object?>{},
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
      // An order nobody confirmed is no solution.
      'correctOrder': orderConfirmed
          ? [for (final label in lines) 'item-${sorted.indexOf(label)}']
          : null,
    };
  }

  Map<String, Object?> _matchingFields() {
    final pairs = lines.map((l) => l.split('=')).toList();
    // IDs and public order are independent of the solution pairing.
    final right = pairs.map((p) => p.length == 2 ? p[1].trim() : '').toList()
      ..sort();
    // The same value may occur on several lines: each line gets its own item.
    final free = [for (final (i, label) in right.indexed) (i, label)];
    int take(String label) {
      final index = free.indexWhere((item) => item.$2 == label);
      return free.removeAt(index).$1;
    }

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
          'left-$i': 'right-${take(p.length == 2 ? p[1].trim() : '')}',
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
            widget.showSolution
                ? context.tr("Lösung und Einstellungen")
                : context.tr("Antwortmöglichkeiten"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (!widget.showSolution) ...[
            Text(context.tr(kNoSolutionHint)),
            const SizedBox(height: 12),
          ],
          if (widget.question is TrueFalseQuestion && !widget.showSolution)
            Text(context.tr("Die Spieler wählen zwischen Wahr und Falsch."))
          else if (widget.question is TrueFalseQuestion)
            SegmentedButton<bool>(
              key: const ValueKey('true-false-solution'),
              // Nothing chosen yet after a change of the kind: no guess.
              emptySelectionAllowed: true,
              segments: [
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.check),
                  label: Text(context.tr("Lösung: Wahr")),
                ),
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.close),
                  label: Text(context.tr("Lösung: Falsch")),
                ),
              ],
              selected: {?truth},
              onSelectionChanged: (selection) {
                setState(() => truth = selection.firstOrNull);
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
                  OrderingQuestion() =>
                    widget.showSolution
                        ? context.tr(
                            "Elemente in korrekter Reihenfolge – eines pro Zeile",
                          )
                        : context.tr("Elemente – eines pro Zeile"),
                  MatchingQuestion() =>
                    widget.showSolution
                        ? context.tr("Paare – pro Zeile: links = rechts")
                        : context.tr(
                            "Elemente – pro Zeile: links = rechts (die Zuordnung wird nicht gespeichert)",
                          ),
                  EstimationQuestion() => context.tr("Korrekte Zahl"),
                  LocationQuestion() ||
                  TrueFalseQuestion() ||
                  MultipleChoiceQuestion() ||
                  BuzzerQuestion() => 'Lösung',
                },
              ),
              validator: widget.question is EstimationQuestion
                  ? _optionalNumber
                  : null,
              autovalidateMode: widget.question is EstimationQuestion
                  ? AutovalidateMode.onUserInteraction
                  : null,
              onChanged: (v) {
                // The field for the target 0 appears and disappears.
                setState(() => content = v);
                changed();
              },
            ),
          if (widget.question is OrderingQuestion &&
              widget.showSolution &&
              !orderConfirmed)
            CheckboxListTile(
              key: const ValueKey('confirm-order'),
              contentPadding: EdgeInsets.zero,
              value: orderConfirmed,
              title: Text(
                context.tr('Die Zeilen stehen in der richtigen Reihenfolge.'),
              ),
              subtitle: Text(
                context.tr(
                  'Die richtige Reihenfolge muss noch festgelegt werden.',
                ),
              ),
              onChanged: (value) {
                setState(() => orderConfirmed = value ?? false);
                changed();
              },
            ),
          if (widget.question is MatchingQuestion && widget.showSolution) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                "Gleiche Werte rechts dürfen mehrfach vorkommen; sie sind untereinander austauschbar.",
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          if (widget.question is ShortAnswerQuestion) ...[
            DropdownButtonFormField<bool>(
              initialValue: manualGrading,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Bewertung')),
              items: [
                DropdownMenuItem(
                  value: false,
                  child: Text(context.tr('Automatisch')),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text(
                    context.tr('Manuell durch den Spielleiter'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => manualGrading = value);
                changed();
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              initialValue: edits,
              decoration: InputDecoration(
                labelText: context.tr("Erlaubte Zeichenänderungen"),
                helperText: manualGrading
                    ? context.tr(
                        'Bei manueller Bewertung gilt diese Toleranz nur für die Empfehlung. Der Spielleiter entscheidet.',
                      )
                    : null,
                helperMaxLines: 3,
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
          ],
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
            DropdownButtonFormField<bool>(
              key: const ValueKey('estimation-mode'),
              initialValue: toleranceOnly,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Wertung')),
              items: [
                DropdownMenuItem(
                  value: false,
                  child: Text(
                    context.tr('Nach Abweichung'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text(
                    context.tr('Nur Toleranz (richtig/falsch)'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => toleranceOnly = value);
                changed();
              },
            ),
            const SizedBox(height: 12),
            if (toleranceOnly)
              Text(
                context.tr(
                  'Innerhalb der Grenzen volle Punkte, außerhalb keine.',
                ),
              )
            else ...[
              Text(
                context.tr(
                  "Punkte = Maximalpunkte × max(0, 1 − relative Abweichung).",
                ),
              ),
              // Only the target 0 needs a scale: the relative deviation is
              // undefined there. A stored scale is kept while hidden.
              if (_parse(content) == 0) ...[
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('estimation-zero-scale'),
                  initialValue: scale,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      "Abweichung für 0 Punkte bei Zielwert 0",
                    ),
                  ),
                  onChanged: (v) {
                    scale = v;
                    changed();
                  },
                ),
              ],
            ],
            const SizedBox(height: 20),
            Text(
              toleranceOnly
                  ? context.tr('Toleranz')
                  : context.tr('Toleranz (optional)'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Antworten von der Unter- bis zur Obergrenze gelten als vollständig richtig.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('estimation-min'),
                    initialValue: minAccepted,
                    decoration: InputDecoration(
                      labelText: context.tr('Untergrenze'),
                    ),
                    validator: _boundary,
                    onChanged: (v) {
                      minAccepted = v;
                      changed();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('estimation-max'),
                    initialValue: maxAccepted,
                    decoration: InputDecoration(
                      labelText: context.tr('Obergrenze'),
                    ),
                    validator: _boundary,
                    onChanged: (v) {
                      maxAccepted = v;
                      changed();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
