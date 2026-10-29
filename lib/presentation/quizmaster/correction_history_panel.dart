import 'package:flutter/material.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../../core/sync/clock.dart';
import '../l10n/app_localizations.dart';

class CorrectionHistoryPanel extends StatelessWidget {
  const CorrectionHistoryPanel({
    required this.game,
    required this.engine,
    super.key,
  });

  final GameState game;
  final QuizEngineBloc engine;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const Icon(Icons.history),
      title: Text(context.tr('Korrekturverlauf')),
      subtitle: Text(
        context.tr('Nur für den Host · {0} Einträge', [
          game.corrections.length,
        ]),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              context.tr(
                game.poker == null ? 'Punkte korrigieren' : 'Chips korrigieren',
              ),
            ),
            onPressed:
                !game.recoveryPaused &&
                    game.players.isNotEmpty &&
                    game.round.question != null
                ? () async {
                    final event = await showDialog<CorrectScoreEvent>(
                      context: context,
                      builder: (_) => _ScoreCorrectionDialog(game: game),
                    );
                    if (event != null && !engine.isClosed) engine.add(event);
                  }
                : null,
          ),
        ),
        if (game.corrections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr('Noch keine manuellen Korrekturen.')),
          )
        else
          SizedBox(
            height: 360,
            child: ListView(
              children: [
                for (final entry in game.corrections.reversed)
                  _entry(context, entry),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _entry(BuildContext context, ManualCorrection entry) {
    final error = engine.correctionUndoError(entry);
    final grade =
        entry.kind == CorrectionKind.answer ||
        entry.kind == CorrectionKind.buzzer;
    String value(int? number) => grade
        ? context.tr(
            number == null
                ? 'Unbewertet'
                : number == 1
                ? 'Richtig'
                : 'Wrong',
          )
        : '$number';
    final label = context.tr(switch (entry.kind) {
      CorrectionKind.answer => 'Manuelle Bewertung',
      CorrectionKind.buzzer => 'Buzzer-Bewertung',
      CorrectionKind.points => 'Punkte korrigieren',
      CorrectionKind.chips => 'Chips korrigieren',
    });
    final timestamp = DateTime.fromMicrosecondsSinceEpoch(entry.atHostMicros)
        .toLocal();
    return ListTile(
      isThreeLine: true,
      title: Text(
        '${entry.participantName}: ${value(entry.beforeValue)} → ${value(entry.afterValue)}',
      ),
      subtitle: Text(
        [
          '$label · ${entry.id}',
          '${context.tr('Runde')}: ${entry.questionId} · ${entry.roundStartedAt}',
          '$timestamp',
          if (entry.scoreDeltas.isNotEmpty)
            context.tr('Punkteänderung: {0}', [
              entry.scoreDeltas.values.fold<int>(0, (a, b) => a + b),
            ]),
          if (entry.chipDeltas.isNotEmpty)
            context.tr('Chipänderung: {0}', [
              entry.chipDeltas.values.fold<int>(0, (a, b) => a + b),
            ]),
          if (entry.reversesId != null)
            context.tr('Gegenkorrektur zu {0}', [entry.reversesId!]),
          if (entry.reason?.isNotEmpty ?? false) entry.reason!,
          if (error != null) context.tr(error),
        ].join('\n'),
      ),
      trailing: IconButton(
        tooltip: context.tr('Rücknahme'),
        icon: const Icon(Icons.undo),
        onPressed: error != null
            ? null
            : () async {
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => _UndoDialog(entry: entry),
                );
                if (reason != null && !engine.isClosed) {
                  engine.add(UndoCorrectionEvent(entry.id, reason: reason));
                }
              },
      ),
    );
  }
}

class _ScoreCorrectionDialog extends StatefulWidget {
  const _ScoreCorrectionDialog({required this.game});
  final GameState game;

  @override
  State<_ScoreCorrectionDialog> createState() => _ScoreCorrectionDialogState();
}

class _ScoreCorrectionDialogState extends State<_ScoreCorrectionDialog> {
  final _form = GlobalKey<FormState>();
  final _delta = TextEditingController();
  final _reason = TextEditingController();
  late String _playerId = widget.game.players.keys.first;
  final _requestId = newId('correction');

  @override
  void dispose() {
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        widget.game.poker == null ? 'Punkte korrigieren' : 'Chips korrigieren',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _playerId,
                isExpanded: true,
                items: [
                  for (final player in widget.game.players.values)
                    DropdownMenuItem(
                      value: player.id,
                      child: Text(
                        widget.game.mode is TeamMode
                            ? '${widget.game.teams[player.teamId]?.name ?? "-"} / ${player.name}'
                            : player.name,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) setState(() => _playerId = id);
                },
              ),
              TextFormField(
                controller: _delta,
                decoration: InputDecoration(
                  labelText: context.tr('Änderung (+/-)'),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                validator: (text) {
                  final delta = int.tryParse(text?.trim() ?? '');
                  if (delta == null || delta == 0) {
                    return context.tr('Eine ganze Zahl ungleich 0 eingeben.');
                  }
                  final poker = widget.game.poker;
                  if (poker != null &&
                      (poker.chips[widget.game.players[_playerId]?.teamId] ??
                                  0) +
                              delta <
                          0) {
                    return context.tr(
                      'Die Korrektur würde negative Chips erzeugen.',
                    );
                  }
                  return null;
                },
              ),
              TextField(
                controller: _reason,
                decoration: InputDecoration(
                  labelText: context.tr('Grund (optional)'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Abbrechen')),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            CorrectScoreEvent(
              requestId: _requestId,
              playerId: _playerId,
              questionId: widget.game.round.question!.id,
              roundStartedAt: widget.game.round.startedAtHostMicros!,
              delta: int.parse(_delta.text.trim()),
              reason: _reason.text.trim(),
            ),
          );
        },
        child: Text(context.tr('Korrektur anwenden')),
      ),
    ],
  );
}

class _UndoDialog extends StatefulWidget {
  const _UndoDialog({required this.entry});
  final ManualCorrection entry;

  @override
  State<_UndoDialog> createState() => _UndoDialogState();
}

class _UndoDialogState extends State<_UndoDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Korrektur zurücknehmen?')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(
            'Die Änderung für {0} wird als neue Gegenkorrektur protokolliert. Spätere Änderungen bleiben erhalten.',
            [widget.entry.participantName],
          ),
        ),
        TextField(
          controller: _reason,
          decoration: InputDecoration(
            labelText: context.tr('Grund (optional)'),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Abbrechen')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _reason.text.trim()),
        child: Text(context.tr('Rücknahme bestätigen')),
      ),
    ],
  );
}
