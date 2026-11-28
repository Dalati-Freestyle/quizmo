/// What the players have to do right now, for the TV.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// A short instruction with its icon; `null` when nothing is to do.
typedef TvInstruction = ({IconData icon, String text});

typedef InstructionTr = String Function(String key, [List<Object?> args]);

/// The instruction for the phase of [game] (a guest snapshot); never tells
/// anything about the solution.
TvInstruction? tvInstruction(InstructionTr tr, GameState game) {
  final round = game.round;
  final question = round.question;
  final jeopardy = game.jeopardy;
  final poker = game.poker;
  final teams = game.mode is TeamMode || poker != null;
  String say(String team, String solo) => tr(teams ? team : solo);

  if (game.showsSlide || game.isFinished) return null;
  if (poker != null && poker.questionHidden) {
    if (poker.stakesBeforeReveal && poker.betting) {
      return (
        icon: Icons.casino_outlined,
        text: tr('Setzt eure Chips auf diese Kategorie.'),
      );
    }
    final jokers = game.jokers;
    final possible =
        jokers != null &&
        jokers.jokers.any(
          (joker) =>
              joker.beforeReveal &&
              game.teams.keys.any((id) => jokers.remainingFor(id, joker) > 0),
        );
    return possible
        ? (icon: Icons.style_outlined, text: tr('Spielt jetzt eure Joker aus.'))
        : null;
  }
  if (question == null) {
    if (jeopardy == null) return null;
    final picker = game.participantName(jeopardy.currentTeamId);
    if (picker == null ||
        game.completedQuestionIds.length >= jeopardy.board.questionIds.length) {
      return null;
    }
    return jeopardy.pendingDailyDoubleId != null
        ? (icon: Icons.star, text: tr('{0} legt den Einsatz fest.', [picker]))
        : (icon: Icons.grid_view, text: tr('{0} wählt ein Feld.', [picker]));
  }
  if (round.status == RoundStatus.revealed ||
      round.status == RoundStatus.idle) {
    return null;
  }
  if (poker != null && poker.betting) {
    return (icon: Icons.casino_outlined, text: tr('Setzt eure Chips.'));
  }
  if (round.status == RoundStatus.locked) {
    if (question is BuzzerQuestion) {
      // Who answers is on the board already.
      return round.activePlayerId != null
          ? null
          : (icon: Icons.lock_outline, text: tr('Der Buzzer ist geschlossen.'));
    }
    return (
      icon: Icons.lock_outline,
      text: round.manualGrading
          ? tr('Antworten sind geschlossen. Die Spielleitung bewertet.')
          : tr('Antworten sind geschlossen.'),
    );
  }
  final snowflake = round.snowflake != null;
  // Exhaustive over the sealed hierarchy: a new kind needs its sentence.
  final TvInstruction what = round.verbal
      ? (
          icon: Icons.record_voice_over_outlined,
          text: say('Sagt eure Antwort laut.', 'Sag deine Antwort laut.'),
        )
      : switch (question) {
          ShortAnswerQuestion() => (
            icon: Icons.keyboard_outlined,
            text: [
              say(
                'Gebt eure Antwort auf eurem Gerät ein.',
                'Gib deine Antwort auf deinem Gerät ein.',
              ),
              if (round.manualGrading) tr('Die Spielleitung bewertet.'),
            ].join(' '),
          ),
          OrderingQuestion() => (
            icon: Icons.swap_vert,
            text: snowflake
                ? say(
                    'Bringt die Elemente in eine Reihenfolge, die sonst niemand wählt.',
                    'Bring die Elemente in eine Reihenfolge, die sonst niemand wählt.',
                  )
                : say(
                    'Bringt die Elemente auf eurem Gerät in die richtige Reihenfolge.',
                    'Bring die Elemente auf deinem Gerät in die richtige Reihenfolge.',
                  ),
          ),
          MatchingQuestion() => (
            icon: Icons.compare_arrows,
            text: snowflake
                ? say(
                    'Ordnet die Begriffe so zu, wie es sonst niemand tut.',
                    'Ordne die Begriffe so zu, wie es sonst niemand tut.',
                  )
                : say(
                    'Ordnet jedem Begriff den passenden zu.',
                    'Ordne jedem Begriff den passenden zu.',
                  ),
          ),
          EstimationQuestion(:final unit, :final valueFormat) => (
            icon: valueFormat.isTime ? Icons.timer_outlined : Icons.numbers,
            text: valueFormat.isTime
                ? tr(
                    teams
                        ? 'Schätzt die Zeit und gebt sie als {0} ein.'
                        : 'Schätz die Zeit und gib sie als {0} ein.',
                    [valueFormat.pattern],
                  )
                : unit.trim().isEmpty
                ? say(
                    'Schätzt und gebt eine Zahl ein.',
                    'Schätz und gib eine Zahl ein.',
                  )
                : tr(
                    teams
                        ? 'Schätzt und gebt eine Zahl ein (in {0}).'
                        : 'Schätz und gib eine Zahl ein (in {0}).',
                    [unit.trim()],
                  ),
          ),
          TrueFalseQuestion() => (
            icon: Icons.rule,
            text: snowflake
                ? say(
                    'Wählt die Antwort, die sonst niemand wählt.',
                    'Wähl die Antwort, die sonst niemand wählt.',
                  )
                : say(
                    'Wahr oder falsch? Wählt auf eurem Gerät.',
                    'Wahr oder falsch? Wähl auf deinem Gerät.',
                  ),
          ),
          MultipleChoiceQuestion(:final allowMultipleAnswers) => (
            icon: Icons.touch_app_outlined,
            text: snowflake
                ? say(
                    'Wählt die Antwort, die sonst niemand wählt.',
                    'Wähl die Antwort, die sonst niemand wählt.',
                  )
                : allowMultipleAnswers
                ? say(
                    'Wählt alle richtigen Antworten.',
                    'Wähl alle richtigen Antworten.',
                  )
                : say('Wählt eine Antwort.', 'Wähl eine Antwort.'),
          ),
          LocationQuestion() => (
            icon: Icons.place_outlined,
            text: say(
              'Markiert den Ort auf der Karte auf eurem Gerät.',
              'Markier den Ort auf der Karte auf deinem Gerät.',
            ),
          ),
          BuzzerQuestion() => (
            icon: Icons.bolt,
            text: say(
              'Drückt den Buzzer und antwortet laut.',
              'Drück den Buzzer und antworte laut.',
            ),
          ),
        };
  // On a board only some may answer: they are named.
  if (jeopardy != null &&
      jeopardy.hasActiveQuestion &&
      jeopardy.currentTeamId != null &&
      !round.buzzerOpenForAll) {
    final names = [
      for (final id in game.participantIds)
        if (jeopardy.mayAnswer(id)) ?game.participantName(id),
    ];
    if (names.isNotEmpty) {
      return (icon: what.icon, text: '${names.join(', ')}: ${what.text}');
    }
  }
  return what;
}

/// The instruction in one line on the 1920×1080 canvas; the slot keeps its
/// height when it is empty, so nothing jumps between the phases.
class TvInstructionLine extends StatelessWidget {
  const TvInstructionLine({required this.game, this.color, super.key});

  final GameState game;

  /// Colour of the team that may answer, if there is one.
  final Color? color;

  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final instruction = tvInstruction(context.tr, game);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('tv-instruction'),
      height: height,
      child: instruction == null
          ? null
          : Semantics(
              liveRegion: true,
              label: instruction.text,
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(
                      instruction.icon,
                      size: 40,
                      color: color ?? scheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        instruction.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: instruction.text.length > 70 ? 28 : 34,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
