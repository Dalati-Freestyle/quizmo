/// On-screen rendering of a finished game's [GameProtocol].
library;

import 'package:flutter/material.dart';

import '../../core/models/game_protocol.dart';
import '../l10n/app_localizations.dart';
import 'protocol_labels.dart';

/// Final standings with shared places; the row of [highlightId] is accented.
class FinalStandingsList extends StatelessWidget {
  /// Creates the list.
  const FinalStandingsList({
    required this.protocol,
    this.highlightId,
    super.key,
  });

  /// Protocol to render.
  final GameProtocol protocol;

  /// Standing id (player or team) to highlight.
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String tr(String key, [List<Object?> args = const []]) =>
        context.tr(key, args);
    if (protocol.standings.isEmpty) {
      return Text(context.tr('No scores yet.'));
    }
    return Column(
      children: [
        for (final standing in protocol.standings)
          Container(
            key: ValueKey('final-standing-${standing.id}'),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: standing.id == highlightId
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: standing.id == highlightId
                  ? Border.all(color: scheme.primary, width: 2)
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    '${standing.place}.',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        standing.id == highlightId
                            ? '${standing.name} (${standing.isTeam ? tr('Dein Team') : tr('Du')})'
                            : standing.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: standing.id == highlightId
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                      if (standing.memberNames.isNotEmpty)
                        Text(
                          standing.memberNames.join(', '),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text(
                  '${standing.score} ${protocolUnit(protocol, tr)}',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The complete protocol: standings, questions with all answers and the
/// correction history.
class ProtocolView extends StatelessWidget {
  /// Creates the view.
  const ProtocolView({required this.protocol, this.highlightId, super.key});

  /// Protocol to render.
  final GameProtocol protocol;

  /// Standing id (player or team) to highlight.
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String tr(String key, [List<Object?> args = const []]) =>
        context.tr(key, args);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(protocol.title, style: theme.textTheme.headlineSmall),
        Text(
          '${tr('Spielprotokoll')} · ${tr(protocolFormatKey(protocol.format))}'
          ' · ${protocolDateTime(protocol.generatedAtMicros)}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text(tr('Platzierung'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        FinalStandingsList(protocol: protocol, highlightId: highlightId),
        const SizedBox(height: 24),
        Text(tr('Fragen'), style: theme.textTheme.titleLarge),
        if (protocol.questions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Es wurden keine Fragen gespielt.')),
          ),
        for (final question in protocol.questions)
          Card(
            key: ValueKey('protocol-question-${question.number}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${question.number}. ${question.prompt}',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (protocolQuestionTags(question, tr) case final tags
                      when tags.isNotEmpty)
                    Text(tags.join(' · '), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    tr('Lösung: {0}', [tr(question.solution)]),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Divider(),
                  for (final answer in question.answers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              answer.team == null
                                  ? answer.player
                                  : '${answer.player} (${answer.team})',
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              [
                                answer.answer == null
                                    ? '—'
                                    : tr(answer.answer!),
                                tr(protocolStatusKey(answer.status)),
                                if (answer.wager case final wager?)
                                  tr('Einsatz: {0}', [wager]),
                                if (answer.practice) tr('Nur Übung'),
                              ].join(' · '),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              answer.points == null
                                  ? ''
                                  : signed(answer.points!),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(tr('Korrekturverlauf'), style: theme.textTheme.titleLarge),
        if (protocol.corrections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Noch keine manuellen Korrekturen.')),
          ),
        for (final entry in protocol.corrections)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${entry.target}: ${protocolCorrectionChange(entry, tr)}'
              '${entry.delta == null ? '' : ' (${signed(entry.delta!)})'}',
            ),
            subtitle: Text(
              [
                '${protocolTime(entry.atMicros)} · '
                    '${tr(protocolCorrectionKey(entry.kind))}',
                if (entry.isReversal) tr('Rücknahme'),
                entry.question ?? tr('Ohne Bezug zu einer Frage'),
                if (entry.reason?.isNotEmpty ?? false)
                  tr('Begründung: {0}', [entry.reason!]),
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}
