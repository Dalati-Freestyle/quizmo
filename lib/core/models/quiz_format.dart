/// The playing format of a quiz.
///
/// A format decides *how the question bank is presented and played*; the
/// questions themselves stay ordinary [Question]s. Modelled as a sealed union
/// so every consumer has to handle a newly added format (architecture Rule 2).
library;

import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';

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
    'poker' => PokerFormat(startingChips: json.readInt('startingChips')),
    JeopardyFormat._type => JeopardyFormat(
      JeopardyBoard.fromJson(json.readObject('board')),
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

final class PokerFormat extends QuizFormat {
  const PokerFormat({this.startingChips = 100});
  final int startingChips;
  @override
  String get label => 'Pokerchips';
  @override
  JsonMap toJson() => {'type': 'poker', 'startingChips': startingChips};
  @override
  List<Object?> get props => [startingChips];
}
