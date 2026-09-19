/// Responsive editor for one reusable quiz.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/data/quiz_repository.dart';
import '../../../core/engine/scoring_rules.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import 'question_editor.dart';
import 'quiz_editor_cubit.dart';

/// Lets the host edit [quiz] and returns its saved replacement.
class QuizEditorPage extends StatelessWidget {
  /// Creates an editor with [repository] and stable identifiers from [createId].
  const QuizEditorPage({
    required this.repository,
    required this.quiz,
    required this.createId,
    super.key,
  });

  /// Persistent local library receiving the saved quiz.
  final QuizRepository repository;

  /// Quiz definition opened by the editor.
  final Quiz quiz;

  /// Generates collision-resistant IDs for new teams and questions.
  final String Function() createId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => QuizEditorCubit(repository: repository, quiz: quiz),
    child: _QuizEditorView(createId: createId),
  );
}

class _QuizEditorView extends StatefulWidget {
  const _QuizEditorView({required this.createId});

  final String Function() createId;

  @override
  State<_QuizEditorView> createState() => _QuizEditorViewState();
}

class _QuizEditorViewState extends State<_QuizEditorView> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    final quiz = context.read<QuizEditorCubit>().state.draft;
    _nameController = TextEditingController(text: quiz.name);
    _descriptionController = TextEditingController(text: quiz.description);
    _categoryController = TextEditingController(text: quiz.category);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<QuizEditorCubit, QuizEditorState>(
    builder: (context, state) {
      final cubit = context.read<QuizEditorCubit>();
      return Scaffold(
        appBar: AppBar(
          title: Text('Edit ${state.draft.name}'),
          actions: [
            TextButton.icon(
              onPressed: state.isSaving ? null : _saveQuiz,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save quiz'),
            ),
          ],
        ),
        body: AdaptivePanelGrid(
          panels: [
            PanelCard(
              title: 'Quiz details',
              icon: Icons.edit_note_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (_) => _updateMetadata(cubit),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => _updateMetadata(cubit),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                    onChanged: (_) => _updateMetadata(cubit),
                  ),
                ],
              ),
            ),
            _TeamsPanel(
              teams: state.draft.teams,
              onAdd: () => _editTeam(cubit),
              onEdit: (team) => _editTeam(cubit, team),
              onRemove: cubit.removeTeam,
            ),
            _QuestionsPanel(
              questions: state.draft.questions,
              onAddMultipleChoice: () => _editQuestion(
                cubit,
                MultipleChoiceQuestion(
                  id: widget.createId(),
                  prompt: '',
                  options: const [
                    AnswerOption(id: 'option-a', label: 'Option A'),
                    AnswerOption(id: 'option-b', label: 'Option B'),
                  ],
                  correctOptionId: 'option-a',
                  scoringRule: const SpeedBonusRule(),
                ),
                isNew: true,
              ),
              onAddBuzzer: () => _editQuestion(
                cubit,
                BuzzerQuestion(
                  id: widget.createId(),
                  prompt: '',
                  scoringRule: const FirstBuzzerRule(),
                ),
                isNew: true,
              ),
              onEdit: (question) => _editQuestion(cubit, question),
              onRemove: cubit.removeQuestion,
              onReorder: cubit.reorderQuestions,
            ),
            if (state.error case final error?)
              PanelCard(
                title: 'Cannot save quiz',
                icon: Icons.error_outline,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      );
    },
  );

  void _updateMetadata(QuizEditorCubit cubit) => cubit.updateMetadata(
    name: _nameController.text,
    description: _descriptionController.text,
    category: _categoryController.text,
  );

  Future<void> _saveQuiz() async {
    final savedQuiz = await context.read<QuizEditorCubit>().save();
    if (!mounted || savedQuiz == null) return;
    Navigator.of(context).pop(savedQuiz);
  }

  Future<void> _editQuestion(
    QuizEditorCubit cubit,
    Question question, {
    bool isNew = false,
  }) async {
    final edited = await Navigator.of(context).push<Question>(
      MaterialPageRoute<Question>(
        builder: (_) => QuestionEditorPage(question: question),
      ),
    );
    if (edited == null || !mounted) return;
    if (isNew) {
      cubit.addQuestion(edited);
    } else {
      cubit.updateQuestion(edited);
    }
  }

  Future<void> _editTeam(QuizEditorCubit cubit, [Team? team]) async {
    final edited = await showDialog<Team>(
      context: context,
      builder: (_) => _TeamDialog(team: team, newId: widget.createId),
    );
    if (edited == null || !mounted) return;
    if (team == null) {
      cubit.addTeam(edited);
    } else {
      cubit.updateTeam(edited);
    }
  }
}

class _TeamsPanel extends StatelessWidget {
  const _TeamsPanel({
    required this.teams,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<Team> teams;
  final VoidCallback onAdd;
  final ValueChanged<Team> onEdit;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => PanelCard(
    title: 'Teams (optional)',
    icon: Icons.groups_outlined,
    trailing: IconButton(
      tooltip: 'Add team',
      onPressed: onAdd,
      icon: const Icon(Icons.add),
    ),
    child: teams.isEmpty
        ? const EmptyHint('No teams: this quiz will start in solo mode.')
        : Column(
            children: [
              for (final team in teams)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Color(team.colorValue),
                  ),
                  title: Text(team.name),
                  subtitle: Text(team.id),
                  onTap: () => onEdit(team),
                  trailing: IconButton(
                    tooltip: 'Remove ${team.name}',
                    onPressed: () => onRemove(team.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          ),
  );
}

class _QuestionsPanel extends StatelessWidget {
  const _QuestionsPanel({
    required this.questions,
    required this.onAddMultipleChoice,
    required this.onAddBuzzer,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  final List<Question> questions;
  final VoidCallback onAddMultipleChoice;
  final VoidCallback onAddBuzzer;
  final ValueChanged<Question> onEdit;
  final ValueChanged<String> onRemove;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) => PanelCard(
    title: 'Questions',
    icon: Icons.quiz_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onAddMultipleChoice,
              icon: const Icon(Icons.add),
              label: const Text('Add multiple-choice question'),
            ),
            OutlinedButton.icon(
              onPressed: onAddBuzzer,
              icon: const Icon(Icons.add),
              label: const Text('Add buzzer question'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (questions.isEmpty)
          const EmptyHint('Add questions before hosting this quiz.')
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: questions.length,
            onReorderItem: onReorder,
            itemBuilder: (context, index) {
              final question = questions[index];
              return ListTile(
                key: ValueKey(question.id),
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (question) {
                  MultipleChoiceQuestion() => Icons.checklist,
                  BuzzerQuestion() => Icons.bolt,
                }),
                title: Text(
                  question.prompt.isEmpty
                      ? 'Untitled question'
                      : question.prompt,
                ),
                subtitle: Text(
                  '${question.kindLabel} · ${question.timeLimit.inSeconds}s · '
                  '${question.scoringRule.label}',
                ),
                onTap: () => onEdit(question),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.drag_handle),
                    IconButton(
                      tooltip: 'Delete question',
                      onPressed: () => onRemove(question.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    ),
  );
}

class _TeamDialog extends StatefulWidget {
  const _TeamDialog({required this.team, required this.newId});

  final Team? team;
  final String Function() newId;

  @override
  State<_TeamDialog> createState() => _TeamDialogState();
}

class _TeamDialogState extends State<_TeamDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _colorController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.team?.name ?? '');
    _colorController = TextEditingController(
      text: (widget.team?.colorValue ?? 0xFF5E6AD2)
          .toRadixString(16)
          .padLeft(8, '0'),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.team == null ? 'Add team' : 'Edit team'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Team name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a team name.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _colorController,
            decoration: const InputDecoration(
              labelText: 'ARGB colour (for example FF5E6AD2)',
            ),
            validator: (value) => _parseColor(value) == null
                ? 'Enter an 8-digit hexadecimal ARGB colour.'
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save team')),
    ],
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      Team(
        id: widget.team?.id ?? widget.newId(),
        name: _nameController.text.trim(),
        colorValue: _parseColor(_colorController.text)!,
      ),
    );
  }

  int? _parseColor(String? value) =>
      int.tryParse(value?.trim().replaceFirst('#', '') ?? '', radix: 16);
}
