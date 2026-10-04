/// Input vocabulary of the [QuizEngineBloc].
///
/// Every state transition of a session is expressed as one of these events,
/// regardless of whether it originates from the host UI, from a web socket
/// frame or from a test.
library;

import 'package:equatable/equatable.dart';

import '../models/models.dart';

/// Base type of every engine input.
sealed class QuizEngineEvent extends Equatable {
  /// Const constructor for the sealed hierarchy.
  const QuizEngineEvent();

  @override
  List<Object?> get props => const [];
}

/// A client completed the join handshake.
///
/// Re-joining with a known id is idempotent and simply flips the player back to
/// connected, which is what makes a browser refresh survivable.
final class PlayerJoinedEvent extends QuizEngineEvent {
  /// Registers [player].
  const PlayerJoinedEvent(this.player);

  /// The joining participant.
  final Player player;

  @override
  List<Object?> get props => [player];
}

/// A client's socket closed.
final class PlayerLeftEvent extends QuizEngineEvent {
  /// Marks [playerId] as disconnected.
  const PlayerLeftEvent(this.playerId);

  /// Identifier of the leaving participant.
  final String playerId;

  @override
  List<Object?> get props => [playerId];
}

/// A client reported a refreshed clock estimate.
final class TimeSyncEvent extends QuizEngineEvent {
  /// Records the sync quality of [playerId].
  const TimeSyncEvent({
    required this.playerId,
    required this.clockOffsetMicros,
    required this.roundTripMicros,
  });

  /// Identifier of the reporting participant.
  final String playerId;

  /// How far the client clock runs ahead of the host clock.
  final int clockOffsetMicros;

  /// Round trip time backing the offset.
  final int roundTripMicros;

  @override
  List<Object?> get props => [playerId, clockOffsetMicros, roundTripMicros];
}

/// Assigns [playerId] to a team, or clears the assignment.
final class AssignTeamEvent extends QuizEngineEvent {
  /// Moves [playerId] into [teamId].
  const AssignTeamEvent({required this.playerId, required this.teamId});

  /// Identifier of the participant.
  final String playerId;

  /// Target team, or `null` to play solo.
  final String? teamId;

  @override
  List<Object?> get props => [playerId, teamId];
}

/// Switches the competition mode.
final class ChangeGameModeEvent extends QuizEngineEvent {
  /// Applies [mode].
  const ChangeGameModeEvent(this.mode);

  /// The new mode.
  final GameMode mode;

  @override
  List<Object?> get props => [mode];
}

/// Puts the question with [questionId] on stage and opens it for input.
final class StartRoundEvent extends QuizEngineEvent {
  /// Starts the round for [questionId].
  const StartRoundEvent(this.questionId);

  /// Identifier of the question in the bank.
  final String questionId;

  @override
  List<Object?> get props => [questionId];
}

/// Starts the first question that has not been revealed yet.
final class NextQuestionEvent extends QuizEngineEvent {
  /// Advances to the next pending question.
  const NextQuestionEvent();
}

/// A player picked an option of a `MultipleChoiceQuestion`.
final class SubmitAnswerEvent extends QuizEngineEvent {
  /// Records [answer].
  const SubmitAnswerEvent(this.answer);

  /// The submission, carrying the latency adjusted timestamp.
  final AnswerSubmission answer;

  @override
  List<Object?> get props => [answer];
}

/// A player hit the buzzer of a `BuzzerQuestion`.
final class BuzzerPressEvent extends QuizEngineEvent {
  /// Records [press].
  const BuzzerPressEvent(this.press);

  /// The press, carrying the latency adjusted timestamp.
  final BuzzerPress press;

  @override
  List<Object?> get props => [press];
}

/// Closes the buzzer grace window and hands the floor to the fastest press.
///
/// Raised automatically by the engine's grace timer, and manually by the host
/// when they do not want to wait for stragglers.
final class LockBuzzerEvent extends QuizEngineEvent {
  /// Locks the buzzer.
  const LockBuzzerEvent();
}

/// The quizmaster judged the spoken answer of the active player.
final class JudgeBuzzerEvent extends QuizEngineEvent {
  /// Accepts or rejects the answer of the active player.
  const JudgeBuzzerEvent({required this.wasCorrect});

  /// Whether the spoken answer was accepted.
  final bool wasCorrect;

  @override
  List<Object?> get props => [wasCorrect];
}

/// Closes the round, books the points and publishes the solution.
final class RevealRoundEvent extends QuizEngineEvent {
  /// Reveals the round.
  const RevealRoundEvent();
}

/// Clears scores, history and round, keeping players and question bank.
final class ResetGameEvent extends QuizEngineEvent {
  /// Resets the session.
  const ResetGameEvent();
}

/// Takes a revealed question off the stage and returns to the board.
final class CloseRoundEvent extends QuizEngineEvent {
  /// Closes the revealed round.
  const CloseRoundEvent();
}

/// The quizmaster clicked the Jeopardy cell that holds [questionId].
///
/// A Daily Double does not start the round yet: it waits for
/// [PlaceDailyDoubleWagerEvent].
final class SelectJeopardyCellEvent extends QuizEngineEvent {
  /// Picks the cell of [questionId] for the team whose turn it is.
  const SelectJeopardyCellEvent(this.questionId);

  /// Identifier of the question the cell references.
  final String questionId;

  @override
  List<Object?> get props => [questionId];
}

/// Fixes the wager of the pending Daily Double and opens its question.
final class PlaceDailyDoubleWagerEvent extends QuizEngineEvent {
  /// Risks [wager] points.
  const PlaceDailyDoubleWagerEvent(this.wager);

  /// Points the picking team bets.
  final int wager;

  @override
  List<Object?> get props => [wager];
}

/// Hands the next pick to [teamId], overriding the automatic rotation.
final class SetJeopardyTurnEvent extends QuizEngineEvent {
  /// Gives [teamId] the pick.
  const SetJeopardyTurnEvent(this.teamId);

  /// The team that picks next.
  final String teamId;

  @override
  List<Object?> get props => [teamId];
}
