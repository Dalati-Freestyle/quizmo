import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../l10n/app_localizations.dart';

import '../../core/models/models.dart';

class SessionNotifications extends StatefulWidget {
  const SessionNotifications({
    required this.game,
    required this.child,
    this.playerId,
    super.key,
  });
  final GameState? game;
  final String? playerId;
  final Widget child;

  @override
  State<SessionNotifications> createState() => _SessionNotificationsState();
}

class _SessionNotificationsState extends State<SessionNotifications> {
  bool _placementShown = false;

  @override
  void initState() {
    super.initState();
    _notify(null);
  }

  @override
  void didUpdateWidget(SessionNotifications oldWidget) {
    super.didUpdateWidget(oldWidget);
    _notify(oldWidget.game);
  }

  void _notify(GameState? previous) {
    final game = widget.game;
    if (game == null) return;
    if (!game.isFinished) _placementShown = false;
    final messages = <String>[];
    if (previous != null) {
      if (widget.playerId != null &&
          !game.resultsHidden &&
          !game.showFinalReview &&
          game.round.status == RoundStatus.revealed &&
          (previous.round.status != RoundStatus.revealed ||
              previous.round.question?.id != game.round.question?.id)) {
        messages.add(roundFeedback(game, widget.playerId!, context: context));
      }
      for (final player in game.players.values) {
        final wasConnected = previous.players[player.id]?.isConnected ?? false;
        if (player.isConnected != wasConnected) {
          messages.add(
            context.tr(
              player.isConnected ? '{0} verbunden.' : '{0} getrennt.',
              [player.name],
            ),
          );
        }
      }
      if (game.allAnswersRevision > previous.allAnswersRevision) {
        messages.add(
          context.tr("Alle Spieler / teilnehmenden Teams haben geantwortet."),
        );
      }
    }
    final me = game.players[widget.playerId];
    final showPlacement =
        game.isFinished &&
        !game.showFinalReview &&
        me != null &&
        !_placementShown;
    if (showPlacement) _placementShown = true;
    if (messages.isEmpty && !showPlacement) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final message in messages) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      if (showPlacement) {
        final teamCompetition = game.mode is TeamMode && me.teamId != null;
        final scores = teamCompetition ? game.teamScores : game.scores.byPlayer;
        final myScore = scores[teamCompetition ? me.teamId : me.id] ?? 0;
        final place =
            1 + scores.values.where((score) => score > myScore).length;
        showDialog<void>(
          context: context,
          builder: (context) => PointerInterceptor(
            child: AlertDialog(
              title: Text(context.tr("Quiz beendet")),
              content: Text(
                context.tr("{0} Platz {1} mit {2} {3}!", [
                  teamCompetition
                      ? context.tr("Dein Team erreicht")
                      : context.tr("Du erreichst"),
                  place,
                  myScore,
                  game.poker == null
                      ? context.tr("Punkten")
                      : context.tr("Chips"),
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr("OK")),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.game?.recoveryPaused != true
      ? widget.child
      : Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.tr(
                    'Game paused for recovery. Reconnect participants before continuing. Media stays paused.',
                  ),
                ),
              ),
            ),
            if (widget.playerId != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  context.tr('Rejoin verification ID: {0}', [widget.playerId]),
                ),
              ),
            Expanded(child: widget.child),
          ],
        );
}

String roundFeedback(GameState game, String playerId, {BuildContext? context}) {
  final question = game.round.question;
  if (question == null) return '';
  final teamId = game.players[playerId]?.teamId;
  final teamMode = game.mode is TeamMode || game.poker != null;
  final ids = teamMode && teamId != null
      ? game.players.values
            .where((p) => p.teamId == teamId)
            .map((p) => p.id)
            .toSet()
      : {playerId};
  final answers = game.round.answers.values.where(
    (a) => ids.contains(a.playerId),
  );
  final verdicts = game.round.buzzerVerdicts.entries.where(
    (v) => ids.contains(v.key),
  );
  final accuracy = question is BuzzerQuestion
      ? (verdicts.any((v) => v.value == 1) ? 1.0 : 0.0)
      : answers.fold<double>(0, (best, answer) {
          final value = game.round.accuracyFor(answer) ?? 0;
          return value > best ? value : best;
        });
  final answered = answers.isNotEmpty || verdicts.isNotEmpty;
  final poker = game.poker;
  final points = poker != null
      ? (poker.wagers[teamId] ?? 0) * (accuracy == 1 ? 1 : -1)
      : game.scores.history
            .where(
              (event) =>
                  event.questionId == question.id &&
                  ids.contains(event.playerId),
            )
            .fold<int>(0, (sum, event) => sum + event.points);
  final verdict = !answered
      ? 'Keine Antwort'
      : accuracy == 1
      ? 'Richtig!'
      : accuracy > 0
      ? 'Teilweise richtig'
      : 'Leider falsch';
  final template = poker == null ? '{0} · {1} Punkte' : '{0} · {1} Chips';
  final arguments = [
    context?.tr(verdict) ?? verdict,
    '${points > 0 ? '+' : ''}$points',
  ];
  final result =
      context?.tr(template, arguments) ??
      AppLocalizations.formatMessage(template, arguments);
  final practice = poker != null && (poker.wagers[teamId] ?? 0) == 0;
  return '$result${practice ? ' · ${context?.tr("Ohne Einsatz: keine Wertung") ?? "Ohne Einsatz: keine Wertung"}' : ''}';
}
