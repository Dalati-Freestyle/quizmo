import 'package:flutter/material.dart';

import '../../../core/engine/quiz_engine_bloc.dart';
import '../../../core/models/models.dart';
import '../../l10n/app_localizations.dart';

class RebindRecoveryPanel extends StatefulWidget {
  const RebindRecoveryPanel({
    required this.engine,
    required this.game,
    super.key,
  });
  final QuizEngineBloc engine;
  final GameState game;
  @override
  State<RebindRecoveryPanel> createState() => _RebindRecoveryPanelState();
}

class _RebindRecoveryPanelState extends State<RebindRecoveryPanel> {
  String? _original;
  String? _temporary;

  @override
  Widget build(BuildContext context) {
    final originals = widget.game.players.values
        .where(
          (p) =>
              !p.isConnected && widget.engine.recoveryPlayerIds.contains(p.id),
        )
        .toList();
    final temporary = widget.game.players.values
        .where(
          (p) =>
              p.isConnected && !widget.engine.recoveryPlayerIds.contains(p.id),
        )
        .toList();
    if (originals.isEmpty || temporary.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
            'Missing private credentials? Join as a new participant, compare the verification ID on their screen, then explicitly reassign the original identity.',
          ),
        ),
        DropdownButton<String>(
          isExpanded: true,
          hint: Text(context.tr('Original participant')),
          value: originals.any((p) => p.id == _original) ? _original : null,
          items: [
            for (final p in originals)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (id) => setState(() {
            _original = id;
          }),
        ),
        DropdownButton<String>(
          isExpanded: true,
          hint: Text(context.tr('Connected verification ID')),
          value: temporary.any((p) => p.id == _temporary) ? _temporary : null,
          items: [
            for (final p in temporary)
              DropdownMenuItem(
                value: p.id,
                child: Text(
                  '${p.name} - ${p.id}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() {
            _temporary = id;
          }),
        ),
        OutlinedButton(
          onPressed:
              !originals.any((p) => p.id == _original) ||
                  !temporary.any((p) => p.id == _temporary)
              ? null
              : () async {
                  final original = _original!;
                  final replacement = _temporary!;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.tr('Confirm identity reassignment')),
                      content: Text(
                        context.tr(
                          'Only confirm after comparing verification ID {0} with the participant. Their old credential will be revoked; identity, team, answers and points remain unchanged.',
                          [replacement],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(context.tr('Cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(context.tr('Confirm')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    widget.engine.add(
                      RebindRecoveredPlayerEvent(
                        playerId: original,
                        temporaryPlayerId: replacement,
                      ),
                    );
                  }
                },
          child: Text(context.tr('Confirm identity reassignment')),
        ),
      ],
    );
  }
}
