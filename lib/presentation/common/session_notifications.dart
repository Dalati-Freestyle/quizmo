import 'package:flutter/material.dart';

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
    final showPlacement = game.isFinished && me != null && !_placementShown;
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
          builder: (context) => AlertDialog(
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
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
