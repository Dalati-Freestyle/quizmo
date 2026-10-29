import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/models.dart';

final class RecoveryException implements Exception {
  const RecoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class RecoveryRecord {
  const RecoveryRecord(this.checkpoint, this.quiz);
  final String checkpoint;
  final String quiz;
  SessionCheckpoint decode() =>
      SessionCheckpoint.decode(checkpoint, quizDocument: quiz);
  bool matches(RecoveryRecord? other) =>
      other != null && checkpoint == other.checkpoint && quiz == other.quiz;
}

final class SessionCheckpoint {
  SessionCheckpoint({
    required this.sessionId,
    required this.quiz,
    required this.game,
    required this.savedAtMicros,
    required this.resumeTokenHashes,
    this.previousJoinUri,
  });

  static const schemaVersion = 1;
  final String sessionId;
  final Quiz quiz;
  final GameState game;
  final int savedAtMicros;
  final Map<String, String> resumeTokenHashes;
  final Uri? previousJoinUri;

  String encode({String? quizDocument, String? quizDigest}) {
    final document = quizDocument ?? jsonEncode(quiz.toJson());
    JsonMap roundReference(RoundState round) => {
      ...round.toJson()..remove('question'),
      'questionId': round.question?.id,
    };
    final payload = jsonEncode({
      'sessionId': sessionId,
      'quizSha256':
          quizDigest ?? sha256.convert(utf8.encode(document)).toString(),
      'game': {
        ...game.toJson()..remove('questionBank'),
        'round': roundReference(game.round),
        'roundHistory': game.roundHistory.map(roundReference).toList(),
      },
      'savedAtMicros': savedAtMicros,
      'resumeTokenHashes': resumeTokenHashes,
      'previousJoinUri': previousJoinUri?.toString(),
    });
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
  }

  static SessionCheckpoint decode(
    String contents, {
    required String quizDocument,
  }) {
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! JsonMap) {
        throw const RecoveryException('Recovery file must be a JSON object.');
      }
      final version = decoded['schemaVersion'];
      if (version is! num || !version.isFinite || version != version.toInt()) {
        throw const RecoveryException(
          'Recovery schemaVersion must be an integer.',
        );
      }
      if (version > schemaVersion) {
        throw const RecoveryException(
          'This recovery file needs a newer Quizmo. Update Quizmo and retry.',
        );
      }
      return switch (version.toInt()) {
        1 => _decodeV1(decoded, quizDocument),
        _ => throw const RecoveryException(
          'Unsupported recovery schemaVersion.',
        ),
      };
    } on RecoveryException {
      rethrow;
    } on QuizSchemaUpdateRequiredException {
      throw const RecoveryException(
        'This recovery file needs a newer Quizmo. Update Quizmo and retry.',
      );
    } on FormatException {
      throw const RecoveryException('Recovery file contains invalid JSON.');
    } on JsonContractException catch (error) {
      throw RecoveryException('Incomplete recovery file: ${error.message}');
    } on QuizValidationException catch (error) {
      throw RecoveryException(
        'Invalid recovery quiz: ${error.messages.join(' ')}',
      );
    }
  }

  static SessionCheckpoint _decodeV1(JsonMap envelope, String quizDocument) {
    if (envelope.length != 3) {
      throw const RecoveryException('Incomplete or unknown recovery fields.');
    }
    final payload = envelope.readString('payload');
    if (sha256.convert(utf8.encode(payload)).toString() !=
        envelope.readString('sha256')) {
      throw const RecoveryException(
        'Recovery checksum failed. The saved game was not changed.',
      );
    }
    final decoded = jsonDecode(payload);
    if (decoded is! JsonMap) {
      throw const RecoveryException('Recovery payload must be a JSON object.');
    }
    if (sha256.convert(utf8.encode(quizDocument)).toString() !=
        decoded.readString('quizSha256')) {
      throw const RecoveryException(
        'Recovery quiz or media is missing or damaged.',
      );
    }
    final quizJson = jsonDecode(quizDocument);
    if (quizJson is! JsonMap) {
      throw const RecoveryException('Invalid saved quiz.');
    }
    final quiz = Quiz.fromJson(quizJson);
    final questions = {for (final q in quiz.questions) q.id: q};
    JsonMap expandRound(JsonMap reference) {
      final id = reference.readStringOrNull('questionId');
      if (!reference.containsKey('questionId') ||
          reference.containsKey('question') ||
          id != null && !questions.containsKey(id)) {
        throw const RecoveryException('Invalid recovery question reference.');
      }
      return {
        ...Map.of(reference)..remove('questionId'),
        'question': questions[id]?.toJson(),
      };
    }

    final storedGame = decoded.readObject('game');
    if (storedGame.containsKey('questionBank')) {
      throw const RecoveryException(
        'Invalid recovery question bank reference.',
      );
    }
    final rawGame = {
      ...storedGame,
      'questionBank': quiz.questions.map((q) => q.toJson()).toList(),
      'round': expandRound(storedGame.readObject('round')),
      'roundHistory': storedGame.readList('roundHistory', expandRound),
    };
    final game = GameState.fromJson(rawGame);
    _requireComplete(rawGame, game.toJson());
    final hashes = readStringMap(decoded, 'resumeTokenHashes');
    final checkpoint = SessionCheckpoint(
      sessionId: decoded.readString('sessionId'),
      quiz: quiz,
      game: game,
      savedAtMicros: decoded.readInt('savedAtMicros'),
      resumeTokenHashes: hashes,
      previousJoinUri: switch (decoded.readStringOrNull('previousJoinUri')) {
        null => null,
        final value => Uri.parse(value),
      },
    );
    if (!decoded.containsKey('previousJoinUri') ||
        decoded.length != 6 ||
        decoded['savedAtMicros'] != checkpoint.savedAtMicros) {
      throw const RecoveryException('Incomplete recovery metadata.');
    }
    checkpoint.validate();
    return checkpoint;
  }

  void validate() {
    void require(bool valid, String message) {
      if (!valid) throw RecoveryException('Invalid recovery state: $message');
    }

    require(
      RegExp(r'^[a-zA-Z0-9_-]{16,80}$').hasMatch(sessionId),
      'session identity.',
    );
    require(savedAtMicros > 0 && game.hostTimeMicros > 0, 'save timestamp.');
    require(
      game.questionBank.length == quiz.questions.length &&
          List.generate(
            quiz.questions.length,
            (index) => game.questionBank[index] == quiz.questions[index],
          ).every((v) => v),
      'question bank does not match the saved quiz.',
    );
    require(
      game.totalQuestionCount == quiz.questions.length,
      'question count.',
    );
    final questions = {for (final q in quiz.questions) q.id: q};
    require(
      game.completedQuestionIds.every(questions.containsKey),
      'completed questions.',
    );
    require(
      game.players.entries.every(
        (e) =>
            e.key == e.value.id &&
            (e.value.teamId == null || game.teams.containsKey(e.value.teamId)),
      ),
      'player or team assignment.',
    );
    require(
      game.teams.entries.every((e) => e.key == e.value.id),
      'team identity.',
    );
    require(
      game.playerOrder.toSet().length == game.playerOrder.length &&
          game.playerOrder.every(game.players.containsKey),
      'player order.',
    );
    require(
      resumeTokenHashes.keys.every(game.players.containsKey) &&
          resumeTokenHashes.values.every(
            (v) => RegExp(r'^[0-9a-f]{64}$').hasMatch(v),
          ),
      'participant credentials.',
    );
    require(
      game.players.keys.every(resumeTokenHashes.containsKey),
      'missing participant credentials.',
    );
    for (final round in [game.round, ...game.roundHistory]) {
      final archived = !identical(round, game.round);
      final q = round.question;
      require(
        (q == null && round.status == RoundStatus.idle) ||
            (q != null && questions[q.id] == q),
        'round question.',
      );
      require(
        round.startedAtHostMicros == null ||
            round.startedAtHostMicros! <= game.hostTimeMicros,
        'round clock.',
      );
      require(
        (round.timerRestartedAtHostMicros == null ||
                round.timerRestartedAtHostMicros! <= game.hostTimeMicros) &&
            round.acceptedElapsedMicros.values.every((v) => v >= 0),
        'timer or accepted answer elapsed time.',
      );
      require(
        round.answers.entries.every(
          (e) =>
              e.key == e.value.playerId &&
              (archived || game.players.containsKey(e.key)) &&
              e.value.questionId == q?.id &&
              (q?.accepts(e.value) ?? false),
        ),
        'accepted answers.',
      );
      require(
        round.buzzerQueue.every(
              (p) =>
                  (archived || game.players.containsKey(p.playerId)) &&
                  p.questionId == q?.id,
            ) &&
            round.buzzerQueue.map((p) => p.playerId).toSet().length ==
                round.buzzerQueue.length,
        'buzzer queue.',
      );
      require(
        archived ||
            round.activePlayerId == null ||
            game.players.containsKey(round.activePlayerId),
        'active player.',
      );
      require(
        (archived ||
                round.lockedOutPlayerIds.every(game.players.containsKey)) &&
            round.answerVerdicts.keys.every(round.answers.containsKey),
        'verdicts.',
      );
    }
    require(
      game.scores.byPlayer.keys.every(game.players.containsKey) &&
          game.scores.history.every(
            (e) =>
                game.players.containsKey(e.playerId) &&
                questions.containsKey(e.questionId),
          ),
      'score history.',
    );
    final totals = <String, int>{};
    for (final entry in game.scores.history) {
      totals[entry.playerId] = (totals[entry.playerId] ?? 0) + entry.points;
    }
    require(
      game.players.keys.every(game.scores.byPlayer.containsKey) &&
          game.scores.byPlayer.entries.every(
            (e) => e.value == (totals[e.key] ?? 0),
          ),
      'score totals do not match score history.',
    );
    switch (quiz.format) {
      case StandardFormat(:final revealMode):
        require(
          game.jeopardy == null &&
              game.poker == null &&
              game.revealMode == revealMode,
          'standard format.',
        );
      case JeopardyFormat(:final board):
        final j = game.jeopardy;
        require(
          j != null && j.board == board && game.poker == null,
          'Jeopardy board.',
        );
        if (j != null) {
          require(
            j.currentTeamId == null ||
                game.participantIds.contains(j.currentTeamId),
            'Jeopardy turn.',
          );
          require(
            [
              j.pendingDailyDoubleId,
              j.pendingPickQuestionId,
            ].whereType<String>().every(board.questionIds.contains),
            'pending Jeopardy cell.',
          );
        }
      case PokerFormat(:final startingChips):
        final poker = game.poker;
        require(
          poker != null &&
              poker.startingChips == startingChips &&
              game.jeopardy == null &&
              game.mode is TeamMode,
          'poker configuration.',
        );
        if (poker != null) {
          require(
            poker.chips.keys.toSet().containsAll(game.teams.keys) &&
                poker.chips.keys.every(game.teams.containsKey) &&
                poker.chips.values.every((v) => v >= 0) &&
                poker.wagers.keys.every(game.teams.containsKey) &&
                poker.wagers.values.every((v) => v >= 0) &&
                poker.settledTeamIds.every(game.teams.containsKey),
            'poker balances.',
          );
        }
    }
  }

  GameState pausedGame() => game.copyWith(
    recoveryPaused: true,
    tvMediaPaused: true,
    players: game.players.map(
      (id, player) => MapEntry(
        id,
        player.copyWith(
          isConnected: false,
          clockOffsetMicros: 0,
          roundTripMicros: 0,
        ),
      ),
    ),
  );

  String exportReport() => const JsonEncoder.withIndent('  ').convert({
    'kind': 'quizmo-private-session-report',
    'schemaVersion': schemaVersion,
    'savedAtMicros': savedAtMicros,
    'quiz': quiz.toJson(),
    'game': game.toJson(),
  });
}

void _requireComplete(Object? actual, Object? canonical) {
  if (canonical is JsonMap) {
    if (actual is! JsonMap || actual.length != canonical.length) {
      throw const RecoveryException('Incomplete or unknown recovery fields.');
    }
    for (final key in canonical.keys) {
      if (!actual.containsKey(key)) {
        throw const RecoveryException('Incomplete recovery fields.');
      }
      _requireComplete(actual[key], canonical[key]);
    }
  } else if (canonical is List) {
    if (actual is! List || actual.length != canonical.length) {
      throw const RecoveryException('Incomplete recovery list.');
    }
    for (var i = 0; i < canonical.length; i++) {
      _requireComplete(actual[i], canonical[i]);
    }
  } else if (actual != canonical) {
    throw const RecoveryException('Invalid or lossy recovery value.');
  }
}
