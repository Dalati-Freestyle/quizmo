/// The three information cards of the live round on the host: the private
/// host note, the solution and what the players answered.
///
/// They used to be lines of plain text in the round panel, and in a real game
/// it was not clear which line was the note, which the solution and which an
/// answer. Each card has its own colour, icon and title now.
library;

import 'package:flutter/material.dart';

import '../../core/engine/quiz_engine_event.dart';
import '../../core/models/models.dart';
import '../../core/sync/clock.dart';
import '../common/hint_views.dart';
import '../common/question_media_view.dart';
import '../common/question_result_view.dart';
import '../common/snowflake_result_view.dart';
import '../l10n/app_localizations.dart';
import '../common/media_playback.dart';

/// The kinds of round information, each with its own look.
enum RoundInfoKind {
  note(Icons.sticky_note_2_outlined, Color(0xFFF2A900)),
  solution(Icons.verified_outlined, Color(0xFF2E9D57)),
  answers(Icons.forum_outlined, Color(0xFF2F6FDB)),
  hints(Icons.lightbulb_outline, Color(0xFF8E44AD));

  const RoundInfoKind(this.icon, this.accent);

  final IconData icon;
  final Color accent;
}

/// A tinted card with a coloured header line.
class RoundInfoCard extends StatelessWidget {
  const RoundInfoCard({
    required this.kind,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final RoundInfoKind kind;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = kind.accent;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(kind.icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle case final text?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// The host's private note of the question; never sent to players.
class HostNoteCard extends StatelessWidget {
  const HostNoteCard({required this.note, super.key});

  final String note;

  @override
  Widget build(BuildContext context) => RoundInfoCard(
    key: const ValueKey('round-card-note'),
    kind: RoundInfoKind.note,
    title: context.tr('Admin-Notiz'),
    subtitle: context.tr('Nur für dich sichtbar'),
    child: SelectableText(note),
  );
}

/// The hints of the question on stage, shown to the guests one by one.
class HintsCard extends StatelessWidget {
  const HintsCard({
    required this.game,
    required this.onShow,
    required this.onTakeBack,
    super.key,
  });

  final GameState game;
  final ValueChanged<ShowHintEvent>? onShow;
  final ValueChanged<TakeBackHintEvent>? onTakeBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;
    final question = round.question;
    if (question == null || question.hints.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = round.shownHintCount;
    final next = round.nextHint;
    return RoundInfoCard(
      key: const ValueKey('round-card-hints'),
      kind: RoundInfoKind.hints,
      title: context.tr('Tipps'),
      subtitle: hintStatusText(context, game),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, hint) in question.hints.indexed)
            Opacity(
              opacity: index < shown ? 1 : 0.6,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      index < shown
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      semanticLabel: index < shown
                          ? context.tr('Gezeigt')
                          : context.tr('Noch verdeckt'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            hintTitle(context, game, index),
                            style: theme.textTheme.labelMedium,
                          ),
                          if (hint.text.trim().isNotEmpty) Text(hint.text),
                          if (hint.media.isNotEmpty)
                            QuestionMediaView(
                              key: ValueKey('host-hint-media-$index'),
                              media: hint.media,
                              // The host previews hints by hand; the
                              // shown ones stop with the host's pause.
                              playback: index < shown
                                  ? MediaPlayback.onDevice(
                                      game,
                                      stopped: index != shown - 1,
                                    )
                                  : MediaPlayback.onDemand,
                              playbackRevision: game.tvMediaRevision,
                              commandRevision: game.tvMediaCommandRevision,
                              maxMediaHeight: hostMediaHeight(context),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (next != null)
                FilledButton.icon(
                  key: const ValueKey('show-hint'),
                  onPressed: game.mayChangeHints && onShow != null
                      ? () => onShow!(
                          ShowHintEvent(
                            questionId: question.id,
                            shownHints: shown,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.lightbulb_outline),
                  label: Text(
                    context.tr('{0} zeigen', [hintTitle(context, game, shown)]),
                  ),
                ),
              if (shown > 0)
                OutlinedButton.icon(
                  key: const ValueKey('take-back-hint'),
                  onPressed: game.mayTakeBackHint && onTakeBack != null
                      ? () => onTakeBack!(
                          TakeBackHintEvent(
                            questionId: question.id,
                            shownHints: shown,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.undo),
                  label: Text(context.tr('Letzten Tipp zurücknehmen')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The stored solution of the question on stage.
class SolutionCard extends StatelessWidget {
  const SolutionCard({required this.question, required this.game, super.key});

  final Question question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revealed = game.round.status == RoundStatus.revealed;
    final label = question is TrueFalseQuestion
        ? context.tr(question.solutionLabel)
        : question.solutionLabel;
    return RoundInfoCard(
      key: const ValueKey('round-card-solution'),
      kind: RoundInfoKind.solution,
      title: context.tr('Lösung'),
      subtitle: revealed
          ? context.tr('Aufgelöst: Spieler sehen die Lösung.')
          : context.tr(
              'Noch geheim: Spieler sehen sie erst bei der Auflösung.',
            ),
      child: game.round.snowflake != null
          ? Text(context.tr('Keine Lösung: Die seltenste Antwort gewinnt.'))
          : label.trim().isEmpty
          ? Text(
              context.tr('Keine Lösung hinterlegt.'),
              style: TextStyle(color: theme.colorScheme.outline),
            )
          : SelectableText(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// What the players answered: "no question", "waiting for answers" or the
/// answers themselves, including the verdict controls of judged rounds.
class AnswersCard extends StatelessWidget {
  const AnswersCard({required this.game, super.key});

  final GameState game;
  @override
  Widget build(BuildContext context) {
    final round = game.round;
    final question = round.question;
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.outline);

    Widget body;
    String? subtitle;
    if (question == null) {
      body = Text(context.tr('Keine Frage aktiv.'), style: muted);
    } else if (game.poker?.betting ?? false) {
      body = Text(
        context.tr('Einsatzphase läuft. Die Antworten folgen danach.'),
        style: muted,
      );
    } else if (round.manualGrading) {
      subtitle = round.verbal
          ? context.tr(
              'Mündlich: Bewertet wird gemeinsam, sobald die Antworten geschlossen sind.',
            )
          : context.tr(
              'Bewertet wird gemeinsam, sobald die Antworten geschlossen sind.',
            );
      body = round.answers.isEmpty
          ? _waiting(context)
          : _WrittenAnswers(question: question, game: game);
    } else if (question is BuzzerQuestion) {
      body = _BuzzerAnswers(game: game);
    } else if (round.snowflake != null) {
      body = round.answers.isEmpty
          ? _waiting(context)
          : SnowflakeResultView(game: game, maxGroups: 50);
    } else {
      body = round.answers.isEmpty
          ? _waiting(context)
          : _WrittenAnswers(question: question, game: game);
    }
    return RoundInfoCard(
      key: const ValueKey('round-card-answers'),
      kind: RoundInfoKind.answers,
      title: context.tr('Antworten der Spieler'),
      subtitle: subtitle,
      trailing: question == null || question is BuzzerQuestion
          ? null
          : Text(
              '${round.answerCount} / ${game.connectedPlayers.length}',
              style: theme.textTheme.labelLarge,
            ),
      child: round.replacedAnswers.isEmpty || question == null
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                body,
                _ReplacedAnswers(question: question, game: game),
              ],
            ),
    );
  }

  Widget _waiting(BuildContext context) => Row(
    children: [
      // Static on purpose: an endless spinner would keep the frame busy.
      const Icon(Icons.hourglass_empty, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          game.round.status.acceptsInput
              ? context.tr('Warte auf Antworten der Spieler…')
              : context.tr('Keine Antworten eingegangen.'),
        ),
      ),
    ],
  );
}

/// Answers teams replaced in this round; they do not count.
class _ReplacedAnswers extends StatelessWidget {
  const _ReplacedAnswers({required this.question, required this.game});

  final Question question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final answers = [...game.round.replacedAnswers]..sort(compareAnswerOrder);
    return ExpansionTile(
      key: const ValueKey('replaced-answers'),
      tilePadding: EdgeInsets.zero,
      dense: true,
      title: Text(context.tr('Frühere Antworten ({0})', [answers.length])),
      children: [
        for (final answer in answers)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${_nameOf(game, answer.playerId)}: '
                '${answerLabel(answer, question, context: context)}',
              ),
            ),
          ),
      ],
    );
  }
}

/// Media in the host's round monitor: large, but the controls stay close.
double hostMediaHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.42).clamp(160, 460);

String _nameOf(GameState game, String playerId) {
  final player = game.players[playerId];
  final name = player?.name ?? playerId;
  if (game.mode is TeamMode) {
    final team = game.teams[player?.teamId]?.name;
    if (team != null) return '$team · $name';
  }
  return name;
}

/// Automatically scored answers, with their verdict after the reveal.
class _WrittenAnswers extends StatelessWidget {
  const _WrittenAnswers({required this.question, required this.game});

  final Question question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;
    final revealed = round.status == RoundStatus.revealed;
    final ordered = round.answers.values.toList()
      ..sort((a, b) => a.hostTimestampMicros.compareTo(b.hostTimestampMicros));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question case final MultipleChoiceQuestion choice)
          _ChoiceTally(question: choice, game: game),
        for (final answer in ordered)
          Padding(
            key: ValueKey('host-answer-${answer.playerId}'),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (revealed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 1),
                    child: _verdictIcon(round.accuracyFor(answer)),
                  ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_nameOf(game, answer.playerId)}: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: answerLabel(answer, question, context: context),
                        ),
                        if (round.adoptedPlayerIds.contains(answer.playerId))
                          TextSpan(
                            text: ' (${context.tr('beim Ablauf übernommen')})',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _verdictIcon(double? accuracy) => switch (accuracy) {
  null => const Icon(Icons.help_outline, size: 18),
  1 => const Icon(Icons.check_circle, size: 18, color: Color(0xFF2E9D57)),
  0 => const Icon(Icons.cancel, size: 18, color: Color(0xFFD64545)),
  _ => const Icon(Icons.timelapse, size: 18, color: Color(0xFFF2A900)),
};

class _ChoiceTally extends StatelessWidget {
  const _ChoiceTally({required this.question, required this.game});

  final MultipleChoiceQuestion question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;
    final tally = <String, int>{
      for (final option in question.options) option.id: 0,
    };
    for (final answer
        in round.answers.values.whereType<MultipleChoiceAnswer>()) {
      for (final id in answer.selectedOptionIds) {
        tally[id] = (tally[id] ?? 0) + 1;
      }
    }
    final total = round.answers.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final option in question.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option.label,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : (tally[option.id] ?? 0) / total,
                      minHeight: 6,
                      color: RoundInfoKind.answers.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${tally[option.id]}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The buzzer race: who pressed, in which latency adjusted order and who
/// currently has the floor.
class _BuzzerAnswers extends StatelessWidget {
  const _BuzzerAnswers({required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;
    if (round.buzzerQueue.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.bolt, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(context.tr("Buzzer armed — nobody pressed yet.")),
          ),
        ],
      );
    }
    final active = round.activePlayerId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.tr('{0} antwortet jetzt mündlich.', [
                _nameOf(game, active),
              ]),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Text(
          context.tr("Latency adjusted ranking"),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        for (final (index, press) in round.buzzerQueue.indexed)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: round.activePlayerId == press.playerId
                  ? RoundInfoKind.answers.accent.withValues(alpha: 0.22)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
            ),
            child: Row(
              children: [
                Text('${index + 1}.', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _nameOf(game, press.playerId),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration:
                          round.lockedOutPlayerIds.contains(press.playerId)
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                Text(
                  index == 0
                      ? context.tr('schnellster')
                      : '+${formatMicrosAsMillis(round.gapToFastest(press).inMicroseconds)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: index == 0
                        ? const Color(0xFF2E9D57)
                        : theme.colorScheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
