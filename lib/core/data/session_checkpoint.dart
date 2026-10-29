import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/models.dart';
import '../engine/session_access.dart';

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
    this.accessState = const SessionAccessState(),
  });

  static const schemaVersion = 4;
  final SessionAccessState accessState;
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
        'reportRounds': [
          for (final entry in game.reportRounds)
            {...entry.toJson(), 'round': roundReference(entry.round)},
        ],
        'corrections': [
          for (final entry in game.corrections)
            {
              ...entry.toJson(),
              'beforeRound': entry.beforeRound == null
                  ? null
                  : roundReference(entry.beforeRound!),
              'afterRound': entry.afterRound == null
                  ? null
                  : roundReference(entry.afterRound!),
            },
        ],
      },
      'savedAtMicros': savedAtMicros,
      'resumeTokenHashes': resumeTokenHashes,
      'previousJoinUri': previousJoinUri?.toString(),
      'access': accessState.toJson(),
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
        2 => _decodeSnapshot(decoded, quizDocument),
        3 => _decodeSnapshot(decoded, quizDocument),
        4 => _decodeSnapshot(decoded, quizDocument),
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

  static SessionCheckpoint _decodeV1(JsonMap envelope, String quizDocument) =>
      _decodeSnapshot(envelope, quizDocument, legacy: true);

  static SessionCheckpoint _decodeSnapshot(
    JsonMap envelope,
    String quizDocument, {
    bool legacy = false,
  }) {
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
    if (legacy) {
      if (storedGame.containsKey('corrections')) {
        throw const RecoveryException('Unknown legacy recovery fields.');
      }
      storedGame['corrections'] = <Object?>[];
    }
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
      'reportRounds':
          envelope['schemaVersion'] != 4 && storedGame['reportRounds'] == null
          ? <Object?>[]
          : storedGame.readList(
              'reportRounds',
              (entry) => {
                ...entry,
                'round': expandRound(entry.readObject('round')),
              },
            ),
      'corrections': storedGame.readList(
        'corrections',
        (entry) => {
          ...entry,
          'beforeRound': switch (entry.readObjectOrNull('beforeRound')) {
            final round? => expandRound(round),
            null => null,
          },
          'afterRound': switch (entry.readObjectOrNull('afterRound')) {
            final round? => expandRound(round),
            null => null,
          },
        },
      ),
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
      accessState:
          envelope['schemaVersion'] == 3 || envelope['schemaVersion'] == 4
          ? SessionAccessState.fromJson(decoded.readObject('access'))
          : const SessionAccessState(),
      previousJoinUri: switch (decoded.readStringOrNull('previousJoinUri')) {
        null => null,
        final value => Uri.parse(value),
      },
    );
    if (!decoded.containsKey('previousJoinUri') ||
        decoded.length !=
            (envelope['schemaVersion'] == 3 || envelope['schemaVersion'] == 4
                ? 7
                : 6) ||
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
    require(
      !accessState.bannedPlayerIds.any(game.players.containsKey),
      'banned participant in roster.',
    );
    for (final round in [
      game.round,
      ...game.roundHistory,
      ...game.reportRounds.map((entry) => entry.round),
    ]) {
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
    for (final record in game.reportRounds) {
      require(
        record.round.question != null &&
            record.round.startedAtHostMicros != null &&
            record.players.entries.every((e) => e.key == e.value.id) &&
            record.eligiblePlayerIds.every(record.players.containsKey) &&
            record.disconnectedPlayerIds.every(record.players.containsKey) &&
            record.presses.entries.every(
              (e) =>
                  e.key == e.value.playerId &&
                  record.players.containsKey(e.key) &&
                  e.value.questionId == record.round.question?.id,
            ) &&
            record.chips.values.every((v) => v >= 0) &&
            record.wagers.values.every((v) => v >= 0),
        'report participation or chips.',
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
    final corrections = <String, ManualCorrection>{};
    final reversed = <String>{};
    for (final entry in game.corrections) {
      require(
        entry.id.isNotEmpty &&
            !corrections.containsKey(entry.id) &&
            questions.containsKey(entry.questionId) &&
            entry.roundStartedAt > 0 &&
            entry.playerId.isNotEmpty &&
            entry.atHostMicros > 0 &&
            entry.atHostMicros <= game.hostTimeMicros &&
            entry.participantName.isNotEmpty,
        'correction identity or timestamp.',
      );
      final before = entry.beforeValue;
      final after = entry.afterValue;
      final isReversal = entry.reversesId != null;
      final monetary =
          entry.kind == CorrectionKind.points ||
          entry.kind == CorrectionKind.chips;
      require(switch (entry.kind) {
        CorrectionKind.points =>
          before != null &&
              after != null &&
              entry.scoreDeltas.length == 1 &&
              entry.scoreDeltas[entry.playerId] == after - before &&
              after != before &&
              entry.chipDeltas.isEmpty,
        CorrectionKind.chips =>
          before != null &&
              after != null &&
              before >= 0 &&
              after >= 0 &&
              entry.teamId != null &&
              entry.chipDeltas.length == 1 &&
              entry.chipDeltas[entry.teamId] == after - before &&
              after != before &&
              entry.scoreDeltas.isEmpty,
        CorrectionKind.answer =>
          (before == null || before == 0 || before == 1) &&
              (after == 0 || after == 1 || (isReversal && after == null)) &&
              before != after &&
              entry.scoreDeltas.isEmpty &&
              entry.chipDeltas.isEmpty,
        CorrectionKind.buzzer =>
          (before == null || before == 0 || before == 1) &&
              (after == 0 || after == 1 || (isReversal && after == null)) &&
              (isReversal ||
                  (entry.beforeRound?.activePlayerId == entry.playerId &&
                      entry.beforeRound?.status == RoundStatus.locked &&
                      entry.afterRound?.buzzerVerdicts[entry.playerId] ==
                          after)),
      }, 'correction values or effects.');
      require(
        entry.scoreDeltas.keys.every((id) => id.isNotEmpty) &&
            entry.chipDeltas.keys.every((id) => id.isNotEmpty) &&
            ((entry.kind == CorrectionKind.buzzer && !isReversal)
                ? entry.beforeRound != null && entry.afterRound != null
                : entry.beforeRound == null &&
                      entry.afterRound == null &&
                      entry.beforeJeopardy == null &&
                      entry.afterJeopardy == null &&
                      entry.beforePoker == null &&
                      entry.afterPoker == null),
        'correction context.',
      );
      final original = corrections[entry.reversesId];
      require(
        entry.reversesId == null ||
            (original != null &&
                original.reversesId == null &&
                reversed.add(original.id) &&
                entry.kind == original.kind &&
                entry.playerId == original.playerId &&
                entry.teamId == original.teamId &&
                entry.questionId == original.questionId &&
                entry.roundStartedAt == original.roundStartedAt &&
                (monetary ||
                    (before == original.afterValue &&
                        after == original.beforeValue)) &&
                entry.scoreDeltas.length == original.scoreDeltas.length &&
                entry.chipDeltas.length == original.chipDeltas.length &&
                entry.scoreDeltas.entries.every(
                  (e) => e.value == -(original.scoreDeltas[e.key] ?? 0),
                ) &&
                entry.chipDeltas.entries.every(
                  (e) => e.value == -(original.chipDeltas[e.key] ?? 0),
                )),
        'invalid counter-correction.',
      );
      require(
        (entry.beforeRound == null ||
                (entry.beforeRound!.question == questions[entry.questionId] &&
                    entry.beforeRound!.startedAtHostMicros ==
                        entry.roundStartedAt)) &&
            (entry.afterRound == null ||
                entry.afterRound!.question == questions[entry.questionId]),
        'correction round.',
      );
      corrections[entry.id] = entry;
    }
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
