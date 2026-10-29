import 'dart:convert';

import '../models/answer.dart';
import '../models/game_state.dart';
import '../models/question.dart';

enum ReportAnswerStatus {
  correct,
  partial,
  incorrect,
  ungraded,
  noAnswer,
  notEligible,
  teamAnswered,
}

final class ReportAnswer {
  const ReportAnswer({
    required this.phase,
    required this.questionId,
    required this.question,
    required this.playerId,
    required this.player,
    required this.teamId,
    required this.team,
    required this.answer,
    required this.status,
    required this.accuracy,
    required this.elapsedMicros,
    required this.disconnected,
    required this.practice,
    required this.wager,
    required this.steal,
    required this.dailyDouble,
    required this.buzzer,
    required this.pointsAtStake,
  });

  final int phase;
  final String questionId;
  final String question;
  final String playerId;
  final String player;
  final String? teamId;
  final String? team;
  final String? answer;
  final ReportAnswerStatus status;
  final double? accuracy;
  final int? elapsedMicros;
  final bool disconnected;
  final bool practice;
  final int? wager;
  final bool steal;
  final bool dailyDouble;
  final bool buzzer;
  final int? pointsAtStake;
}

final class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.name,
    required this.isTeam,
    required this.finalScore,
    required this.evaluated,
    required this.correct,
    required this.meanElapsedMicros,
    required this.connected,
    required this.inRoster,
  });

  final String id;
  final String name;
  final bool isTeam;
  final int? finalScore;
  final int evaluated;
  final int correct;
  final double? meanElapsedMicros;
  final bool connected;
  final bool inRoster;
  double? get hitRate => evaluated == 0 ? null : correct / evaluated;
}

final class ReportProgress {
  const ReportProgress({
    required this.phase,
    required this.questionId,
    required this.id,
    required this.name,
    required this.isTeam,
    required this.score,
  });
  final int phase;
  final String questionId;
  final String id;
  final String name;
  final bool isTeam;
  final int score;
}

final class SessionReport {
  SessionReport._({
    required this.title,
    required this.format,
    required this.finished,
    required this.historyComplete,
    required this.answers,
    required this.summaries,
    required this.progress,
    required this.corrections,
  });

  factory SessionReport.fromGame(GameState game, {required String title}) {
    final answers = <ReportAnswer>[];
    final progress = <ReportProgress>[];
    final poker = game.poker != null;
    final teamMode = game.mode is TeamMode || poker;
    for (final player in game.players.values) {
      if (!poker) {
        progress.add(
          ReportProgress(
            phase: 0,
            questionId: '',
            id: player.id,
            name: player.name,
            isTeam: false,
            score: 0,
          ),
        );
      }
    }
    if (teamMode) {
      for (final team in game.teams.values) {
        progress.add(
          ReportProgress(
            phase: 0,
            questionId: '',
            id: team.id,
            name: team.name,
            isTeam: true,
            score: game.poker?.startingChips ?? 0,
          ),
        );
      }
    }
    for (final (index, record) in game.reportRounds.indexed) {
      final round = record.round;
      final question = round.question!;
      final phase = index + 1;
      for (final player in record.players.values) {
        final submission = round.answers[player.id];
        final press = record.presses[player.id];
        final accuracy = submission != null
            ? round.accuracyFor(submission)
            : round.buzzerVerdicts[player.id]?.toDouble();
        final eligible = record.eligiblePlayerIds.contains(player.id);
        final teamAnswered =
            teamMode &&
            (game.jeopardy != null || poker) &&
            player.teamId != null &&
            [
              ...round.answers.keys,
              ...round.buzzerVerdicts.keys,
            ].any((id) => record.players[id]?.teamId == player.teamId);
        final status = switch (accuracy) {
          1 => ReportAnswerStatus.correct,
          final double value when value > 0 => ReportAnswerStatus.partial,
          final double _ => ReportAnswerStatus.incorrect,
          null when submission != null || press != null =>
            ReportAnswerStatus.ungraded,
          null when !eligible => ReportAnswerStatus.notEligible,
          null when teamAnswered => ReportAnswerStatus.teamAnswered,
          null => ReportAnswerStatus.noAnswer,
        };
        final input = submission ?? press;
        // A buzzer measures reaction time, not the duration of a spoken answer.
        final elapsed = input == null
            ? null
            : round.acceptedElapsedMicros[player.id] ??
                  (round.startedAtHostMicros == null
                      ? null
                      : round
                            .elapsedAt(input.hostTimestampMicros)
                            .inMicroseconds);
        answers.add(
          ReportAnswer(
            phase: phase,
            questionId: question.id,
            question: question.prompt,
            playerId: player.id,
            player: player.name,
            teamId: teamMode ? player.teamId : null,
            team: teamMode ? record.teamNames[player.teamId] : null,
            answer: input == null ? null : reportAnswerLabel(input, question),
            status: status,
            accuracy: accuracy,
            elapsedMicros: elapsed,
            disconnected: record.disconnectedPlayerIds.contains(player.id),
            practice: record.practiceTeamIds.contains(player.teamId),
            wager: poker ? record.wagers[player.teamId] ?? 0 : null,
            steal: record.isSteal,
            dailyDouble: record.isDailyDouble,
            buzzer: question is BuzzerQuestion,
            pointsAtStake: record.pointsAtStake,
          ),
        );
      }
      if (!poker) {
        for (final entry in record.players.entries) {
          progress.add(
            ReportProgress(
              phase: phase,
              questionId: question.id,
              id: entry.key,
              name: entry.value.name,
              isTeam: false,
              score: record.playerScores[entry.key] ?? 0,
            ),
          );
        }
      }
      if (teamMode) {
        for (final team in record.teamNames.entries) {
          progress.add(
            ReportProgress(
              phase: phase,
              questionId: question.id,
              id: team.key,
              name: team.value,
              isTeam: true,
              score: poker
                  ? record.chips[team.key] ?? 0
                  : record.players.values
                        .where((p) => p.teamId == team.key)
                        .fold(
                          0,
                          (total, p) =>
                              total + (record.playerScores[p.id] ?? 0),
                        ),
            ),
          );
        }
      }
    }

    ReportSummary summary(
      String id,
      String name,
      bool isTeam,
      int? score,
      bool connected,
      bool inRoster,
    ) {
      final rows = answers.where(
        (a) => isTeam ? a.teamId == id : a.playerId == id,
      );
      final metrics = reportMetrics(rows);
      return ReportSummary(
        id: id,
        name: name,
        isTeam: isTeam,
        finalScore: score,
        evaluated: metrics.evaluated,
        correct: metrics.correct,
        meanElapsedMicros: metrics.meanElapsedMicros,
        connected: connected,
        inRoster: inRoster,
      );
    }

    final summaries =
        [
          for (final player in {
            for (final record in game.reportRounds) ...record.players,
            ...game.players,
          }.values)
            summary(
              player.id,
              player.name,
              false,
              poker || !game.players.containsKey(player.id)
                  ? null
                  : game.scores.scoreOf(player.id),
              game.players[player.id]?.isConnected ?? false,
              game.players.containsKey(player.id),
            ),
          if (teamMode)
            for (final team in game.teams.values)
              summary(
                team.id,
                team.name,
                true,
                game.teamScores[team.id] ?? 0,
                game.players.values.any(
                  (p) => p.teamId == team.id && p.isConnected,
                ),
                true,
              ),
        ]..sort((a, b) {
          if (a.isTeam != b.isTeam) return a.isTeam ? -1 : 1;
          if (a.finalScore == null && b.finalScore != null) return 1;
          if (b.finalScore == null && a.finalScore != null) return -1;
          final score = (b.finalScore ?? 0).compareTo(a.finalScore ?? 0);
          return score != 0 ? score : a.id.compareTo(b.id);
        });
    return SessionReport._(
      title: title,
      format: poker
          ? 'poker'
          : game.jeopardy != null
          ? 'jeopardy'
          : 'standard',
      finished: game.isFinished,
      historyComplete: game.completedQuestionIds.every(
        (id) => game.reportRounds.any((r) => r.round.question?.id == id),
      ),
      answers: List.unmodifiable(answers),
      summaries: List.unmodifiable(summaries),
      progress: List.unmodifiable(progress),
      corrections: List.unmodifiable([
        for (final entry in game.corrections)
          Map<String, Object?>.unmodifiable({
            'correction_id': entry.id,
            'question_id': entry.questionId,
            'entity_type': entry.teamId == null ? 'player' : 'team',
            'entity_id': entry.teamId ?? entry.playerId,
            'name': entry.participantName,
            'team_id': entry.teamId,
            'status': entry.kind.name,
            'reason': entry.reason,
            'value_before': entry.beforeValue,
            'value_after': entry.afterValue,
            'reverses_correction': entry.reversesId,
            'score_delta': poker
                ? entry.chipDeltas.values.fold<int>(0, (a, b) => a + b)
                : entry.scoreDeltas.values.fold<int>(0, (a, b) => a + b),
          }),
      ]),
    );
  }

  final String title;
  final String format;
  final bool finished;
  final bool historyComplete;
  final List<ReportAnswer> answers;
  final List<ReportSummary> summaries;
  final List<ReportProgress> progress;
  final List<Map<String, Object?>> corrections;

  static const columns = [
    'report_version',
    'row_type',
    'quiz',
    'format',
    'finished',
    'history_complete',
    'phase',
    'question_id',
    'question',
    'entity_type',
    'entity_id',
    'name',
    'team_id',
    'team',
    'answer',
    'status',
    'accuracy_ratio',
    'response_time_ms',
    'response_time_kind',
    'connection',
    'practice_only',
    'wager_chips',
    'points_at_stake',
    'steal',
    'daily_double',
    'score_unit',
    'score',
    'evaluated_answers',
    'fully_correct_answers',
    'hit_rate_ratio',
    'mean_response_time_ms',
    'correction_id',
    'reason',
    'value_before',
    'value_after',
    'reverses_correction',
    'score_delta',
  ];

  String toCsv() {
    final lines = <List<Object?>>[columns];
    void add(Map<String, Object?> values) => lines.add([
      for (final column in columns)
        switch (column) {
          'report_version' => 1,
          'quiz' => title,
          'format' => format,
          'finished' => finished,
          'history_complete' => historyComplete,
          'score_unit' => format == 'poker' ? 'chips' : 'points',
          _ => values[column] ?? 'N/A',
        },
    ]);
    for (final entry in summaries) {
      add({
        'row_type': 'summary',
        'entity_type': entry.isTeam ? 'team' : 'player',
        'entity_id': entry.id,
        'name': entry.name,
        'score': entry.finalScore,
        'connection': !entry.inRoster
            ? 'removed_from_roster'
            : entry.connected
            ? 'connected_at_end'
            : 'disconnected_at_end',
        'evaluated_answers': entry.evaluated,
        'fully_correct_answers': entry.correct,
        'hit_rate_ratio': entry.hitRate,
        'mean_response_time_ms': entry.meanElapsedMicros == null
            ? null
            : entry.meanElapsedMicros! / 1000,
      });
    }
    for (final entry in answers) {
      add({
        'row_type': 'answer',
        'phase': entry.phase,
        'question_id': entry.questionId,
        'question': entry.question,
        'entity_type': 'player',
        'entity_id': entry.playerId,
        'name': entry.player,
        'team_id': entry.teamId,
        'team': entry.team,
        'answer': entry.answer,
        'status': entry.status.name,
        'accuracy_ratio': entry.accuracy,
        'response_time_ms': entry.elapsedMicros == null
            ? null
            : entry.elapsedMicros! / 1000,
        'response_time_kind': entry.buzzer
            ? 'buzzer_reaction'
            : 'answer_submission',
        'connection': entry.disconnected
            ? 'disconnection_observed'
            : 'no_disconnection_observed',
        'practice_only': entry.practice,
        'wager_chips': entry.wager,
        'points_at_stake': entry.pointsAtStake,
        'steal': entry.steal,
        'daily_double': entry.dailyDouble,
      });
    }
    for (final phase in answers.map((a) => a.phase).toSet()) {
      final phaseAnswers = answers.where((a) => a.phase == phase);
      for (final teamId
          in phaseAnswers.map((a) => a.teamId).whereType<String>().toSet()) {
        final rows = phaseAnswers.where((a) => a.teamId == teamId).toList();
        final metrics = reportMetrics(rows);
        add({
          'row_type': 'question_summary',
          'phase': phase,
          'question_id': rows.first.questionId,
          'question': rows.first.question,
          'entity_type': 'team',
          'entity_id': teamId,
          'name': rows.first.team,
          'team_id': teamId,
          'team': rows.first.team,
          'evaluated_answers': metrics.evaluated,
          'fully_correct_answers': metrics.correct,
          'hit_rate_ratio': metrics.hitRate,
          'mean_response_time_ms': metrics.meanElapsedMicros == null
              ? null
              : metrics.meanElapsedMicros! / 1000,
          'status': rows.any((a) => a.answer != null)
              ? 'answered'
              : rows.every((a) => a.status == ReportAnswerStatus.notEligible)
              ? 'notEligible'
              : 'noAnswer',
          'practice_only': rows.any((a) => a.practice),
          'wager_chips': rows.first.wager,
          'points_at_stake': rows.first.pointsAtStake,
          'steal': rows.first.steal,
          'daily_double': rows.first.dailyDouble,
        });
      }
    }
    for (final entry in progress) {
      add({
        'row_type': 'progress',
        'phase': entry.phase,
        'question_id': entry.questionId,
        'entity_type': entry.isTeam ? 'team' : 'player',
        'entity_id': entry.id,
        'name': entry.name,
        'score': entry.score,
      });
    }
    for (final entry in corrections) {
      add({'row_type': 'correction', ...entry});
    }
    return '\uFEFF${lines.map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n';
  }
}

({int evaluated, int correct, double? hitRate, double? meanElapsedMicros})
reportMetrics(Iterable<ReportAnswer> answers) {
  var evaluated = 0;
  var correct = 0;
  var timed = 0;
  var elapsed = 0;
  for (final answer in answers) {
    if (answer.accuracy != null) {
      evaluated++;
      if (answer.accuracy == 1) correct++;
    }
    if (answer.elapsedMicros case final time?) {
      elapsed += time;
      timed++;
    }
  }
  return (
    evaluated: evaluated,
    correct: correct,
    hitRate: evaluated == 0 ? null : correct / evaluated,
    meanElapsedMicros: timed == 0 ? null : elapsed / timed,
  );
}

String csvCell(Object? value) {
  var text = value?.toString() ?? 'N/A';
  // Quote syntax alone does not stop spreadsheet formula evaluation.
  if (value is String &&
      (RegExp(r'^[\s\u0000-\u0020]*[=+\-@＝＋－＠]').hasMatch(text) ||
          RegExp(r'^[\t\r\n]').hasMatch(text))) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

String reportAnswerLabel(
  AnswerSubmission answer,
  Question question,
) => switch (answer) {
  ShortAnswer(:final text) => text,
  EstimationAnswer(:final value) =>
    question is EstimationQuestion
        ? '$value ${question.unit}'.trimRight()
        : '$value',
  TrueFalseAnswer(:final value) => value ? 'true' : 'false',
  MultipleChoiceAnswer(:final selectedOptionIds) => jsonEncode([
    for (final id in selectedOptionIds)
      {
        'id': id,
        'label': question is MultipleChoiceQuestion
            ? question.options.where((o) => o.id == id).firstOrNull?.label ?? id
            : id,
      },
  ]),
  OrderingAnswer(:final itemIds) => jsonEncode([
    for (final id in itemIds)
      {
        'id': id,
        'label': question is OrderingQuestion
            ? question.items.where((o) => o.id == id).firstOrNull?.label ?? id
            : id,
      },
  ]),
  MatchingAnswer(:final pairs) => jsonEncode([
    for (final entry in pairs.entries)
      {
        'left_id': entry.key,
        'right_id': entry.value,
        'left': question is MatchingQuestion
            ? question.leftItems
                      .where((o) => o.id == entry.key)
                      .firstOrNull
                      ?.label ??
                  entry.key
            : entry.key,
        'right': question is MatchingQuestion
            ? question.rightItems
                      .where((o) => o.id == entry.value)
                      .firstOrNull
                      ?.label ??
                  entry.value
            : entry.value,
      },
  ]),
  BuzzerPress() => 'buzzer (spoken answer not recorded)',
};
