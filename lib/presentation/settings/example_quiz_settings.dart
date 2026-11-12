import 'package:flutter/material.dart';

import '../../core/data/quiz_repository.dart';
import '../l10n/app_localizations.dart';
import '../quizmaster/editor/quiz_library_repository.dart';

class ExampleQuizSettings extends StatefulWidget {
  const ExampleQuizSettings({this.repository, this.onChanged, super.key});

  final QuizRepository? repository;
  final Future<void> Function()? onChanged;

  @override
  State<ExampleQuizSettings> createState() => _ExampleQuizSettingsState();
}

class _ExampleQuizSettingsState extends State<ExampleQuizSettings> {
  bool _isBusy = false;
  String? _error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.tr(
          'Recreate the default quizzes. Unedited examples are replaced; edited examples and your own quizzes are kept.',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _isBusy ? null : _recreate,
        icon: _isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.restore),
        label: Text(context.tr('Recreate example quizzes')),
      ),
      if (_error != null)
        Text(
          context.tr(_error!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );

  Future<void> _recreate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Recreate example quizzes?')),
        content: Text(
          context.tr(
            'Unedited examples will be removed and recreated. Edited examples and your own quizzes will not be changed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Recreate example quizzes')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await (widget.repository ?? createQuizRepository()).recreateExamples(
        DateTime.now(),
      );
      await widget.onChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Example quizzes recreated.'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('Could not recreate example quizzes: {0}', [
          context.tr('$error'),
        ]);
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
