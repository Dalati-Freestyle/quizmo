/// TV stage for the category phase of a poker question.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../common/joker_texts.dart';
import '../common/media_playback.dart';
import '../common/question_media_view.dart';
import '../common/quiz_markdown.dart';
import '../l10n/app_localizations.dart';
import '../common/tv_instruction.dart';

/// Announces the category while the question is still hidden, together with
/// the attack jokers played so far. The slide of the category (its text and
/// media) is shown with it when there is one.
class TvCategoryStage extends StatelessWidget {
  /// Creates the stage for [game].
  const TvCategoryStage({required this.game, super.key});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = game.poker?.category;
    final lines = jokerPlayLines(context, game);
    final slide = game.activeSlide;
    final hasMedia = slide != null && slide.media.isNotEmpty;
    final name = Text(
      category == null || category.trim().isEmpty
          ? context.tr("Ohne Kategorie")
          : category,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: hasMedia ? 72 : 120,
        fontWeight: FontWeight.w900,
      ),
    );
    final instruction = Text(
      [
        ?tvInstruction(context.tr, game)?.text,
        if (!(game.poker?.stakesBeforeReveal ?? false))
          context.tr('Die Frage folgt gleich.'),
      ].join(' '),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 34, color: scheme.onSurfaceVariant),
    );
    final jokers = [
      for (final line in lines.take(hasMedia ? 2 : 4))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            line,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: scheme.tertiary,
            ),
          ),
        ),
    ];
    final heading = Text(
      context.tr("Nächste Kategorie"),
      style: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
      ),
    );
    final text = slide != null && !isBlankMarkdown(slide.text)
        ? QuizMarkdown(
            slide.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34),
          )
        : null;
    if (hasMedia) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: heading),
          const SizedBox(height: 8),
          name,
          if (text != null) ...[const SizedBox(height: 8), text],
          const SizedBox(height: 16),
          Expanded(
            child: QuestionMediaView(
              key: ValueKey('category-media-${slide.id}'),
              media: slide.media,
              fill: true,
              playback: MediaPlayback.onTv(game),
              playbackRevision: game.tvMediaRevision,
              commandRevision: game.tvMediaCommandRevision,
            ),
          ),
          const SizedBox(height: 16),
          instruction,
          ...jokers,
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          heading,
          const SizedBox(height: 24),
          name,
          if (text != null) ...[const SizedBox(height: 16), text],
          const SizedBox(height: 40),
          instruction,
          if (lines.isNotEmpty) const SizedBox(height: 32),
          ...jokers,
        ],
      ),
    );
  }
}
