/// Output state of the [QuizEngineBloc].
library;

import 'package:equatable/equatable.dart';

import '../models/models.dart';

const Object _unset = Object();

/// The state exposed by the engine.
///
/// [game] is the serializable domain snapshot that also travels over the wire;
/// [notice] is a transient, host-only hint ("Buzz ignored: round is locked")
/// that must never be persisted or broadcast.
final class QuizEngineState extends Equatable {
  /// Creates an engine state.
  const QuizEngineState({this.game = const GameState(), this.notice});

  /// The authoritative session snapshot.
  final GameState game;

  /// Last diagnostic message produced by a rejected or notable transition.
  final String? notice;

  /// Lifecycle position of the round on stage.
  RoundStatus get roundStatus => game.round.status;

  /// The question on stage, if any.
  Question? get currentQuestion => game.round.question;

  /// Whether the host may open a new round right now.
  bool get canStartRound =>
      roundStatus == RoundStatus.idle || roundStatus == RoundStatus.revealed;

  /// Returns a copy with the given fields replaced.
  QuizEngineState copyWith({GameState? game, Object? notice = _unset}) =>
      QuizEngineState(
        game: game ?? this.game,
        notice: identical(notice, _unset) ? this.notice : notice as String?,
      );

  @override
  List<Object?> get props => [game, notice];
}
