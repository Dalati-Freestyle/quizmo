/// Editor for one polymorphic quiz question.
library;

import 'package:flutter/material.dart';

import '../../../core/engine/scoring_rules.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';

enum _ScoringRuleKind { fixed, speedBonus, firstBuzzer }

/// Edits [question] and returns a replacement when the host saves it.
class QuestionEditorPage extends StatefulWidget {
  /// Creates an editor for [question].
  const QuestionEditorPage({required this.question, super.key});

  /// Question variant being edited.
  final Question question;

  @override
  State<QuestionEditorPage> createState() => _QuestionEditorPageState();
}

class _QuestionEditorPageState extends State<QuestionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _promptController;
  late final TextEditingController _categoryController;
  late final TextEditingController _timeLimitController;
  late final TextEditingController _expectedAnswerController;
  late final TextEditingController _primaryPointsController;
  late final TextEditingController _secondaryPointsController;
  late final TextEditingController _tertiaryPointsController;
  late List<_OptionDraft> _options;
  late String? _correctOptionId;
  late bool _lockOutOnMiss;
  late _ScoringRuleKind _scoringKind;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    _promptController = TextEditingController(text: question.prompt);
    _categoryController = TextEditingController(text: question.category ?? '');
    _timeLimitController = TextEditingController(
      text: question.timeLimit.inSeconds.toString(),
    );
    _expectedAnswerController = TextEditingController(
      text: switch (question) {
        MultipleChoiceQuestion() => '',
        BuzzerQuestion(:final expectedAnswer) => expectedAnswer ?? '',
      },
    );
    _options = switch (question) {
      MultipleChoiceQuestion(:final options) => [
        for (final option in options) _OptionDraft(option.id, option.label),
      ],
      BuzzerQuestion() => [],
    };
    _correctOptionId = switch (question) {
      MultipleChoiceQuestion(:final correctOptionId) => correctOptionId,
      BuzzerQuestion() => null,
    };
    _lockOutOnMiss = switch (question) {
      MultipleChoiceQuestion() => true,
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
      BuzzerQuestion() => false,
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
            },
            _scoringPanel(),
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
        DropdownButtonFormField<String>(
          initialValue: _options.any((option) => option.id == _correctOptionId)
              ? _correctOptionId
              : null,
          decoration: const InputDecoration(labelText: 'Correct option'),
          items: [
            for (final option in _options)
              DropdownMenuItem(value: option.id, child: Text(option.label)),
          ],
          onChanged: (value) => setState(() => _correctOptionId = value),
          validator: (value) =>
              value == null ? 'Choose an option as the correct answer.' : null,
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
    final id = 'option-${_options.length + 1}';
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
      if (_correctOptionId == removed.id) {
        _correctOptionId = _options.isEmpty ? null : _options.first.id;
      }
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final timeLimit = Duration(seconds: int.parse(_timeLimitController.text));
    final rule = _buildScoringRule();
    final question = switch (widget.question) {
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
        correctOptionId: _correctOptionId,
      ),
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
