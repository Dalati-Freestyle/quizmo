/// Editor for one polymorphic quiz question.
library;

import 'package:flutter/material.dart';

import '../../../core/engine/scoring_rules.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import 'new_question_fields.dart';
import 'media_editor.dart';
import 'selection_dropdown.dart';

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
final List<QuestionTemplate> kQuestionTemplates = [
  QuestionTemplate(
    label: 'Freitext',
    icon: Icons.text_fields,
    create: (id) => ShortAnswerQuestion(
      id: id,
      prompt: '',
      acceptedAnswers: const ['Antwort'],
    ),
  ),
  QuestionTemplate(
    label: 'Reihenfolge',
    icon: Icons.sort,
    create: (id) => OrderingQuestion(
      id: id,
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
    create: (id) => EstimationQuestion(id: id, prompt: '', correctValue: 100),
  ),
  QuestionTemplate(
    label: 'Wahr / Falsch',
    icon: Icons.rule,
    create: (id) => TrueFalseQuestion(id: id, prompt: '', correctAnswer: true),
  ),
  QuestionTemplate(
    label: 'Multiple choice',
    icon: Icons.checklist,
    create: (id) => MultipleChoiceQuestion(
      id: id,
      prompt: '',
      options: const [
        AnswerOption(id: 'option-a', label: 'Option A'),
        AnswerOption(id: 'option-b', label: 'Option B'),
      ],
      correctOptionId: 'option-a',
      scoringRule: const SpeedBonusRule(),
    ),
  ),
  QuestionTemplate(
    label: 'Fast buzzer',
    icon: Icons.bolt,
    create: (id) => BuzzerQuestion(
      id: id,
      prompt: '',
      scoringRule: const FirstBuzzerRule(),
    ),
  ),
];

/// Selects a question kind from the templates shared by every quiz format.
class QuestionTemplateDropdown extends StatelessWidget {
  /// Creates a selector for [value] that reports changes to [onChanged].
  const QuestionTemplateDropdown({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The selected template, or `null` before a kind is chosen.
  final QuestionTemplate? value;

  /// Receives the selected template.
  final ValueChanged<QuestionTemplate?> onChanged;

  @override
  Widget build(BuildContext context) => SelectionDropdown<QuestionTemplate>(
    label: 'Fragenart',
    value: value,
    items: [
      for (final template in kQuestionTemplates)
        DropdownMenuItem(
          value: template,
          child: Row(
            children: [
              Icon(template.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(template.label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
    ],
    onChanged: onChanged,
  );
}

/// Edits [question] and returns a replacement when the host saves it.
class QuestionEditorPage extends StatefulWidget {
  /// Creates an editor for [question].
  ///
  /// With [usesBoardPoints] the scoring rule is neither shown nor changed: the
  /// question sits on a Jeopardy board, where the row decides the points.
  const QuestionEditorPage({
    required this.question,
    this.usesBoardPoints = false,
    super.key,
  });

  /// Question variant being edited.
  final Question question;

  /// Whether the points come from a Jeopardy row instead of the question.
  final bool usesBoardPoints;

  @override
  State<QuestionEditorPage> createState() => _QuestionEditorPageState();
}

class _QuestionEditorPageState extends State<QuestionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  Map<String, Object?> _contentFields = {};
  late List<MediaAttachment> _media;
  late List<MediaAttachment> _solutionMedia;
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
  late _ScoringRuleKind _scoringKind;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    _notesController = TextEditingController(text: question.adminNotes);
    _media = question.media;
    _solutionMedia = question.solutionMedia;
    _promptController = TextEditingController(text: question.prompt);
    _categoryController = TextEditingController(text: question.category ?? '');
    _timeLimitController = TextEditingController(
      text: question.timeLimit.inSeconds.toString(),
    );
    _expectedAnswerController = TextEditingController(
      text: switch (question) {
        MultipleChoiceQuestion() ||
        ShortAnswerQuestion() ||
        OrderingQuestion() ||
        MatchingQuestion() ||
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
      EstimationQuestion() ||
      TrueFalseQuestion() => [],
    };
    _correctOptionId = switch (question) {
      MultipleChoiceQuestion(:final correctOptionId) => correctOptionId,
      BuzzerQuestion() ||
      ShortAnswerQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
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
      EstimationQuestion() ||
      TrueFalseQuestion() => false,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.question.kindLabel} question'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save question'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: AdaptivePanelGrid(
          panels: [
            PanelCard(
              title: 'Question',
              icon: isMultipleChoice ? Icons.checklist : Icons.bolt,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _promptController,
                    decoration: const InputDecoration(labelText: 'Prompt'),
                    minLines: 2,
                    maxLines: 4,
                    validator: _requiredText('Enter a question prompt.'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Admin-Notizen (nur Spielleiter)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Question category (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _timeLimitController,
                    decoration: const InputDecoration(
                      labelText: 'Time limit in seconds',
                    ),
                    keyboardType: TextInputType.number,
                    validator: _positiveInt('Enter a positive time limit.'),
                  ),
                ],
              ),
            ),
            switch (widget.question) {
              MultipleChoiceQuestion() => _multipleChoicePanel(),
              BuzzerQuestion() => _buzzerPanel(),
              ShortAnswerQuestion() ||
              OrderingQuestion() ||
              MatchingQuestion() ||
              EstimationQuestion() ||
              TrueFalseQuestion() => NewQuestionFields(
                question: widget.question,
                onChanged: (fields) => _contentFields = fields,
              ),
            },
            if (!widget.usesBoardPoints) _scoringPanel(),
            MediaEditor(
              media: _media,
              onChanged: (media) => _media = media,
              title: 'Fragemedien',
            ),
            MediaEditor(
              media: _solutionMedia,
              onChanged: (media) => _solutionMedia = media,
              title: 'Lösungsmedien (erst bei Auflösung)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _multipleChoicePanel() => PanelCard(
    title: 'Answer options',
    icon: Icons.format_list_bulleted,
    trailing: IconButton(
      tooltip: 'Add option',
      onPressed: _addOption,
      icon: const Icon(Icons.add),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_options.isEmpty)
          const EmptyHint(
            'Add at least two options and choose the correct one.',
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
        SwitchListTile(
          title: const Text('Mehrere richtige Antworten'),
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
        if (_allowMultipleAnswers)
          FormField<List<String>>(
            validator: (_) => _correctOptionIds.isEmpty
                ? 'Mindestens eine richtige Antwort wÃ¤hlen.'
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
        if (!_allowMultipleAnswers)
          DropdownButtonFormField<String>(
            initialValue:
                _options.any((option) => option.id == _correctOptionId)
                ? _correctOptionId
                : null,
            decoration: const InputDecoration(labelText: 'Correct option'),
            items: [
              for (final option in _options)
                DropdownMenuItem(value: option.id, child: Text(option.label)),
            ],
            onChanged: (value) => setState(() {
              _correctOptionId = value;
              _correctOptionIds = [?value];
            }),
            validator: (value) => value == null
                ? 'Choose an option as the correct answer.'
                : null,
          ),
      ],
    ),
  );

  Widget _buzzerPanel() => PanelCard(
    title: 'Buzzer answer',
    icon: Icons.record_voice_over_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _expectedAnswerController,
          decoration: const InputDecoration(
            labelText: 'Expected answer (optional)',
          ),
          minLines: 2,
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _lockOutOnMiss,
          onChanged: (value) => setState(() => _lockOutOnMiss = value),
          title: const Text('Lock out a player after a wrong answer'),
        ),
      ],
    ),
  );

  Widget _scoringPanel() => PanelCard(
    title: 'Scoring rule',
    icon: Icons.stars_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<_ScoringRuleKind>(
          initialValue: _scoringKind,
          decoration: const InputDecoration(labelText: 'Rule'),
          items: const [
            DropdownMenuItem(
              value: _ScoringRuleKind.fixed,
              child: Text('Fixed points'),
            ),
            DropdownMenuItem(
              value: _ScoringRuleKind.speedBonus,
              child: Text('Speed bonus'),
            ),
            DropdownMenuItem(
              value: _ScoringRuleKind.firstBuzzer,
              child: Text('First buzzer'),
            ),
          ],
          onChanged: (value) => setState(() => _scoringKind = value!),
        ),
        const SizedBox(height: 12),
        ...switch (_scoringKind) {
          _ScoringRuleKind.fixed => [
            _pointField(_primaryPointsController, 'Correct points'),
            const SizedBox(height: 12),
            _pointField(_secondaryPointsController, 'Wrong-answer points'),
          ],
          _ScoringRuleKind.speedBonus => [
            _pointField(_primaryPointsController, 'Base points'),
            const SizedBox(height: 12),
            _pointField(_secondaryPointsController, 'Maximum speed bonus'),
            const SizedBox(height: 12),
            _pointField(_tertiaryPointsController, 'Wrong-answer points'),
          ],
          _ScoringRuleKind.firstBuzzer => [
            _pointField(_primaryPointsController, 'First-buzzer points'),
            const SizedBox(height: 12),
            _pointField(_secondaryPointsController, 'Wrong-answer penalty'),
            const SizedBox(height: 12),
            _pointField(_tertiaryPointsController, 'Points lost per rank'),
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
        validator: _integer('Enter a whole number.'),
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
        _OptionDraft(id, 'Option ${_options.length + 1}'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bitte Eingaben prüfen: $error')));
    }
  }

  void _saveValid() {
    if (!_formKey.currentState!.validate()) return;
    final timeLimit = Duration(seconds: int.parse(_timeLimitController.text));
    final rule = widget.usesBoardPoints
        ? widget.question.scoringRule
        : _buildScoringRule();
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
      ),
    };
    question = Question.fromJson({
      ...question.toJson(),
      'media': _media.map((m) => m.toJson()).toList(),
      'solutionMedia': _solutionMedia.map((m) => m.toJson()).toList(),
      'adminNotes': _notesController.text,
    });
    final errors = [
      ...question.contentErrors,
      for (final m in [..._media, ..._solutionMedia]) ...m.validationErrors,
    ];
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errors.join(' '))));
      return;
    }
    Navigator.of(context).pop(question);
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

  FormFieldValidator<String> _requiredText(String message) =>
      (value) => value == null || value.trim().isEmpty ? message : null;

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
            decoration: InputDecoration(labelText: 'Option ${index + 1}'),
            onChanged: onChanged,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter an option label.'
                : null,
          ),
        ),
        IconButton(
          tooltip: 'Remove option',
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
