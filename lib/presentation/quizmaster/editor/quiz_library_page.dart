/// Local quiz library and entry point to the editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/data/quiz_repository.dart';
import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import '../../common/browser_exit_guard.dart';
import 'quiz_editor_page.dart';
import 'quiz_file_transfer.dart';
import 'quiz_library_cubit.dart';
import 'quiz_library_repository.dart';

/// Lets the host choose, edit, import, and export a locally stored quiz.
class QuizLibraryPage extends StatelessWidget {
  /// Creates a library page, optionally with test-specific dependencies.
  const QuizLibraryPage({
    this.repository,
    this.createId,
    this.now,
    this.selectForHosting = false,
    super.key,
  });

  /// Optional repository override for widget tests.
  final QuizRepository? repository;

  /// Optional ID generator override for widget tests.
  final String Function()? createId;

  /// Optional clock override for widget tests.
  final DateTime Function()? now;

  /// Whether a card may return its quiz to start a new host session.
  final bool selectForHosting;

  @override
  Widget build(BuildContext context) {
    final ids = createId ?? _newId;
    return BlocProvider(
      create: (_) => QuizLibraryCubit(
        repository: repository ?? createQuizRepository(),
        createId: ids,
        now: now,
      )..load(),
      child: _QuizLibraryView(
        createId: ids,
        now: now ?? DateTime.now,
        selectForHosting: selectForHosting,
      ),
    );
  }
}

class _QuizLibraryView extends StatelessWidget {
  const _QuizLibraryView({
    required this.createId,
    required this.now,
    required this.selectForHosting,
  });

  final String Function() createId;
  final DateTime Function() now;
  final bool selectForHosting;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<QuizLibraryCubit, QuizLibraryState>(
        listenWhen: (previous, current) =>
            current.error != null && current.error != previous.error,
        listener: (context, state) {
          if (state.requiredSchemaVersion != null) {
            showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Update Quizmo to import this quiz'),
                content: const Text(
                  'This quiz requires a newer version of Quizmo. '
                  'Update the app, then import this file again. '
                  'Your quiz library has not been changed.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: const Text('Quiz library'),
            actions: [
              if (kIsWeb)
                TextButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () => _leave(context, state.quizzes),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Seite verlassen'),
                ),
              TextButton.icon(
                onPressed: state.isBusy ? null : () => _importQuiz(context),
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import'),
              ),
              IconButton(
                tooltip: 'Create quiz',
                onPressed: state.isBusy ? null : () => _createQuiz(context),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : AdaptivePanelGrid(
                  panels: [
                    if (kIsWeb)
                      const PanelCard(
                        title: 'Quizzes in diesem Browser',
                        icon: Icons.save_outlined,
                        child: Text(
                          'Deine Quizzes bleiben in diesem Browser gespeichert. Exportiere sie als Sicherung, bevor du die Seite verlässt oder Browserdaten löschst. Beim Schließen des Tabs: Abbrechen wählen und hier exportieren.',
                        ),
                      ),
                    for (final quiz in state.quizzes)
                      _QuizCard(
                        quiz: quiz,
                        isBusy: state.isBusy,
                        onHost: selectForHosting
                            ? () => Navigator.of(context).pop(quiz)
                            : null,
                        onEdit: () => _editQuiz(context, quiz),
                        onExport: () => _exportQuiz(context, quiz),
                        onDelete: () => _deleteQuiz(context, quiz),
                      ),
                    if (state.quizzes.isEmpty)
                      const PanelCard(
                        title: 'No quizzes available',
                        icon: Icons.quiz_outlined,
                        child: EmptyHint(
                          'Create or import a quiz to get started.',
                        ),
                      ),
                  ],
                ),
        ),
      );

  Future<void> _createQuiz(BuildContext context) {
    final timestamp = now().toUtc();
    return _openEditor(
      context,
      Quiz(
        id: createId(),
        name: 'Untitled quiz',
        description: 'A new Quizmo quiz.',
        category: 'General knowledge',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  Future<void> _leave(BuildContext context, List<Quiz> quizzes) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quizzes vor dem Verlassen exportieren?'),
        content: const Text(
          'Die Quizzes bleiben im Browser gespeichert. Für eine Sicherung kannst du sie jetzt in der Bibliothek exportieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'leave'),
            child: const Text('Ohne Export verlassen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'export'),
            child: const Text('Quizzes exportieren'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'leave') leaveBrowserPage();
    if (choice == 'export') {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Quizzes exportieren'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final quiz in quizzes)
                    ListTile(
                      title: Text(quiz.name),
                      trailing: IconButton(
                        tooltip: 'Export including media',
                        icon: const Icon(Icons.download),
                        onPressed: () => _exportQuiz(context, quiz),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Zurück'),
            ),
            TextButton(
              onPressed: leaveBrowserPage,
              child: const Text('Seite verlassen'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _editQuiz(BuildContext context, Quiz quiz) =>
      _openEditor(context, quiz);

  Future<void> _openEditor(BuildContext context, Quiz quiz) async {
    final repository = context.read<QuizLibraryCubit>().repository;
    final saved = await Navigator.of(context).push<Quiz>(
      MaterialPageRoute<Quiz>(
        builder: (_) => QuizEditorPage(
          repository: repository,
          quiz: quiz,
          createId: createId,
        ),
      ),
    );
    if (!context.mounted || saved == null) return;
    await context.read<QuizLibraryCubit>().load();
  }

  Future<void> _importQuiz(BuildContext context) async {
    try {
      final contents = await pickQuizJson();
      if (!context.mounted || contents == null) return;
      final imported = await context.read<QuizLibraryCubit>().importContents(
        contents,
      );
      if (!context.mounted || imported == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported "${imported.name}".')));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import quiz: $error')));
    }
  }

  Future<void> _exportQuiz(BuildContext context, Quiz quiz) async {
    try {
      final exported = await exportQuizFile(quiz);
      if (!context.mounted || !exported) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported "${quiz.name}" including media.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export quiz: $error')));
    }
  }

  Future<void> _deleteQuiz(BuildContext context, Quiz quiz) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete quiz?'),
        content: Text('Delete "${quiz.name}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!context.mounted || shouldDelete != true) return;
    await context.read<QuizLibraryCubit>().delete(quiz);
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.quiz,
    required this.isBusy,
    required this.onHost,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  final Quiz quiz;
  final bool isBusy;
  final VoidCallback? onHost;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => PanelCard(
    title: quiz.name,
    icon: Icons.quiz_outlined,
    trailing: PopupMenuButton<_QuizAction>(
      onSelected: (action) => switch (action) {
        _QuizAction.edit => onEdit(),
        _QuizAction.export => onExport(),
        _QuizAction.delete => onDelete(),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: _QuizAction.edit, child: Text('Edit')),
        PopupMenuItem(value: _QuizAction.export, child: Text('Export file')),
        PopupMenuItem(value: _QuizAction.delete, child: Text('Delete')),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quiz.description.isEmpty ? 'No description.' : quiz.description),
        const SizedBox(height: 12),
        InfoRow(label: 'Category', value: quiz.category),
        InfoRow(label: 'Type', value: quiz.format.label),
        InfoRow(label: 'Questions', value: '${quiz.questions.length}'),
        InfoRow(label: 'Teams', value: '${quiz.teams.length}'),
        if (quiz.questions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'First question: ${quiz.questions.first.prompt}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isBusy ? null : onExport,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export quiz with media'),
        ),
        if (onHost != null)
          FilledButton.icon(
            onPressed: isBusy ? null : onHost,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Host this quiz'),
          ),
      ],
    ),
  );
}

enum _QuizAction { edit, export, delete }

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
