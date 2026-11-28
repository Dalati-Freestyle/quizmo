/// Edits the framing settings of many questions at once.
library;

import 'package:flutter/material.dart';

import 'category_field.dart';

import '../../../core/engine/scoring_rules.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import '../../l10n/app_localizations.dart';

/// Which questions a bulk edit reaches.
typedef QuestionFilter = bool Function(Question question);

/// Result of [QuestionBulkEditDialog].
typedef BulkEditResult = ({QuestionBulkEdit edit, QuestionFilter where});

/// Editor card that opens [QuestionBulkEditDialog].
class BulkEditPanel extends StatelessWidget {
  /// Creates the card for [quiz].
  const BulkEditPanel({required this.quiz, required this.onApply, super.key});

  final Quiz quiz;
  final void Function(QuestionBulkEdit edit, QuestionFilter where) onApply;

  @override
  Widget build(BuildContext context) => PanelCard(
    title: context.tr("Fragen gemeinsam bearbeiten"),
    icon: Icons.tune,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
            "Zeitlimits, Kategorie, Wertung, Medien und weitere Einstellungen für viele Fragen auf einmal setzen. Fragetext und Lösungen bleiben unverändert; jede Frage lässt sich danach weiter einzeln anpassen.",
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('bulk-edit'),
            onPressed: quiz.questions.isEmpty
                ? null
                : () async {
                    final result = await showDialog<BulkEditResult>(
                      context: context,
                      builder: (_) => QuestionBulkEditDialog(quiz: quiz),
                    );
                    if (result != null) onApply(result.edit, result.where);
                  },
            icon: const Icon(Icons.tune),
            label: Text(context.tr("Gemeinsam bearbeiten …")),
          ),
        ),
      ],
    ),
  );
}

enum _Rule { unchanged, fixed, speedBonus, firstBuzzer }

enum _Limit { unchanged, none, seconds }

/// Picks the questions and the settings to change; every setting starts as
/// "unchanged".
class QuestionBulkEditDialog extends StatefulWidget {
  /// Creates the dialog for [quiz].
  const QuestionBulkEditDialog({required this.quiz, super.key});

  final Quiz quiz;

  @override
  State<QuestionBulkEditDialog> createState() => _QuestionBulkEditDialogState();
}

class _QuestionBulkEditDialogState extends State<QuestionBulkEditDialog> {
  int _scope = 0;
  _Limit _limit = _Limit.unchanged;
  final _seconds = TextEditingController(text: '30');
  bool? _soft;
  bool _setCategory = false;
  final _category = TextEditingController();
  _Rule _rule = _Rule.unchanged;
  final _points = [
    TextEditingController(text: '10'),
    TextEditingController(text: '0'),
    TextEditingController(text: '0'),
  ];
  bool? _hideQuestionMedia;
  bool? _hideSolutionMedia;
  bool? _zoom;
  bool? _manualGrading;
  final _maxEdits = TextEditingController();
  final _fullKm = TextEditingController();
  final _zeroKm = TextEditingController();
  bool? _lockOut;
  bool? _hostEnds;

  @override
  void dispose() {
    for (final controller in [
      _seconds,
      _category,
      _maxEdits,
      _fullKm,
      _zeroKm,
      ..._points,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Selectable groups of questions: all, per kind, per category.
  List<(String, QuestionFilter)> _scopes(BuildContext context) {
    final questions = widget.quiz.questions;
    String label(String text, QuestionFilter where) =>
        '$text (${questions.where(where).length})';
    final kinds = {for (final q in questions) q.kindLabel};
    final categories = {
      for (final q in questions)
        if (q.category case final c? when c.trim().isNotEmpty) c,
    };
    return [
      (label(context.tr("Alle Fragen"), (_) => true), (_) => true),
      for (final kind in kinds)
        (
          label(context.tr("Typ: {0}", [context.tr(kind)]), (q) {
            return q.kindLabel == kind;
          }),
          (q) => q.kindLabel == kind,
        ),
      for (final category in categories)
        (
          label(context.tr("Kategorie: {0}", [category]), (q) {
            return q.category == category;
          }),
          (q) => q.category == category,
        ),
    ];
  }

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  /// The edit, or `null` while an entered number is invalid.
  QuestionBulkEdit? get _edit {
    final seconds = _int(_seconds);
    if (_limit == _Limit.seconds && (seconds == null || seconds < 1)) {
      return null;
    }
    final values = [for (final c in _points) _int(c)];
    if (_rule != _Rule.unchanged && values.any((v) => v == null)) return null;
    final maxEdits = _maxEdits.text.trim().isEmpty ? null : _int(_maxEdits);
    if (_maxEdits.text.trim().isNotEmpty &&
        (maxEdits == null || maxEdits < 0 || maxEdits > 5)) {
      return null;
    }
    double? km(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.'));
    final fullKm = _fullKm.text.trim().isEmpty ? null : km(_fullKm);
    final zeroKm = _zeroKm.text.trim().isEmpty ? null : km(_zeroKm);
    if ((_fullKm.text.trim().isNotEmpty && (fullKm == null || fullKm < 0)) ||
        (_zeroKm.text.trim().isNotEmpty && (zeroKm == null || zeroKm <= 0)) ||
        (fullKm != null && zeroKm != null && zeroKm <= fullKm)) {
      return null;
    }
    return QuestionBulkEdit(
      fullPointsKm: fullKm,
      zeroPointsKm: zeroKm,
      timeLimit: switch (_limit) {
        _Limit.unchanged => null,
        _Limit.none => Duration.zero,
        _Limit.seconds => Duration(seconds: seconds!),
      },
      softTimeLimit: _soft,
      category: _setCategory ? _category.text : null,
      scoringRule: switch (_rule) {
        _Rule.unchanged => null,
        _Rule.fixed => FixedPointsRule(
          correctPoints: values[0]!,
          wrongPoints: values[1]!,
        ),
        _Rule.speedBonus => SpeedBonusRule(
          basePoints: values[0]!,
          maxSpeedBonus: values[1]!,
          wrongPoints: values[2]!,
        ),
        _Rule.firstBuzzer => FirstBuzzerRule(
          points: values[0]!,
          penalty: values[1]!,
          rankDecay: values[2]!,
        ),
      },
      hideQuestionMediaDetails: _hideQuestionMedia,
      hideSolutionMediaDetails: _hideSolutionMedia,
      imageZoom: _zoom,
      manualGrading: _manualGrading,
      maxEdits: maxEdits,
      lockOutOnMiss: _lockOut,
      hostEndsRound: _hostEnds,
    );
  }

  Widget _choice(
    String key,
    String label,
    bool? value,
    ValueChanged<bool?> onChanged, {
    required String yes,
    required String no,
  }) => DropdownButtonFormField<bool?>(
    key: ValueKey('bulk-$key'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: null, child: Text(context.tr("unverändert"))),
      DropdownMenuItem(value: true, child: Text(yes)),
      DropdownMenuItem(value: false, child: Text(no)),
    ],
    onChanged: (value) => setState(() => onChanged(value)),
  );

  Widget _number(String key, TextEditingController controller, String label) =>
      SizedBox(
        width: 150,
        child: TextField(
          key: ValueKey('bulk-$key'),
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final scopes = _scopes(context);
    final scope = scopes[_scope.clamp(0, scopes.length - 1)];
    final count = widget.quiz.questions.where(scope.$2).length;
    final edit = _edit;
    final pointLabels = switch (_rule) {
      _Rule.unchanged => const <String>[],
      _Rule.fixed => [
        context.tr("Punkte richtig"),
        context.tr("Punkte falsch"),
      ],
      _Rule.speedBonus => [
        context.tr("Grundpunkte"),
        context.tr("Max. Bonus"),
        context.tr("Punkte falsch"),
      ],
      _Rule.firstBuzzer => [
        context.tr("Punkte"),
        context.tr("Abzug falsch"),
        context.tr("Abzug pro Rang"),
      ],
    };
    return AlertDialog(
      title: Text(context.tr("Fragen gemeinsam bearbeiten")),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: const ValueKey('bulk-scope'),
                initialValue: _scope,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr("Welche Fragen"),
                ),
                items: [
                  for (final (index, entry) in scopes.indexed)
                    DropdownMenuItem(value: index, child: Text(entry.$1)),
                ],
                onChanged: (value) => setState(() => _scope = value ?? 0),
              ),
              _section(context.tr("Zeitlimit")),
              DropdownButtonFormField<_Limit>(
                key: const ValueKey('bulk-limit'),
                initialValue: _limit,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr("Zeitlimit")),
                items: [
                  DropdownMenuItem(
                    value: _Limit.unchanged,
                    child: Text(context.tr("unverändert")),
                  ),
                  DropdownMenuItem(
                    value: _Limit.none,
                    child: Text(context.tr("Kein Zeitlimit")),
                  ),
                  DropdownMenuItem(
                    value: _Limit.seconds,
                    child: Text(context.tr("Sekunden festlegen")),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _limit = value ?? _Limit.unchanged),
              ),
              if (_limit == _Limit.seconds)
                _number('seconds', _seconds, context.tr("Sekunden")),
              _choice(
                'soft',
                context.tr("Art des Zeitlimits"),
                _soft,
                (value) => _soft = value,
                yes: context.tr("Weich: Spielleitung beendet die Runde"),
                no: context.tr("Hart: Antworten schließen automatisch"),
              ),
              _section(context.tr("Kategorie")),
              CheckboxListTile(
                key: const ValueKey('bulk-set-category'),
                contentPadding: EdgeInsets.zero,
                value: _setCategory,
                title: Text(context.tr("Kategorie setzen (leer = entfernen)")),
                onChanged: (value) =>
                    setState(() => _setCategory = value ?? false),
              ),
              if (_setCategory)
                CategoryField(
                  key: const ValueKey('bulk-category'),
                  controller: _category,
                  categories: widget.quiz.categories,
                  label: context.tr("Kategorie"),
                ),
              _section(context.tr("Wertung")),
              DropdownButtonFormField<_Rule>(
                key: const ValueKey('bulk-rule'),
                initialValue: _rule,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr("Wertung")),
                items: [
                  DropdownMenuItem(
                    value: _Rule.unchanged,
                    child: Text(context.tr("unverändert")),
                  ),
                  DropdownMenuItem(
                    value: _Rule.fixed,
                    child: Text(context.tr("Feste Punkte")),
                  ),
                  DropdownMenuItem(
                    value: _Rule.speedBonus,
                    child: Text(context.tr("Geschwindigkeitsbonus")),
                  ),
                  DropdownMenuItem(
                    value: _Rule.firstBuzzer,
                    child: Text(context.tr("Buzzer-Wertung")),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _rule = value ?? _Rule.unchanged;
                  final defaults = switch (_rule) {
                    _Rule.unchanged || _Rule.fixed => ['10', '0', '0'],
                    _Rule.speedBonus => ['10', '10', '0'],
                    _Rule.firstBuzzer => ['15', '-5', '5'],
                  };
                  for (final (i, text) in defaults.indexed) {
                    _points[i].text = text;
                  }
                }),
              ),
              if (pointLabels.isNotEmpty)
                Wrap(
                  spacing: 12,
                  children: [
                    for (final (i, label) in pointLabels.indexed)
                      _number('points-$i', _points[i], label),
                  ],
                ),
              _section(context.tr("Medien")),
              _choice(
                'hide-question-media',
                context.tr("Details der Fragen-Medien"),
                _hideQuestionMedia,
                (value) => _hideQuestionMedia = value,
                yes: context.tr("verbergen"),
                no: context.tr("zeigen"),
              ),
              _choice(
                'hide-solution-media',
                context.tr("Details der Lösungs-Medien"),
                _hideSolutionMedia,
                (value) => _hideSolutionMedia = value,
                yes: context.tr("verbergen"),
                no: context.tr("zeigen"),
              ),
              _choice(
                'zoom',
                context.tr("Bilder per Tipp vergrößern"),
                _zoom,
                (value) => _zoom = value,
                yes: context.tr("ja"),
                no: context.tr("nein"),
              ),
              _section(context.tr("Freitext-Fragen")),
              _choice(
                'manual-grading',
                context.tr("Bewertung"),
                _manualGrading,
                (value) => _manualGrading = value,
                yes: context.tr("von Hand durch die Spielleitung"),
                no: context.tr("automatisch"),
              ),
              _number(
                'max-edits',
                _maxEdits,
                context.tr("Erlaubte Tippfehler (leer = unverändert)"),
              ),
              _section(context.tr("Buzzer-Fragen")),
              _choice(
                'lock-out',
                context.tr("Nach Fehlversuch gesperrt"),
                _lockOut,
                (value) => _lockOut = value,
                yes: context.tr("ja"),
                no: context.tr("nein"),
              ),
              _choice(
                'host-ends',
                context.tr("Spielleitung beendet die Runde"),
                _hostEnds,
                (value) => _hostEnds = value,
                yes: context.tr("ja"),
                no: context.tr("nein"),
              ),
              _section(context.tr("Ort auf der Karte")),
              Wrap(
                spacing: 12,
                children: [
                  _number(
                    'full-km',
                    _fullKm,
                    context.tr("Volle Punkte bis (km)"),
                  ),
                  _number(
                    'zero-km',
                    _zeroKm,
                    context.tr("Keine Punkte ab (km)"),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                edit == null
                    ? context.tr("Bitte gültige Zahlen eingeben.")
                    : context.tr(
                        "Gilt für {0} Fragen. Nicht gewählte Einstellungen bleiben, wie sie sind.",
                        [count],
                      ),
                style: TextStyle(
                  color: edit == null
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr("Cancel")),
        ),
        FilledButton(
          key: const ValueKey('bulk-apply'),
          onPressed: edit == null || edit.isEmpty || count == 0
              ? null
              : () =>
                    Navigator.of(context)
                        .pop<BulkEditResult>((edit: edit, where: scope.$2)),
          child: Text(context.tr("Übernehmen")),
        ),
      ],
    );
  }
}
