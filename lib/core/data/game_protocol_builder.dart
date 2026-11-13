/// Builds the guest facing [GameProtocol] from the host's full game state.
library;

import '../models/answer.dart';
import '../models/game_protocol.dart';
import '../models/game_state.dart';
import '../models/manual_correction.dart';
import '../models/question.dart';
import 'session_report.dart';

/// Reason the engine stores on score events booked by manual corrections.
const _manualReason = 'Manual correction';

/// Builds the protocol of [game] (the unredacted host state).
///
/// It is based on the host's [SessionReport] so that the protocol and the
/// report export always agree.
GameProtocol buildGameProtocol(GameState game, {required String title}) {
  final report = SessionReport.fromGame(game, title: title);
  final poker = game.poker != null;
  final teamMode = game.mode is TeamMode || poker;

  final standings = <ProtocolStanding>[];
  if (teamMode) {
    final ranked = rankByScore(
      game.teams.values,
      (team) => game.teamScores[team.id] ?? 0,
      tieBreak: (a, b) => a.name.compareTo(b.name),
    );
    for (final (team, place) in ranked) {
      final members = [
        for (final id in game.playerOrder)
          if (game.players[id] case final player? when player.teamId == team.id)
            player,
        for (final player in game.players.values)
          if (player.teamId == team.id && !game.playerOrder.contains(player.id))
            player,
      ];
      standings.add(
        ProtocolStanding(
          id: team.id,
          name: team.name,
          isTeam: true,
          score: game.teamScores[team.id] ?? 0,
          place: place,
          memberIds: [for (final player in members) player.id],
          memberNames: [for (final player in members) player.name],
        ),
      );
    }
  } else {
    final ranked = rankByScore(
      game.players.values,
      (player) => game.scores.scoreOf(player.id),
      tieBreak: (a, b) => a.name.compareTo(b.name),
    );
    for (final (player, place) in ranked) {
      standings.add(
        ProtocolStanding(
          id: player.id,
          name: player.name,
          isTeam: false,
          score: game.scores.scoreOf(player.id),
          place: place,
        ),
      );
    }
  }

  // Points earned per question and player, without manual corrections; those
  // are listed in the correction history.
  final earned = <String, Map<String, int>>{};
  for (final event in game.scores.history) {
    if (event.isTeamBooking || event.reason == _manualReason) continue;
    final perPlayer = earned[event.questionId] ??= {};
    perPlayer[event.playerId] = (perPlayer[event.playerId] ?? 0) + event.points;
  }
  // The last phase a player actually answered a question gets its points.
  final pointsPhase = <(String, String), int>{};
  for (final answer in report.answers) {
    if (answer.answer != null) {
      pointsPhase[(answer.questionId, answer.playerId)] = answer.phase;
    }
  }
  // Chips per phase and team in a poker session.
  final chipsByPhase = <int, Map<String, int>>{};
  for (final entry in report.progress) {
    if (entry.isTeam) {
      (chipsByPhase[entry.phase] ??= {})[entry.id] = entry.score;
    }
  }

  int? earnedIn(int phase, String questionId, String playerId) =>
      pointsPhase[(questionId, playerId)] != phase
      ? null
      : earned[questionId]?[playerId];

  final categories = <String, String>{
    for (final category in game.jeopardy?.board.categories ?? const [])
      for (final cell in category.cells) ?cell.questionId: category.name,
  };

  final questions = <ProtocolQuestion>[];
  for (final (index, record) in game.reportRounds.indexed) {
    final question = record.round.question!;
    final phase = index + 1;
    questions.add(
      ProtocolQuestion(
        number: phase,
        questionId: question.id,
        prompt: question.prompt,
        solution: question.solutionLabel,
        category: categories[question.id],
        pointsAtStake: record.pointsAtStake,
        isSteal: record.isSteal,
        isDailyDouble: record.isDailyDouble,
        answers: [
          for (final answer in report.answers.where((a) => a.phase == phase))
            ProtocolAnswer(
              playerId: answer.playerId,
              player: answer.player,
              team: answer.team,
              answer: switch (record.round.answers[answer.playerId] ??
                  record.presses[answer.playerId]) {
                final input? => protocolAnswerLabel(input, question),
                null => null,
              },
              status: _status(answer.status),
              wager: answer.wager,
              practice: answer.practice,
              points: poker
                  ? _chipChange(chipsByPhase, phase, answer.teamId)
                  : earnedIn(phase, question.id, answer.playerId),
            ),
        ],
      ),
    );
  }

  final prompts = {
    for (final question in [
      ...game.questionBank,
      for (final record in game.reportRounds) record.round.question!,
    ])
      question.id: question.prompt,
  };
  final corrections = [
    for (final entry in game.corrections)
      ProtocolCorrection(
        atMicros: entry.atHostMicros,
        kind: switch (entry.kind) {
          CorrectionKind.answer => ProtocolCorrectionKind.answer,
          CorrectionKind.buzzer => ProtocolCorrectionKind.buzzer,
          CorrectionKind.points => ProtocolCorrectionKind.points,
          CorrectionKind.chips => ProtocolCorrectionKind.chips,
        },
        target: entry.participantName,
        question: entry.questionId == null
            ? null
            : prompts[entry.questionId] ?? entry.questionId,
        before: entry.beforeValue,
        after: entry.afterValue,
        delta: switch ([
          ...entry.scoreDeltas.values,
          ...entry.teamDeltas.values,
          ...entry.chipDeltas.values,
        ]) {
          final deltas when deltas.isEmpty => null,
          final deltas => deltas.fold<int>(0, (a, b) => a + b),
        },
        reason: entry.reason,
        isReversal: entry.reversesId != null,
      ),
  ];

  return GameProtocol(
    title: title,
    generatedAtMicros: game.hostTimeMicros,
    format: poker
        ? ProtocolFormat.poker
        : game.jeopardy != null
        ? ProtocolFormat.jeopardy
        : ProtocolFormat.standard,
    teamMode: teamMode,
    standings: standings,
    questions: questions,
    corrections: corrections,
  );
}

/// Returns the snapshot that players and TV screens receive.
///
/// Identical to [GameState.redactedForPlayers], plus the [GameProtocol] once
/// the game is finished. Until then the protocol (and with it every solution
/// and foreign answer) stays on the host.
GameState guestSnapshotOf(
  GameState game, {
  required String title,
  bool includeMediaData = false,
}) {
  final redacted = game.redactedForPlayers(includeMediaData: includeMediaData);
  return game.isFinished
      ? redacted.copyWith(protocol: buildGameProtocol(game, title: title))
      : redacted;
}

/// Human readable label of [answer] to [question] for the protocol.
///
/// True/false answers use the same German message keys as
/// [Question.solutionLabel] ("Wahr" / "Falsch"), so the UI translates both.
String protocolAnswerLabel(AnswerSubmission answer, Question question) {
  String find(Iterable<AnswerOption> items, String id) =>
      items.where((item) => item.id == id).firstOrNull?.label ?? id;
  return switch (answer) {
    ShortAnswer(:final text) => text,
    EstimationAnswer(:final value) =>
      question is EstimationQuestion
          ? '$value ${question.unit}'.trimRight()
          : '$value',
    TrueFalseAnswer(:final value) => value ? 'Wahr' : 'Falsch',
    MultipleChoiceAnswer(:final selectedOptionIds) => [
      for (final id in selectedOptionIds)
        question is MultipleChoiceQuestion ? find(question.options, id) : id,
    ].join(', '),
    OrderingAnswer(:final itemIds) => [
      for (final (index, id) in itemIds.indexed)
        '${index + 1}. ${question is OrderingQuestion ? find(question.items, id) : id}',
    ].join('  '),
    MatchingAnswer(:final pairs) => [
      for (final entry in pairs.entries)
        question is MatchingQuestion
            ? '${find(question.leftItems, entry.key)} → ${find(question.rightItems, entry.value)}'
            : '${entry.key} → ${entry.value}',
    ].join('; '),
    BuzzerPress() => 'Buzzer',
  };
}

int? _chipChange(Map<int, Map<String, int>> chips, int phase, String? team) {
  if (team == null) return null;
  final after = chips[phase]?[team];
  final before = chips[phase - 1]?[team];
  if (after == null || before == null || after == before) return null;
  return after - before;
}

ProtocolAnswerStatus _status(ReportAnswerStatus status) => switch (status) {
  ReportAnswerStatus.correct => ProtocolAnswerStatus.correct,
  ReportAnswerStatus.partial => ProtocolAnswerStatus.partial,
  ReportAnswerStatus.incorrect => ProtocolAnswerStatus.incorrect,
  ReportAnswerStatus.ungraded => ProtocolAnswerStatus.ungraded,
  ReportAnswerStatus.noAnswer => ProtocolAnswerStatus.noAnswer,
  ReportAnswerStatus.notEligible => ProtocolAnswerStatus.notEligible,
  ReportAnswerStatus.teamAnswered => ProtocolAnswerStatus.teamAnswered,
};
