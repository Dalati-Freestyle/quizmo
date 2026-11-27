/// Editor for one polymorphic quiz question.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/engine/scoring_rules.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import 'new_question_fields.dart';
import 'hints_editor.dart';
import 'media_editor.dart';
import 'selection_dropdown.dart';
import 'markdown_field.dart';
import 'location_question_fields.dart';

enum _ScoringRuleKind { fixed, speedBonus, firstBuzzer }

/// A question kind the host can start from, with sensible starting values.
final class QuestionTemplate {
  /// Creates a template that builds a blank question of one kind.
  const QuestionTemplate({
    required this.label,
    required this.icon,
    required this.create,
  });

  /// Menu label.
  final String label;

  /// Menu icon.
  final IconData icon;

  /// Builds a fresh question with the given [id].
  final Question Function(String id) create;
}

/// Every question kind that can be created from a menu, for example for a
/// Jeopardy cell.
///
/// Add one entry here when a new question type is introduced, so that it can
/// be used in every quiz format right away.
/// New questions start without a time limit; the host ends the round.
final List<QuestionTemplate> kQuestionTemplates = [
  QuestionTemplate(
    label: 'Freitext',
    icon: Icons.text_fields,
    create: (id) => ShortAnswerQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      acceptedAnswers: const ['Antwort'],
    ),
  ),
  QuestionTemplate(
    label: 'Reihenfolge',
    icon: Icons.sort,
    create: (id) => OrderingQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      items: const [
        AnswerOption(id: 'a', label: 'Erstes'),
        AnswerOption(id: 'b', label: 'Zweites'),
      ],
      correctOrder: const ['a', 'b'],
    ),
  ),
  QuestionTemplate(
    label: 'Zuordnung',
    icon: Icons.compare_arrows,
    create: (id) => MatchingQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      leftItems: const [
        AnswerOption(id: 'a', label: 'Deutschland'),
        AnswerOption(id: 'b', label: 'Frankreich'),
      ],
      rightItems: const [
        AnswerOption(id: 'x', label: 'Berlin'),
        AnswerOption(id: 'y', label: 'Paris'),
      ],
      correctPairs: const {'a': 'x', 'b': 'y'},
    ),
  ),
  QuestionTemplate(
    label: 'Schätzfrage',
    icon: Icons.numbers,
    create: (id) => EstimationQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      correctValue: 100,
    ),
  ),
  QuestionTemplate(
    label: 'Wahr / Falsch',
    icon: Icons.rule,
    create: (id) => TrueFalseQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      correctAnswer: true,
    ),
  ),
  QuestionTemplate(
    label: 'Multiple choice',
    icon: Icons.checklist,
    create: (id) => MultipleChoiceQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      options: const [
        AnswerOption(id: 'option-a', label: 'Option A'),
        AnswerOption(id: 'option-b', label: 'Option B'),
      ],
      correctOptionId: 'option-a',
      scoringRule: const FixedPointsRule(),
    ),
  ),
  QuestionTemplate(
    label: 'Ort auf der Karte',
    icon: Icons.place_outlined,
    create: (id) =>
        LocationQuestion(id: id, timeLimit: Duration.zero, prompt: ''),
  ),
  QuestionTemplate(
    label: 'Fast buzzer',
    icon: Icons.bolt,
    create: (id) => BuzzerQuestion(
      id: id,
      timeLimit: Duration.zero,
      prompt: '',
      scoringRule: const FirstBuzzerRule(),
    ),
  ),
];

/// The templates that can be played in [format].
///
/// A snowflake quiz compares the answers with each other, which only kinds
/// with a finite answer set support (`Question.supportsUniqueness`).
List<QuestionTemplate> questionTemplatesFor(QuizFormat format) =>
    switch (format) {
      StandardFormat() ||
      JeopardyFormat() ||
      PokerFormat() => kQuestionTemplates,
      SnowflakeFormat() => [
        for (final template in kQuestionTemplates)
          if (template.create('').supportsUniqueness) template,
      ],
    };

/// Selects a question kind from the templates shared by every quiz format.
class QuestionTemplateDropdown extends StatelessWidget {
  /// Creates a selector for [value] that reports changes to [onChanged].
  const QuestionTemplateDropdown({
    required this.value,
    required this.onChanged,
    this.templates,
    super.key,
  });

  /// The selected template, or `null` before a kind is chosen.
  final QuestionTemplate? value;

  /// The offered kinds; every kind when `null`.
  final List<QuestionTemplate>? templates;

  /// Receives the selected template.
  final ValueChanged<QuestionTemplate?> onChanged;

  @override
  Widget build(BuildContext context) => SelectionDropdown<QuestionTemplate>(
    label: context.tr("Fragenart"),
    value: (templates ?? kQuestionTemplates).contains(value) ? value : null,
    items: [
      for (final template in templates ?? kQuestionTemplates)
        DropdownMenuItem(
          value: template,
          child: Row(
            children: [
              Icon(template.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(template.label),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
    onChanged: onChanged,
  );
}

/// Edits [question] and returns a replacement when the host saves it. The
/// kind can be changed: the form is then rebuilt for the new kind, with
/// everything that could be taken over.
class QuestionEditorPage extends StatefulWidget {
  /// Creates an editor for [question].
  const QuestionEditorPage({
    required this.question,
    required this.format,
    super.key,
  });

  final Question question;
  final QuizFormat format;

  @override
  State<QuestionEditorPage> createState() => _QuestionEditorPageState();
}

class _QuestionEditorPageState extends State<QuestionEditorPage> {
  late Question _question = widget.question;
  int _generation = 0;

  /// The content each kind had when it was left, to come back to it.
  final Map<Type, Question> _byKind = {};

  bool get _withSolution => switch (widget.format) {
    SnowflakeFormat() => false,
    StandardFormat() || JeopardyFormat() || PokerFormat() => true,
  };

  Future<bool> _changeKind(Question draft, QuestionTemplate template) async {
    final kind = template.create(draft.id);
    if (kind.runtimeType == draft.runtimeType) return true;
    final conversion = convertQuestion(
      draft,
      kind,
      withSolution: _withSolution,
    );
    if (conversion.losesSomething || conversion.notes.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _KindChangeDialog(
          conversion: conversion,
          from: draft,
          to: template,
        ),
      );
      if (confirmed != true || !mounted) return false;
    }
    final remembered = _byKind[kind.runtimeType];
    _byKind[draft.runtimeType] = draft;
    setState(() {
      _question = remembered == null
          ? conversion.question
          : withSharedFields(remembered, draft);
      _generation++;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) => _QuestionForm(
    key: ValueKey(_generation),
    question: _question,
    format: widget.format,
    onKindChanged: _changeKind,
  );
}

/// Asks before a kind change empties anything; names what goes and what is
/// still to fill in.
class _KindChangeDialog extends StatelessWidget {
  const _KindChangeDialog({
    required this.conversion,
    required this.from,
    required this.to,
  });

  final QuestionConversion conversion;
  final Question from;
  final QuestionTemplate to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String text(ConversionText entry) => context.tr(entry.key, entry.args);
    Widget section(String title, List<ConversionText> entries) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.titleSmall),
        for (final entry in entries) Text('• ${text(entry)}'),
      ],
    );
    return AlertDialog(
      key: const ValueKey('kind-change-dialog'),
      title: Text(
        context.tr('Fragetyp ändern: {0} → {1}', [
          context.tr(from.kindLabel),
          context.tr(to.label),
        ]),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(
                'Gemeinsame Inhalte wie Fragetext, Medien, Tipps und Wertung bleiben erhalten.',
              ),
            ),
            if (conversion.lost.isNotEmpty)
              section(context.tr('Wird entfernt'), conversion.lost),
            if (conversion.notes.isNotEmpty)
              section(context.tr('Hinweis'), conversion.notes),
            if (conversion.todo.isNotEmpty)
              section(context.tr('Danach noch ausfüllen'), conversion.todo),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Gültig wird die Änderung erst mit „Frage speichern“.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('Abbrechen')),
        ),
        FilledButton(
          key: const ValueKey('confirm-kind-change'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr('Fragetyp ändern')),
        ),
      ],
    );
  }
}

/// The form of one kind.
class _QuestionForm extends StatefulWidget {
  const _QuestionForm({
    required this.question,
    required this.format,
    required this.onKindChanged,
    super.key,
  });

  /// Called with the current, unsaved input; `false` keeps the kind.
  final Future<bool> Function(Question draft, QuestionTemplate kind)
  onKindChanged;

  /// Question variant being edited.
  final Question question;

  final QuizFormat format;

  bool get usesQuestionPoints => switch (format) {
    StandardFormat() || SnowflakeFormat() => true,
    JeopardyFormat() || PokerFormat() => false,
  };

  /// Whether hints lower the points; poker has chips instead.
  bool get hintsCostPoints => switch (format) {
    PokerFormat() => false,
    StandardFormat() || JeopardyFormat() || SnowflakeFormat() => true,
  };

  /// Whether the format is played without a stored solution.
  bool get hidesSolution => switch (format) {
    SnowflakeFormat() => true,
    StandardFormat() || JeopardyFormat() || PokerFormat() => false,
  };

  @override
  State<_QuestionForm> createState() => _QuestionFormState();
}

class _QuestionFormState extends State<_QuestionForm> {
  final _formKey = GlobalKey<FormState>();
  int _kindPicker = 0;
  Map<String, Object?> _contentFields = {};
  late List<MediaAttachment> _media;
  late List<MediaAttachment> _solutionMedia;
  late List<QuestionHint> _hints;
  late final TextEditingController _notesController;
  late final TextEditingController _promptController;
  late final TextEditingController _categoryController;
  late final TextEditingController _timeLimitController;
  late final TextEditingController _expectedAnswerController;
  late final TextEditingController _primaryPointsController;
  late final TextEditingController _secondaryPointsController;
  late final TextEditingController _tertiaryPointsController;
  late List<_OptionDraft> _options;
  late String? _correctOptionId;
  List<String> _correctOptionIds = [];
  bool _allowMultipleAnswers = false;
  late bool _lockOutOnMiss;
  bool _hostEndsRound = false;
  bool _softTimeLimit = false;
  late bool _hasTimeLimit;
  late final TextEditingController _retryLimitController;
  late _ScoringRuleKind _scoringKind;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    _softTimeLimit = question.softTimeLimit;
    _hasTimeLimit = question.hasTimeLimit;
    _hostEndsRound = question is BuzzerQuestion && question.hostEndsRound;
    _retryLimitController = TextEditingController(
      text: question is BuzzerQuestion
          ? question.retryLimit?.toString() ?? ''
          : '',
    );
    _notesController = TextEditingController(text: question.adminNotes);
    _media = question.media;
    _solutionMedia = question.solutionMedia;
    _hints = question.hints;
    _promptController = TextEditingController(text: question.prompt);
    _categoryController = TextEditingController(text: question.category ?? '');
    _timeLimitController = TextEditingController(
      text: question.hasTimeLimit
          ? question.timeLimit.inSeconds.toString()
          : '30',
    );
    _expectedAnswerController = TextEditingController(
      text: switch (question) {
        MultipleChoiceQuestion() ||
        ShortAnswerQuestion() ||
        OrderingQuestion() ||
        MatchingQuestion() ||
        LocationQuestion() ||
        EstimationQuestion() ||
        TrueFalseQuestion() => '',
        BuzzerQuestion(:final expectedAnswer) => expectedAnswer ?? '',
      },
    );
    _options = switch (question) {
      MultipleChoiceQuestion(:final options) => [
        for (final option in options) _OptionDraft(option.id, option.label),
      ],
      BuzzerQuestion() ||
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      LocationQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => [],
    };
    _correctOptionId = switch (question) {
      MultipleChoiceQuestion(:final correctOptionId) => correctOptionId,
      BuzzerQuestion() ||
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      LocationQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => null,
    };
    if (question is MultipleChoiceQuestion) {
      _correctOptionIds = [...question.solutionOptionIds];
      _allowMultipleAnswers = question.allowMultipleAnswers;
    }
    _lockOutOnMiss = switch (question) {
      MultipleChoiceQuestion() ||
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      LocationQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => true,
      BuzzerQuestion(:final lockOutOnMiss) => lockOutOnMiss,
    };

    final (kind, primary, secondary, tertiary) = switch (question.scoringRule) {
      FixedPointsRule(:final correctPoints, :final wrongPoints) => (
        _ScoringRuleKind.fixed,
        correctPoints,
        wrongPoints,
        0,
      ),
      SpeedBonusRule(
        :final basePoints,
        :final maxSpeedBonus,
        :final wrongPoints,
      ) =>
        (_ScoringRuleKind.speedBonus, basePoints, maxSpeedBonus, wrongPoints),
      FirstBuzzerRule(:final points, :final penalty, :final rankDecay) => (
        _ScoringRuleKind.firstBuzzer,
        points,
        penalty,
        rankDecay,
      ),
    };
    _scoringKind = kind;
    _primaryPointsController = TextEditingController(text: '$primary');
    _secondaryPointsController = TextEditingController(text: '$secondary');
    _tertiaryPointsController = TextEditingController(text: '$tertiary');
  }

  @override
  void dispose() {
    _retryLimitController.dispose();
    _notesController.dispose();
    _promptController.dispose();
    _categoryController.dispose();
    _timeLimitController.dispose();
    _expectedAnswerController.dispose();
    _primaryPointsController.dispose();
    _secondaryPointsController.dispose();
    _tertiaryPointsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMultipleChoice = switch (widget.question) {
      MultipleChoiceQuestion() => true,
      BuzzerQuestion() ||
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      LocationQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => false,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr("Edit {0} question", [
            context.tr(widget.question.kindLabel),
          ]),
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(context.tr("Save question")),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: AdaptivePanelGrid(
          panels: [
            PanelCard(
              title: context.tr("Question"),
              icon: isMultipleChoice ? Icons.checklist : Icons.bolt,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuestionTemplateDropdown(
                    key: ValueKey('kind-picker-$_kindPicker'),
                    value: kQuestionTemplates
                        .where(
                          (template) =>
                              template.create('').runtimeType ==
                              widget.question.runtimeType,
                        )
                        .firstOrNull,
                    templates: questionTemplatesFor(widget.format),
                    onChanged: (template) async {
                      if (template == null) return;
                      final draft = _draft();
                      final changed = await widget.onKindChanged(
                        draft,
                        template,
                      );
                      // Cancelled: the picker shows the old kind again.
                      if (!changed && mounted) setState(() => _kindPicker++);
                    },
                  ),
                  const SizedBox(height: 12),
                  MarkdownField(
                    key: const ValueKey('prompt-field'),
                    controller: _promptController,
                    label: context.tr("Prompt"),
                    maxLines: 6,
                    // Markdown without anything visible is empty, too.
                    validator: (value) => isBlankMarkdown(value ?? '')
                        ? context.tr("Enter a question prompt.")
                        : null,
                  ),
                  const SizedBox(height: 12),
                  MarkdownField(
                    key: const ValueKey('notes-field'),
                    controller: _notesController,
                    label: context.tr("Admin-Notizen (nur Spielleiter)"),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryController,
                    decoration: InputDecoration(
                      labelText: context.tr("Question category (optional)"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('time-limit-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr("Zeitlimit")),
                    subtitle: Text(
                      context.tr(
                        "Ohne Zeitlimit läuft keine Uhr; der Spielleiter beendet die Runde.",
                      ),
                    ),
                    value: _hasTimeLimit,
                    onChanged: (value) => setState(() => _hasTimeLimit = value),
                  ),
                  if (_hasTimeLimit) ...[
                    TextFormField(
                      controller: _timeLimitController,
                      decoration: InputDecoration(
                        labelText: context.tr("Time limit in seconds"),
                      ),
                      keyboardType: TextInputType.number,
                      validator: _positiveInt(
                        context.tr("Enter a positive time limit."),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.tr("Weiches Zeitlimit")),
                      subtitle: Text(
                        context.tr(
                          "Hart: Nach Ablauf sind keine Antworten mehr möglich. Weich: Die Zeit dient als Orientierung; erst der Spielleiter beendet die Runde.",
                        ),
                      ),
                      value: _softTimeLimit,
                      onChanged: (value) =>
                          setState(() => _softTimeLimit = value),
                    ),
                  ],
                ],
              ),
            ),
            switch (widget.question) {
              final LocationQuestion location => LocationQuestionFields(
                question: location,
                onChanged: (fields) => _contentFields = fields,
              ),
              MultipleChoiceQuestion() => _multipleChoicePanel(),
              BuzzerQuestion() => _buzzerPanel(),
              ShortAnswerQuestion() ||
              OrderingQuestion() ||
              MatchingQuestion() ||
              EstimationQuestion() ||
              TrueFalseQuestion() => NewQuestionFields(
                question: widget.question,
                showSolution: !widget.hidesSolution,
                onChanged: (fields) => _contentFields = fields,
              ),
            },
            if (widget.usesQuestionPoints) _scoringPanel(),
            HintsEditor(
              hints: _hints,
              onChanged: (hints) => _hints = hints,
              costsPoints: widget.hintsCostPoints,
            ),
            MediaEditor(
              media: _media,
              onChanged: (media) => _media = media,
              title: context.tr("Fragemedien"),
            ),
            MediaEditor(
              media: _solutionMedia,
              onChanged: (media) => _solutionMedia = media,
              title: context.tr("Lösungsmedien (erst bei Auflösung)"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _multipleChoicePanel() => PanelCard(
    title: context.tr("Answer options"),
    icon: Icons.format_list_bulleted,
    trailing: IconButton(
      tooltip: context.tr("Add option"),
      onPressed: _addOption,
      icon: const Icon(Icons.add),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_options.isEmpty)
          EmptyHint(
            context.tr("Add at least two options and choose the correct one."),
          ),
        for (var index = 0; index < _options.length; index++)
          _OptionField(
            key: ValueKey(_options[index].id),
            index: index,
            option: _options[index],
            onChanged: (label) => setState(() => _options[index].label = label),
            onRemove: _options.length <= 2 ? null : () => _removeOption(index),
          ),
        const SizedBox(height: 8),
        if (widget.hidesSolution)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.tr(kNoSolutionHint)),
          ),
        SwitchListTile(
          title: Text(
            widget.hidesSolution
                ? context.tr("Mehrere Antworten wählbar")
                : context.tr("Mehrere richtige Antworten"),
          ),
          value: _allowMultipleAnswers,
          onChanged: (value) => setState(() {
            _allowMultipleAnswers = value;
            if (!value) _correctOptionId = _correctOptionIds.firstOrNull;
            if (value &&
                _correctOptionIds.isEmpty &&
                _correctOptionId != null) {
              _correctOptionIds = [_correctOptionId!];
            }
          }),
        ),
        if (_allowMultipleAnswers && !widget.hidesSolution)
          FormField<List<String>>(
            validator: (_) => _correctOptionIds.isEmpty
                ? context.tr("Mindestens eine richtige Antwort wÃ¤hlen.")
                : null,
            builder: (field) => Column(
              children: [
                for (final option in _options)
                  CheckboxListTile(
                    title: Text(option.label),
                    value: _correctOptionIds.contains(option.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _correctOptionIds.add(option.id);
                      } else {
                        _correctOptionIds.remove(option.id);
                      }
                      field.didChange([..._correctOptionIds]);
                    }),
                  ),
                if (field.errorText != null)
                  Text(
                    field.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        if (!_allowMultipleAnswers && !widget.hidesSolution)
          DropdownButtonFormField<String>(
            initialValue:
                _options.any((option) => option.id == _correctOptionId)
                ? _correctOptionId
                : null,
            decoration: InputDecoration(
              labelText: context.tr("Correct option"),
            ),
            items: [
              for (final option in _options)
                DropdownMenuItem(value: option.id, child: Text(option.label)),
            ],
            onChanged: (value) => setState(() {
              _correctOptionId = value;
              _correctOptionIds = [?value];
            }),
            validator: (value) => value == null
                ? context.tr("Choose an option as the correct answer.")
                : null,
          ),
      ],
    ),
  );

  Widget _buzzerPanel() => PanelCard(
    title: context.tr("Buzzer answer"),
    icon: Icons.record_voice_over_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _expectedAnswerController,
          decoration: InputDecoration(
            labelText: context.tr("Expected answer (optional)"),
          ),
          minLines: 2,
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _lockOutOnMiss,
          onChanged: (value) => setState(() => _lockOutOnMiss = value),
          title: Text(context.tr("Lock out a player after a wrong answer")),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _hostEndsRound,
          onChanged: (value) => setState(() => _hostEndsRound = value),
          title: Text(context.tr("Nur durch Spielleiter beenden")),
          subtitle: Text(
            context.tr(
              "Die Frage bleibt bis zum manuellen Beenden offen, auch nach einer richtigen Antwort.",
            ),
          ),
        ),
        TextFormField(
          controller: _retryLimitController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.tr("Empfohlene Wiederholungen (optional)"),
            helperText: context.tr(
              "Leer: unbegrenzt. 0: keine Wiederholung. Der Spielleiter darf trotzdem fortsetzen.",
            ),
            helperMaxLines: 3,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final count = int.tryParse(value.trim());
            return count == null || count < 0
                ? context.tr("Bitte eine ganze Zahl ab 0 eingeben.")
                : null;
          },
        ),
      ],
    ),
  );

  Widget _scoringPanel() => PanelCard(
    title: context.tr("Scoring rule"),
    icon: Icons.stars_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<_ScoringRuleKind>(
          initialValue: _scoringKind,
          decoration: InputDecoration(labelText: context.tr("Rule")),
          items: [
            DropdownMenuItem(
              value: _ScoringRuleKind.fixed,
              child: Text(context.tr("Fixed points")),
            ),
            DropdownMenuItem(
              value: _ScoringRuleKind.speedBonus,
              child: Text(context.tr("Speed bonus")),
            ),
            DropdownMenuItem(
              value: _ScoringRuleKind.firstBuzzer,
              child: Text(context.tr("First buzzer")),
            ),
          ],
          onChanged: (value) => setState(() => _scoringKind = value!),
        ),
        const SizedBox(height: 12),
        ...switch (_scoringKind) {
          _ScoringRuleKind.fixed => [
            _pointField(_primaryPointsController, context.tr("Correct points")),
            const SizedBox(height: 12),
            _pointField(
              _secondaryPointsController,
              context.tr("Wrong-answer points"),
            ),
          ],
          _ScoringRuleKind.speedBonus => [
            _pointField(_primaryPointsController, context.tr("Base points")),
            const SizedBox(height: 12),
            _pointField(
              _secondaryPointsController,
              context.tr("Maximum speed bonus"),
            ),
            const SizedBox(height: 12),
            _pointField(
              _tertiaryPointsController,
              context.tr("Wrong-answer points"),
            ),
          ],
          _ScoringRuleKind.firstBuzzer => [
            _pointField(
              _primaryPointsController,
              context.tr("First-buzzer points"),
            ),
            const SizedBox(height: 12),
            _pointField(
              _secondaryPointsController,
              context.tr("Wrong-answer penalty"),
            ),
            const SizedBox(height: 12),
            _pointField(
              _tertiaryPointsController,
              context.tr("Points lost per rank"),
            ),
          ],
        },
      ],
    ),
  );

  Widget _pointField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        validator: _integer(context.tr("Enter a whole number.")),
      );

  void _addOption() {
    var number = _options.length + 1;
    while (_options.any((option) => option.id == 'option-$number')) {
      number++;
    }
    final id = 'option-$number';
    setState(() {
      _options = [
        ..._options,
        _OptionDraft(id, context.tr("Option {0}", [_options.length + 1])),
      ];
      _correctOptionId ??= id;
    });
  }

  void _removeOption(int index) {
    final removed = _options[index];
    setState(() {
      _options = [..._options]..removeAt(index);
      _correctOptionIds.remove(removed.id);
      if (_correctOptionId == removed.id) {
        _correctOptionId = _options.isEmpty ? null : _options.first.id;
      }
    });
  }

  void _save() {
    try {
      _saveValid();
    } on Object catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr("Bitte Eingaben prüfen: {0}", [context.tr('$error')]),
          ),
        ),
      );
    }
  }

  /// The question as entered so far, without checking it: what a kind
  /// change takes over. Unreadable numbers keep their former value.
  Question _draft() {
    T attempt<T>(T Function() read, T fallback) {
      try {
        return read();
      } on Object {
        return fallback;
      }
    }

    return attempt(
      () => _buildQuestion(
        timeLimit: attempt(_timeLimit, widget.question.timeLimit),
        rule: widget.usesQuestionPoints
            ? attempt(_buildScoringRule, widget.question.scoringRule)
            : widget.question.scoringRule,
      ),
      () {
        // Kind specific input that does not parse yet stays as it was.
        _contentFields = {};
        return _buildQuestion(
          timeLimit: attempt(_timeLimit, widget.question.timeLimit),
          rule: widget.question.scoringRule,
        );
      }(),
    );
  }

  Duration _timeLimit() => _hasTimeLimit
      ? Duration(seconds: int.parse(_timeLimitController.text))
      : Duration.zero;

  void _saveValid() {
    if (!_formKey.currentState!.validate()) return;
    final question = _buildQuestion(
      timeLimit: _timeLimit(),
      rule: widget.usesQuestionPoints
          ? _buildScoringRule()
          : widget.question.scoringRule,
    );
    final errors = [
      ...question.structureErrors,
      if (!widget.hidesSolution) ...question.solutionErrors,
      for (final m in [..._media, ..._solutionMedia]) ...m.validationErrors,
      for (final hint in _hints) ...hint.validationErrors,
    ];
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.map(context.tr).join(' '))));
      return;
    }
    Navigator.of(context).pop(question);
  }

  Question _buildQuestion({
    required Duration timeLimit,
    required ScoringRule rule,
  }) {
    var question = switch (widget.question) {
      MultipleChoiceQuestion(:final id) => MultipleChoiceQuestion(
        id: id,
        prompt: _promptController.text.trim(),
        category: _nullableText(_categoryController.text),
        timeLimit: timeLimit,
        scoringRule: rule,
        options: [
          for (final option in _options)
            AnswerOption(id: option.id, label: option.label.trim()),
        ],
        correctOptionId: _allowMultipleAnswers ? null : _correctOptionId,
        correctOptionIds: _allowMultipleAnswers ? [..._correctOptionIds] : null,
        allowMultipleAnswers: _allowMultipleAnswers,
      ),
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      LocationQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => Question.fromJson({
        ...widget.question.toJson(),
        ..._contentFields,
        'prompt': _promptController.text.trim(),
        'category': _nullableText(_categoryController.text),
        'timeLimitMs': timeLimit.inMilliseconds,
        'scoringRule': rule.toJson(),
      }),
      BuzzerQuestion(:final id) => BuzzerQuestion(
        id: id,
        prompt: _promptController.text.trim(),
        category: _nullableText(_categoryController.text),
        timeLimit: timeLimit,
        scoringRule: rule,
        expectedAnswer: _nullableText(_expectedAnswerController.text),
        lockOutOnMiss: _lockOutOnMiss,
        hostEndsRound: _hostEndsRound,
        retryLimit: int.tryParse(_retryLimitController.text.trim()),
      ),
    };
    question = Question.fromJson({
      ...question.toJson(),
      'softTimeLimit': _hasTimeLimit && _softTimeLimit,
      'media': _media.map((m) => m.toJson()).toList(),
      'solutionMedia': _solutionMedia.map((m) => m.toJson()).toList(),
      'adminNotes': _notesController.text,
      'hints': _hints.map((hint) => hint.toJson()).toList(),
    });
    if (widget.hidesSolution) question = question.withoutSolution();
    return question;
  }

  ScoringRule _buildScoringRule() => switch (_scoringKind) {
    _ScoringRuleKind.fixed => FixedPointsRule(
      correctPoints: int.parse(_primaryPointsController.text),
      wrongPoints: int.parse(_secondaryPointsController.text),
    ),
    _ScoringRuleKind.speedBonus => SpeedBonusRule(
      basePoints: int.parse(_primaryPointsController.text),
      maxSpeedBonus: int.parse(_secondaryPointsController.text),
      wrongPoints: int.parse(_tertiaryPointsController.text),
    ),
    _ScoringRuleKind.firstBuzzer => FirstBuzzerRule(
      points: int.parse(_primaryPointsController.text),
      penalty: int.parse(_secondaryPointsController.text),
      rankDecay: int.parse(_tertiaryPointsController.text),
    ),
  };

  FormFieldValidator<String> _positiveInt(String message) => (value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed <= 0 ? message : null;
  };

  FormFieldValidator<String> _integer(String message) =>
      (value) => int.tryParse(value ?? '') == null ? message : null;

  String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _OptionField extends StatelessWidget {
  const _OptionField({
    required this.index,
    required this.option,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _OptionDraft option;
  final ValueChanged<String> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text('${index + 1}.', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: option.label,
            decoration: InputDecoration(
              labelText: context.tr("Option {0}", [index + 1]),
            ),
            onChanged: onChanged,
            validator: (value) => value == null || value.trim().isEmpty
                ? context.tr("Enter an option label.")
                : null,
          ),
        ),
        IconButton(
          tooltip: context.tr("Remove option"),
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ],
    ),
  );
}

final class _OptionDraft {
  _OptionDraft(this.id, this.label);

  final String id;
  String label;
}
