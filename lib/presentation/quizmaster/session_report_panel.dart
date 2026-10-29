import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/data/session_report.dart';
import '../../core/models/game_state.dart';
import '../l10n/app_localizations.dart';

class SessionReportPanel extends StatefulWidget {
  const SessionReportPanel({
    required this.game,
    required this.quizName,
    this.saveCsv,
    super.key,
  });

  final GameState game;
  final String quizName;
  final Future<bool> Function(SessionReport)? saveCsv;

  @override
  State<SessionReportPanel> createState() => _SessionReportPanelState();
}

class _SessionReportPanelState extends State<SessionReportPanel> {
  bool _exporting = false;

  Future<void> _export(SessionReport report) async {
    setState(() => _exporting = true);
    try {
      final saved = widget.saveCsv != null
          ? await widget.saveCsv!(report)
          : await FilePicker.saveFile(
                  dialogTitle: context.tr('CSV export'),
                  fileName: 'quizmo-results.csv',
                  bytes: utf8.encode(report.toCsv()),
                  mimeType: 'text/csv',
                ) !=
                null;
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('Report exported.'))));
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('CSV export failed: {0}', ['$error'])),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = SessionReport.fromGame(widget.game, title: widget.quizName);
    String metric(num? value) => value == null
        ? context.tr('Not applicable / unavailable')
        : value.toStringAsFixed(2);
    final unit = context.tr(report.format == 'poker' ? 'Chips' : 'Points');
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.assessment_outlined),
        title: Text(context.tr('Final report')),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Report metrics explained')),
          const SizedBox(height: 8),
          Text(context.tr('Report storage explained')),
          if (!report.historyComplete)
            Text(
              context.tr(
                'Older save: detailed history is incomplete. Final standings are authoritative.',
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _exporting ? null : () => _export(report),
            icon: const Icon(Icons.download),
            label: Text(context.tr('CSV export')),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Final standings'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final entry in report.summaries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${context.tr(entry.isTeam ? 'Team' : 'Player')}: ${entry.name}',
              ),
              subtitle: Text(
                context.tr(
                  'Correct: {0}/{1} judged; hit rate: {2} %; mean time: {3} ms; {4}',
                  [
                    entry.correct,
                    entry.evaluated,
                    metric(entry.hitRate == null ? null : entry.hitRate! * 100),
                    metric(
                      entry.meanElapsedMicros == null
                          ? null
                          : entry.meanElapsedMicros! / 1000,
                    ),
                    context.tr(
                      !entry.inRoster
                          ? 'Removed from roster'
                          : entry.connected
                          ? 'Connected at end'
                          : 'Disconnected at end',
                    ),
                  ],
                ),
              ),
              trailing: SizedBox(
                width: 100,
                child: Text(
                  entry.finalScore == null
                      ? context.tr('Not applicable / unavailable')
                      : '${entry.finalScore} $unit',
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ExpansionTile(
            title: Text(context.tr('Score progression')),
            children: [
              for (final entry in report.progress)
                ListTile(
                  title: Text('${entry.phase}. ${entry.name}'),
                  subtitle: Text(entry.questionId),
                  trailing: Text('${entry.score} $unit'),
                ),
            ],
          ),
          for (final phase in report.answers.map((a) => a.phase).toSet())
            ExpansionTile(
              key: ValueKey('report-phase-$phase'),
              title: Text(
                '$phase. ${report.answers.firstWhere((a) => a.phase == phase).question}',
              ),
              subtitle: Text(
                [
                  if (report.answers.firstWhere((a) => a.phase == phase).steal)
                    context.tr('Steal'),
                  if (report.answers
                      .firstWhere((a) => a.phase == phase)
                      .dailyDouble)
                    context.tr('Daily Double'),
                ].join(' · '),
              ),
              children: [
                for (final team
                    in report.answers
                        .where((a) => a.phase == phase)
                        .map((a) => a.teamId)
                        .whereType<String>()
                        .toSet())
                  Builder(
                    builder: (context) {
                      final rows = report.answers.where(
                        (a) => a.phase == phase && a.teamId == team,
                      );
                      final metrics = reportMetrics(rows);
                      return ListTile(
                        title: Text(
                          '${context.tr('Team')}: ${rows.first.team ?? team}',
                        ),
                        subtitle: Text(
                          context.tr(
                            'Correct: {0}/{1} judged; hit rate: {2} %; mean time: {3} ms',
                            [
                              metrics.correct,
                              metrics.evaluated,
                              metric(
                                metrics.hitRate == null
                                    ? null
                                    : metrics.hitRate! * 100,
                              ),
                              metric(
                                metrics.meanElapsedMicros == null
                                    ? null
                                    : metrics.meanElapsedMicros! / 1000,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                for (final row in report.answers.where((a) => a.phase == phase))
                  ListTile(
                    title: Text(
                      '${row.player}${row.team == null ? '' : ' / ${row.team}'}',
                    ),
                    subtitle: Text(
                      [
                        row.answer ?? context.tr('No answer recorded'),
                        context.tr(_statusLabel(row.status)),
                        context.tr('Accuracy / response time: {0} % / {1} ms', [
                          metric(
                            row.accuracy == null ? null : row.accuracy! * 100,
                          ),
                          metric(
                            row.elapsedMicros == null
                                ? null
                                : row.elapsedMicros! / 1000,
                          ),
                        ]),
                        if (row.disconnected)
                          context.tr(
                            'Disconnection observed during this phase',
                          ),
                        if (row.practice) context.tr('Practice only'),
                        if (row.wager != null)
                          context.tr('Stake: {0} chips', [row.wager]),
                        if (row.pointsAtStake != null)
                          context.tr('Points at stake: {0}', [
                            row.pointsAtStake,
                          ]),
                      ].join('\n'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String _statusLabel(ReportAnswerStatus status) => switch (status) {
  ReportAnswerStatus.correct => 'Richtig',
  ReportAnswerStatus.partial => 'Teilweise richtig',
  ReportAnswerStatus.incorrect => 'Leider falsch',
  ReportAnswerStatus.ungraded => 'Not judged',
  ReportAnswerStatus.noAnswer => 'Keine Antwort',
  ReportAnswerStatus.notEligible => 'Not eligible to answer',
  ReportAnswerStatus.teamAnswered => 'Answered by teammate',
};
