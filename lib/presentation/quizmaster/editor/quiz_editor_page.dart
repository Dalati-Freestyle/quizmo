/// Responsive editor for one reusable quiz.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/settings_page.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/data/quiz_repository.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import 'jeopardy_board_editor.dart';
import 'question_editor.dart';
import 'quiz_editor_cubit.dart';
import 'selection_dropdown.dart';

enum _QuizFormatKind { standard, jeopardy, poker }

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
      final formatKind = switch (state.draft.format) {
        StandardFormat() => _QuizFormatKind.standard,
        JeopardyFormat() => _QuizFormatKind.jeopardy,
        PokerFormat() => _QuizFormatKind.poker,
      };
      return Scaffold(
        appBar: AppBar(
          title: Text(context.tr("Edit {0}", [state.draft.name])),
          actions: [
            const SettingsButton(),
            TextButton.icon(
              onPressed: state.isSaving ? null : _saveQuiz,
              icon: const Icon(Icons.save_outlined),
              label: Text(context.tr("Save quiz")),
            ),
          ],
        ),
        body: AdaptivePanelGrid(
          panels: [
            PanelCard(
              title: context.tr("Quiz details"),
              icon: Icons.edit_note_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: context.tr("Name")),
                    onChanged: (_) => _updateMetadata(cubit),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: context.tr("Description"),
                    ),
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => _updateMetadata(cubit),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _categoryController,
                    decoration: InputDecoration(
                      labelText: context.tr("Category"),
                    ),
                    onChanged: (_) => _updateMetadata(cubit),
                  ),
                  const SizedBox(height: 16),
                  SelectionDropdown<_QuizFormatKind>(
                    label: context.tr("Quiz type"),
                    value: formatKind,
                    items: [
                      DropdownMenuItem(
                        value: _QuizFormatKind.standard,
                        child: Row(
                          children: [
                            Icon(Icons.list_alt),
                            SizedBox(width: 8),
                            Text(context.tr("Standard")),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: _QuizFormatKind.jeopardy,
                        child: Row(
                          children: [
                            Icon(Icons.grid_view),
                            SizedBox(width: 8),
                            Text(context.tr("Jeopardy")),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: _QuizFormatKind.poker,
                        child: Row(
                          children: [
                            Icon(Icons.casino_outlined),
                            SizedBox(width: 8),
                            Text(context.tr("Pokerchips")),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (selection) {
                      if (selection == null || selection == formatKind) return;
                      switch (selection) {
                        case _QuizFormatKind.standard:
                          cubit.useStandardFormat();
                        case _QuizFormatKind.jeopardy:
                          cubit.useJeopardyFormat();
                        case _QuizFormatKind.poker:
                          cubit.usePokerFormat();
                      }
                    },
                  ),
                  if (state.draft.format case StandardFormat(
                    :final revealMode,
                  )) ...[
                    const SizedBox(height: 16),
                    SelectionDropdown<SolutionRevealMode>(
                      label: context.tr('Auflösung'),
                      value: revealMode,
                      items: [
                        DropdownMenuItem(
                          value: SolutionRevealMode.afterEachQuestion,
                          child: Text(context.tr('Nach jeder Frage')),
                        ),
                        DropdownMenuItem(
                          value: SolutionRevealMode.atEnd,
                          child: Text(context.tr('Am Quizende')),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          cubit.useStandardFormat(revealMode: mode);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Am Quizende: Lösungen, Bewertungen und Punktestände bleiben für Spieler und TV bis zum Schluss verborgen. Der Spielleiter sieht sie weiterhin.',
                      ),
                    ),
                  ],
                  if (state.draft.format case PokerFormat(
                    :final startingChips,
                  )) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: '$startingChips',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          "Startchips pro Team (1–1000000)",
                        ),
                      ),
                      onChanged: (value) => cubit.usePokerFormat(
                        startingChips: int.tryParse(value) ?? 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        "Jedes Team setzt pro Frage. Richtig: doppelter Einsatz zurück. Falsch oder keine Antwort: Einsatz verloren. 0 Chips = aussetzen. Mindestens ein Team anlegen.",
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _TeamsPanel(
              teams: state.draft.teams,
              onAdd: () => _editTeam(cubit),
              onEdit: (team) => _editTeam(cubit, team),
              onRemove: cubit.removeTeam,
            ),
            switch (state.draft.format) {
              JeopardyFormat(:final board) => JeopardyBoardEditorPanel(
                quiz: state.draft,
                board: board,
                cubit: cubit,
                createId: widget.createId,
              ),
              StandardFormat() || PokerFormat() => _QuestionsPanel(
                questions: state.draft.questions,
                format: state.draft.format,
                onAddTemplate: (template) => _editQuestion(
                  cubit,
                  template.create(widget.createId()),
                  isNew: true,
                ),
                onEdit: (question) => _editQuestion(cubit, question),
                onRemove: cubit.removeQuestion,
                onReorder: cubit.reorderQuestions,
              ),
            },
            if (state.error case final error?)
              PanelCard(
                title: context.tr("Cannot save quiz"),
                icon: Icons.error_outline,
                child: Text(
                  context.tr(error),
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
        builder: (_) => QuestionEditorPage(
          question: question,
          format: cubit.state.draft.format,
        ),
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
    title: context.tr("Teams (optional)"),
    icon: Icons.groups_outlined,
    trailing: IconButton(
      tooltip: context.tr("Add team"),
      onPressed: onAdd,
      icon: const Icon(Icons.add),
    ),
    child: teams.isEmpty
        ? EmptyHint(context.tr("No teams: this quiz will start in solo mode."))
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
                    tooltip: context.tr("Remove {0}", [team.name]),
                    onPressed: () => onRemove(team.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          ),
  );
}

class _QuestionsPanel extends StatefulWidget {
  const _QuestionsPanel({
    required this.questions,
    required this.format,
    required this.onAddTemplate,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  final List<Question> questions;
  final QuizFormat format;
  final ValueChanged<QuestionTemplate> onAddTemplate;
  final ValueChanged<Question> onEdit;
  final ValueChanged<String> onRemove;
  final ReorderCallback onReorder;

  @override
  State<_QuestionsPanel> createState() => _QuestionsPanelState();
}

class _QuestionsPanelState extends State<_QuestionsPanel> {
  QuestionTemplate? _selectedTemplate;

  @override
  Widget build(BuildContext context) => PanelCard(
    title: context.tr("Questions"),
    icon: Icons.quiz_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionTemplateDropdown(
          value: _selectedTemplate,
          onChanged: (template) => setState(() => _selectedTemplate = template),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _selectedTemplate == null
                ? null
                : () => widget.onAddTemplate(_selectedTemplate!),
            icon: const Icon(Icons.add),
            label: Text(context.tr("Add question")),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.questions.isEmpty)
          EmptyHint(context.tr("Add questions before hosting this quiz."))
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.questions.length,
            onReorderItem: widget.onReorder,
            itemBuilder: (context, index) {
              final question = widget.questions[index];
              return ListTile(
                key: ValueKey(question.id),
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (question) {
                  MultipleChoiceQuestion() => Icons.checklist,
                  BuzzerQuestion() => Icons.bolt,
                  ShortAnswerQuestion() => Icons.text_fields,
                  OrderingQuestion() => Icons.sort,
                  MatchingQuestion() => Icons.compare_arrows,
                  EstimationQuestion() => Icons.numbers,
                  TrueFalseQuestion() => Icons.rule,
                }),
                title: Text(
                  question.prompt.isEmpty
                      ? context.tr("Untitled question")
                      : question.prompt,
                ),
                subtitle: Text(
                  context.tr("{0} · {1}s · {2}", [
                    context.tr(question.kindLabel),
                    question.timeLimit.inSeconds,
                    switch (widget.format) {
                      StandardFormat() => context.tr(
                        question.scoringRule.label,
                      ),
                      PokerFormat() => context.tr(
                        "Gewinn abhängig vom Einsatz",
                      ),
                      JeopardyFormat() => context.tr("Punkte aus der Zeile"),
                    },
                  ]),
                ),
                onTap: () => widget.onEdit(question),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.drag_handle),
                    IconButton(
                      tooltip: context.tr("Delete question"),
                      onPressed: () => widget.onRemove(question.id),
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
    title: Text(
      widget.team == null ? context.tr("Add team") : context.tr("Edit team"),
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.tr("Team name")),
            validator: (value) => value == null || value.trim().isEmpty
                ? context.tr("Enter a team name.")
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _colorController,
            decoration: InputDecoration(
              labelText: context.tr("ARGB colour (for example FF5E6AD2)"),
            ),
            validator: (value) => _parseColor(value) == null
                ? context.tr("Enter an 8-digit hexadecimal ARGB colour.")
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.tr("Cancel")),
      ),
      FilledButton(onPressed: _save, child: Text(context.tr("Save team"))),
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
