/// Editor panel for the interstitial slides of a quiz.
library;

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import '../../l10n/app_localizations.dart';
import 'media_editor.dart';
import 'markdown_field.dart';

/// Lists the slides in their position between the questions.
class SlidesEditorPanel extends StatelessWidget {
  /// Creates the panel for [quiz].
  const SlidesEditorPanel({
    required this.quiz,
    required this.createId,
    required this.onSave,
    required this.onRemove,
    super.key,
  });

  final Quiz quiz;
  final String Function() createId;
  final ValueChanged<InfoSlide> onSave;
  final ValueChanged<String> onRemove;

  String _position(BuildContext context, InfoSlide slide) {
    final index = quiz.questions.indexWhere(
      (question) => question.id == slide.beforeQuestionId,
    );
    return index < 0
        ? context.tr("Nach der letzten Frage")
        : context.tr("Vor Frage {0}: {1}", [
            index + 1,
            markdownToPlain(quiz.questions[index].prompt),
          ]);
  }

  Future<void> _edit(BuildContext context, [InfoSlide? slide]) async {
    final edited = await showDialog<InfoSlide>(
      context: context,
      builder: (_) => SlideEditorDialog(
        quiz: quiz,
        slide: slide ?? InfoSlide(id: 'slide-${createId()}'),
      ),
    );
    if (edited != null) onSave(edited);
  }

  @override
  Widget build(BuildContext context) {
    final ordered = interleaveSlides(
      quiz.questions,
      quiz.slides,
      (question) => question.id,
    ).whereType<InfoSlide>();
    return PanelCard(
      title: context.tr("Zwischenfolien (optional)"),
      icon: Icons.slideshow_outlined,
      trailing: IconButton(
        key: const ValueKey('add-slide'),
        tooltip: context.tr("Zwischenfolie hinzufügen"),
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
      ),
      child: quiz.slides.isEmpty
          ? EmptyHint(
              context.tr(
                "Keine Zwischenfolien. Sie zeigen zwischen den Fragen z. B. eine Pause, eine Kategorie oder „Das Ergebnis ist unterwegs“ – ohne Wertung.",
              ),
            )
          : Column(
              children: [
                for (final slide in ordered)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.slideshow_outlined),
                    title: Text(
                      slide.title.trim().isEmpty
                          ? markdownToPlain(slide.text)
                          : slide.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _position(context, slide),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _edit(context, slide),
                    trailing: IconButton(
                      tooltip: context.tr("Remove {0}", [slide.title]),
                      onPressed: () => onRemove(slide.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Edits title, text, media and position of one slide.
class SlideEditorDialog extends StatefulWidget {
  /// Creates the dialog for [slide] of [quiz].
  const SlideEditorDialog({required this.quiz, required this.slide, super.key});

  final Quiz quiz;
  final InfoSlide slide;

  @override
  State<SlideEditorDialog> createState() => _SlideEditorDialogState();
}

class _SlideEditorDialogState extends State<SlideEditorDialog> {
  late InfoSlide _slide = widget.slide;

  @override
  Widget build(BuildContext context) {
    final questions = widget.quiz.questions;
    final errors = _slide.validationErrors({for (final q in questions) q.id});
    return AlertDialog(
      title: Text(context.tr("Zwischenfolie")),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('slide-title'),
                initialValue: _slide.title,
                decoration: InputDecoration(labelText: context.tr("Titel")),
                onChanged: (value) =>
                    setState(() => _slide = _slide.copyWith(title: value)),
              ),
              const SizedBox(height: 12),
              MarkdownField(
                key: const ValueKey('slide-text'),
                initialValue: _slide.text,
                label: context.tr("Text"),
                onChanged: (value) =>
                    setState(() => _slide = _slide.copyWith(text: value)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const ValueKey('slide-position'),
                isExpanded: true,
                initialValue:
                    questions.any((q) => q.id == _slide.beforeQuestionId)
                    ? _slide.beforeQuestionId
                    : null,
                decoration: InputDecoration(labelText: context.tr("Position")),
                items: [
                  for (final (index, question) in questions.indexed)
                    DropdownMenuItem(
                      value: question.id,
                      child: Text(
                        context.tr("Vor Frage {0}: {1}", [
                          index + 1,
                          markdownToPlain(question.prompt),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.tr("Nach der letzten Frage")),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _slide = _slide.copyWith(beforeQuestionId: value),
                ),
              ),
              const SizedBox(height: 12),
              MediaEditor(
                title: context.tr("Medien der Zwischenfolie"),
                media: _slide.media,
                onChanged: (media) =>
                    setState(() => _slide = _slide.copyWith(media: media)),
              ),
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
          key: const ValueKey('save-slide'),
          onPressed: errors.isEmpty
              ? () => Navigator.of(context).pop(_slide)
              : null,
          child: Text(context.tr("Save")),
        ),
      ],
    );
  }
}
