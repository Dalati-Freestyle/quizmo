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
                    (game.players.isNotEmpty || game.teams.isNotEmpty)
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
          entry.questionId == null
              ? context.tr('Ohne Bezug zu einer Frage')
              : '${context.tr('Runde')}: ${entry.questionId} · ${entry.roundStartedAt}',
          '$timestamp',
          if (entry.scoreDeltas.isNotEmpty || entry.teamDeltas.isNotEmpty)
            context.tr('Punkteänderung: {0}', [
              [
                ...entry.scoreDeltas.values,
                ...entry.teamDeltas.values,
              ].fold<int>(0, (a, b) => a + b),
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

/// Target of a manual point change: a single player or a whole team.
typedef _Target = ({String? playerId, String? teamId});

class _ScoreCorrectionDialogState extends State<_ScoreCorrectionDialog> {
  final _form = GlobalKey<FormState>();
  final _delta = TextEditingController();
  final _reason = TextEditingController();
  final _requestId = newId('correction');
  late _Target _target = _targets.first;

  GameState get _game => widget.game;

  bool get _teamTargets => _game.mode is TeamMode || _game.poker != null;

  List<_Target> get _targets => [
    if (_teamTargets)
      for (final team in _game.teams.values) (playerId: null, teamId: team.id),
    for (final player in _game.players.values)
      (playerId: player.id, teamId: null),
  ];

  String _label(_Target target) {
    if (target.teamId case final teamId?) {
      return '${context.tr('Team')}: ${_game.teams[teamId]?.name ?? teamId}';
    }
    final player = _game.players[target.playerId]!;
    return _game.mode is TeamMode
        ? '${_game.teams[player.teamId]?.name ?? "-"} / ${player.name}'
        : player.name;
  }

  int? get _currentChips {
    final poker = _game.poker;
    if (poker == null) return null;
    return poker.chips[_target.teamId ??
        _game.players[_target.playerId]?.teamId];
  }

  @override
  void dispose() {
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _useNoReason() {
    setState(() => _reason.text = kNoReasonGiven);
    _form.currentState?.validate();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      CorrectScoreEvent(
        requestId: _requestId,
        playerId: _target.playerId,
        teamId: _target.teamId,
        delta: int.parse(_delta.text.trim()),
        reason: _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        _game.poker == null ? 'Punkte korrigieren' : 'Chips korrigieren',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<_Target>(
                key: const ValueKey('score-change-target'),
                initialValue: _target,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('Ziel')),
                items: [
                  for (final target in _targets)
                    DropdownMenuItem(
                      value: target,
                      child: Text(
                        _label(target),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (target) {
                  if (target != null) setState(() => _target = target);
                },
              ),
              TextFormField(
                key: const ValueKey('score-change-delta'),
                controller: _delta,
                decoration: InputDecoration(
                  labelText: context.tr('Änderung (+/-)'),
                  helperText: _currentChips == null
                      ? null
                      : context.tr('Aktueller Stand: {0} Chips', [
                          _currentChips!,
                        ]),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                validator: (text) {
                  final delta = int.tryParse(text?.trim() ?? '');
                  if (delta == null || delta == 0) {
                    return context.tr('Eine ganze Zahl ungleich 0 eingeben.');
                  }
                  if (_currentChips case final chips? when chips + delta < 0) {
                    return context.tr(
                      'Die Korrektur würde negative Chips erzeugen.',
                    );
                  }
                  return null;
                },
              ),
              TextFormField(
                key: const ValueKey('score-change-reason'),
                controller: _reason,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: context.tr('Begründung (Pflicht)'),
                ),
                validator: (text) => (text?.trim().isEmpty ?? true)
                    ? context.tr(
                        'Bitte eine Begründung angeben oder „Keine Begründung“ wählen.',
                      )
                    : null,
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('score-change-no-reason'),
                  icon: const Text(kNoReasonGiven),
                  label: Text(context.tr('Keine Begründung')),
                  onPressed: _useNoReason,
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
        onPressed: _apply,
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
