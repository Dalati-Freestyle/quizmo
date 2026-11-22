/// The playing format of a quiz.
///
/// A format decides *how the question bank is presented and played*; the
/// questions themselves stay ordinary [Question]s. Modelled as a sealed union
/// so every consumer has to handle a newly added format (architecture Rule 2).
library;

import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';
import 'snowflake.dart';

/// When standard quizzes publish solutions, verdicts and standings to guests.
enum SolutionRevealMode {
  afterEachQuestion,
  atEnd;

  /// Restores the mode from its serialized name.
  static SolutionRevealMode fromName(String name) =>
      SolutionRevealMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => throw JsonContractException(
          'Unknown solution reveal mode "$name".',
        ),
      );
}

/// Base type of every quiz format.
sealed class QuizFormat extends Equatable {
  /// Const constructor for the sealed hierarchy.
  const QuizFormat();

  /// Short label shown in the quiz library and the editor.
  String get label;

  /// Serializes the format including its configuration.
  JsonMap toJson();

  /// Restores a format from [json].
  ///
  /// Deserialization boundary: the only place that maps wire tags to types.
  static QuizFormat fromJson(JsonMap json) => switch (json.readString('type')) {
    StandardFormat._type => StandardFormat(
      revealMode: SolutionRevealMode.fromName(
        json.readStringOrNull('revealMode') ?? 'afterEachQuestion',
      ),
    ),
    PokerFormat._type => PokerFormat(
      startingChips: json.readInt('startingChips'),
      minStake: json.readIntOrNull('minStake') ?? 0,
      maxStake: json.readIntOrNull('maxStake'),
    ),
    JeopardyFormat._type => JeopardyFormat(
      JeopardyBoard.fromJson(json.readObject('board')),
    ),
    SnowflakeFormat._type => SnowflakeFormat(
      scoring: SnowflakeScoring.fromName(json.readString('scoring')),
    ),
    final unknown => throw JsonContractException(
      'Unknown quiz format "$unknown".',
    ),
  };
}

/// A plain, ordered list of questions played one after the other.
final class StandardFormat extends QuizFormat {
  /// Creates the standard format.
  const StandardFormat({
    this.revealMode = SolutionRevealMode.afterEachQuestion,
  });

  /// Timing of public solutions and score feedback.
  final SolutionRevealMode revealMode;

  static const String _type = 'standard';

  @override
  String get label => 'Standard';

  @override
  JsonMap toJson() => {'type': _type, 'revealMode': revealMode.name};

  @override
  List<Object?> get props => [revealMode];
}

/// A board of categories and point levels; the teams pick the cells.
final class JeopardyFormat extends QuizFormat {
  /// Creates a Jeopardy format playing on [board].
  const JeopardyFormat(this.board);

  static const String _type = 'jeopardy';

  /// Layout and rules of the board.
  final JeopardyBoard board;

  @override
  String get label => 'Jeopardy';

  @override
  JsonMap toJson() => {'type': _type, 'board': board.toJson()};

  @override
  List<Object?> get props => [board];
}

/// Every team bets chips on each question; a correct answer doubles them.
final class PokerFormat extends QuizFormat {
  /// Creates the poker format.
  const PokerFormat({
    this.startingChips = 100,
    this.minStake = 0,
    this.maxStake,
  });

  static const String _type = 'poker';

  /// Chips every team starts with.
  final int startingChips;

  /// Smallest stake per question (schema 12). 0 lets teams sit out; a team
  /// with fewer chips than this has to go all-in.
  final int minStake;

  /// Largest stake per question (schema 12), `null` for no limit.
  final int? maxStake;

  @override
  String get label => 'Pokerchips';

  @override
  JsonMap toJson() => {
    'type': _type,
    'startingChips': startingChips,
    'minStake': minStake,
    if (maxStake != null) 'maxStake': maxStake,
  };

  @override
  List<Object?> get props => [startingChips, minStake, maxStake];
}

/// "Biggest Snowflake": no answer is stored as correct; the rarest answer of
/// each round wins (supported from quiz schema 10 on).
///
/// Only question kinds with a finite, deterministic answer set can be played
/// (`Question.supportsUniqueness`).
final class SnowflakeFormat extends QuizFormat {
  /// Creates the format with its [scoring] rule.
  const SnowflakeFormat({this.scoring = SnowflakeScoring.winnerOnly});

  static const String _type = 'snowflake';

  /// Whether only the rarest answer scores or the points are graded.
  final SnowflakeScoring scoring;

  @override
  String get label => 'Biggest Snowflake';

  @override
  JsonMap toJson() => {'type': _type, 'scoring': scoring.name};

  @override
  List<Object?> get props => [scoring];
}
