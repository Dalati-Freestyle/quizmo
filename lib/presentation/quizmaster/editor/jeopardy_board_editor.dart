/// Editor panel for the Jeopardy board of a quiz.
///
/// Every cell holds an ordinary [Question] of *any* kind: tapping a cell opens
/// the regular question editor, and the list of kinds offered for a new cell
/// is [kQuestionTemplates] — so a new question type (or one with audio or video
/// attached) becomes available on the board as soon as it has a template.
library;

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import 'question_editor.dart';
import 'quiz_editor_cubit.dart';

const double _kRowLabelWidth = 92;
const double _kCellWidth = 172;
const double _kCellHeight = 84;
const double _kHeaderHeight = 56;
const double _kGap = 8;

/// Lets the host lay out the board and fill its cells.
class JeopardyBoardEditorPanel extends StatelessWidget {
  /// Creates the panel for [board] of [quiz], editing through [cubit].
  const JeopardyBoardEditorPanel({
    required this.quiz,
    required this.board,
    required this.cubit,
    required this.createId,
    super.key,
  });

  /// The quiz being edited; provides the questions the cells point to.
  final Quiz quiz;

  /// The board of [quiz].
  final JeopardyBoard board;

  /// Receives every edit.
  final QuizEditorCubit cubit;

  /// Generates ids for new questions.
  final String Function() createId;

  @override
  Widget build(BuildContext context) {
    final questions = {
      for (final question in quiz.questions) question.id: question,
    };

    return PanelCard(
      title: 'Jeopardy board',
      icon: Icons.grid_view,
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: 'Add category (column)',
            onPressed: cubit.addCategory,
            icon: const Icon(Icons.view_column_outlined),
          ),
          IconButton(
            tooltip: 'Add point level (row)',
            onPressed: cubit.addRow,
            icon: const Icon(Icons.table_rows_outlined),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: board.penalizeWrongAnswers,
            onChanged: (value) =>
                cubit.updateBoardRules(penalizeWrongAnswers: value),
            title: const Text('Wrong answers cost points'),
            subtitle: const Text(
              'A wrong answer loses the points of the row. '
              'A Daily Double always risks the wager.',
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: board.allowSteal,
            onChanged: (value) => cubit.updateBoardRules(allowSteal: value),
            title: const Text('Other teams may steal'),
            subtitle: const Text(
              'The picking team answers first; after a miss the other teams '
              'may answer. Off: the question ends after the first miss.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The points of a cell come from its row; the scoring rule of the '
            'question itself is ignored on the board. Tap a category or a row '
            'label to rename it, a cell to edit its question, the star to '
            'make it a Daily Double.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: _kRowLabelWidth + _kGap),
                    for (var c = 0; c < board.categories.length; c++) ...[
                      _CategoryHeader(
                        name: board.categories[c].name,
                        onTap: () => _editCategory(context, c),
                      ),
                      const SizedBox(width: _kGap),
                    ],
                  ],
                ),
                const SizedBox(height: _kGap),
                for (var r = 0; r < board.rowCount; r++) ...[
                  Row(
                    children: [
                      _RowLabel(
                        points: board.rowPoints[r],
                        onTap: () => _editRow(context, r),
                      ),
                      const SizedBox(width: _kGap),
                      for (var c = 0; c < board.categories.length; c++) ...[
                        _CellTile(
                          cell: board.cellAt(c, r),
                          question: questions[board.cellAt(c, r).questionId],
                          onTap: () => _editCell(context, c, r),
                          onToggleDailyDouble: () =>
                              cubit.toggleDailyDouble(c, r),
                          onClear: () => cubit.clearCell(c, r),
                        ),
                        const SizedBox(width: _kGap),
                      ],
                    ],
                  ),
                  const SizedBox(height: _kGap),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editCategory(BuildContext context, int index) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(
        title: 'Category',
        label: 'Category name',
        initialValue: board.categories[index].name,
        deleteLabel: board.categories.length > 1
            ? 'Delete category and its questions'
            : null,
      ),
    );
    if (result == null) return;
    if (result.delete) {
      cubit.removeCategory(index);
    } else {
      cubit.renameCategory(index, result.value);
    }
  }

  Future<void> _editRow(BuildContext context, int row) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(
        title: 'Row ${row + 1}',
        label: 'Points of this row',
        initialValue: '${board.rowPoints[row]}',
        isNumber: true,
        deleteLabel: board.rowCount > 1 ? 'Delete row and its questions' : null,
      ),
    );
    if (result == null) return;
    if (result.delete) {
      cubit.removeRow(row);
    } else if (int.tryParse(result.value) case final points? when points > 0) {
      cubit.setRowPoints(row, points);
    }
  }

  Future<void> _editCell(BuildContext context, int category, int row) async {
    final cell = board.cellAt(category, row);
    Question? question;
    for (final candidate in quiz.questions) {
      if (candidate.id == cell.questionId) question = candidate;
    }

    question ??= await _chooseNewQuestion(context);
    if (question == null || !context.mounted) return;

    final edited = await Navigator.of(context).push<Question>(
      MaterialPageRoute<Question>(
        builder: (_) =>
            QuestionEditorPage(question: question!, usesBoardPoints: true),
      ),
    );
    if (edited == null) return;
    cubit.saveCellQuestion(category: category, row: row, question: edited);
  }

  Future<Question?> _chooseNewQuestion(BuildContext context) async {
    final template = await showDialog<QuestionTemplate>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('What kind of question?'),
        children: [
          for (final template in kQuestionTemplates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(template),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(template.icon),
                title: Text(template.label),
              ),
            ),
        ],
      ),
    );
    return template?.create(createId());
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _kCellWidth,
      height: _kHeaderHeight,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name.trim().isEmpty ? 'Unnamed' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.edit_outlined, size: 14, color: scheme.onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.points, required this.onTap});

  final int points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _kRowLabelWidth,
      height: _kCellHeight,
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Text(
              '$points',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CellTile extends StatelessWidget {
  const _CellTile({
    required this.cell,
    required this.question,
    required this.onTap,
    required this.onToggleDailyDouble,
    required this.onClear,
  });

  final JeopardyCell cell;
  final Question? question;
  final VoidCallback onTap;
  final VoidCallback onToggleDailyDouble;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = question;

    return SizedBox(
      width: _kCellWidth,
      height: _kCellHeight,
      child: Material(
        color: current == null
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: current == null
              ? Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18, color: scheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        'Add question',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 2, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          current.prompt.isEmpty
                              ? 'Untitled question'
                              : current.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.kindLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: cell.isDailyDouble
                                ? 'Remove Daily Double'
                                : 'Make Daily Double',
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: onToggleDailyDouble,
                            icon: Icon(
                              cell.isDailyDouble
                                  ? Icons.star
                                  : Icons.star_border,
                              color: cell.isDailyDouble
                                  ? scheme.tertiary
                                  : null,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove question',
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: onClear,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

final class _EditResult {
  const _EditResult(this.value, {this.delete = false});

  final String value;
  final bool delete;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.isNumber = false,
    this.deleteLabel,
  });

  final String title;
  final String label;
  final String initialValue;
  final bool isNumber;
  final String? deleteLabel;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    if (widget.isNumber && (int.tryParse(value) ?? 0) <= 0) return;
    Navigator.of(context).pop(_EditResult(value));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: widget.isNumber ? TextInputType.number : null,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      if (widget.deleteLabel case final label?)
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const _EditResult('', delete: true)),
          child: Text(label),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
