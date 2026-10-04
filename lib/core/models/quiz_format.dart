/// The playing format of a quiz.
///
/// A format decides *how the question bank is presented and played*; the
/// questions themselves stay ordinary [Question]s. Modelled as a sealed union
/// so every consumer has to handle a newly added format (architecture Rule 2).
library;

import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';

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
    StandardFormat._type => const StandardFormat(),
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
  const StandardFormat();

  static const String _type = 'standard';

  @override
  String get label => 'Standard';

  @override
  JsonMap toJson() => const {'type': _type};

  @override
  List<Object?> get props => const [];
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
