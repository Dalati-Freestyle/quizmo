import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../engine/quiz_engine_bloc.dart';
import '../models/models.dart';
import 'session_checkpoint.dart';

abstract interface class SessionRecoveryStore {
  Future<RecoveryRecord?> read();
  Future<void> acquire();
  Future<void> write(String contents, String quizDocument);
  Future<void> delete();
  Future<void> release();
}

String newRecoveryId() =>
    base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');

String hashResumeToken(String token) =>
    sha256.convert(utf8.encode(token)).toString();

final class SessionRecovery {
  SessionRecovery({
    required this.engine,
    required this.quiz,
    required this.store,
    this.previousJoinUri,
    this.interval = const Duration(seconds: 1),
    this.restored,
  });

  final QuizEngineBloc engine;
  final Quiz quiz;
  final SessionRecoveryStore store;
  final Duration interval;
  final SessionCheckpoint? restored;
  Uri? previousJoinUri;
  final _errors = StreamController<RecoveryException>.broadcast();
  Stream<RecoveryException> get errors => _errors.stream;
  StreamSubscription<QuizEngineState>? _subscription;
  Timer? _timer;
  Future<void> _tail = Future.value();
  bool _closed = false;
  bool _ownsStore = false;
  SessionCheckpoint? _pending;
  bool _writing = false;
  RecoveryException? lastError;
  int? lastSavedAtMicros;
  Future<void>? _closing;
  late final String _quizDocument = jsonEncode(quiz.toJson());
  late final String _quizDigest = sha256
      .convert(utf8.encode(_quizDocument))
      .toString();

  Future<void> start() async {
    if (_closed) throw const RecoveryException('Recovery is closed.');
    await store.acquire();
    _ownsStore = true;
    try {
      if (_closed) throw const RecoveryException('Recovery is closed.');
      final contents = await store.read();
      if (contents != null) {
        final current = contents.decode();
        if (restored == null || current.encode() != restored!.encode()) {
          throw const RecoveryException(
            'A saved game already exists or changed. Reopen recovery before hosting.',
          );
        }
      } else if (restored != null) {
        throw const RecoveryException(
          'The saved game was removed. Reopen recovery.',
        );
      }
    } on Object {
      _ownsStore = false;
      await store.release();
      rethrow;
    }
    engine.persistRecovery = checkpoint;
    _subscription = engine.stream.listen((state) {
      if (state.game.players.keys.every(engine.resumeTokenHashes.containsKey)) {
        unawaited(_saveAutomatically());
      }
    });
    _timer = Timer.periodic(interval, (_) {
      if (engine.state.game.round.status.acceptsInput &&
          !engine.state.game.recoveryPaused) {
        unawaited(_saveAutomatically());
      }
    });
    try {
      await checkpoint();
    } on Object {
      await close();
      rethrow;
    }
  }

  Future<void> _saveAutomatically() async {
    try {
      await checkpoint();
    } on RecoveryException {
      // checkpoint publishes a visible error; the last durable file is kept.
    }
  }

  Future<void> checkpoint() {
    if (_closed) {
      return Future.error(const RecoveryException('Recovery is closed.'));
    }
    final game = engine.state.game;
    _pending = SessionCheckpoint(
      sessionId: engine.recoverySessionId!,
      quiz: quiz,
      game: game.copyWith(hostTimeMicros: engine.hostNowMicros),
      savedAtMicros: DateTime.now().microsecondsSinceEpoch,
      resumeTokenHashes: {
        for (final id in game.players.keys) id: ?engine.resumeTokenHashes[id],
      },
      previousJoinUri: previousJoinUri,
    );
    if (!_writing) {
      _writing = true;
      _tail = _drain();
    }
    return _tail;
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final snapshot = _pending!;
        _pending = null;
        snapshot.validate();
        await store.write(
          snapshot.encode(quizDocument: _quizDocument, quizDigest: _quizDigest),
          _quizDocument,
        );
        engine.committedRecoveryGame = snapshot.game;
        lastSavedAtMicros = snapshot.savedAtMicros;
        lastError = null;
      }
    } on Object catch (cause) {
      final error = cause is RecoveryException
          ? cause
          : const RecoveryException(
              'Recovery could not be saved. Check free space and storage permissions; '
              'the last successful save is retained. Retry before continuing.',
            );
      lastError = error;
      _errors.add(error);
      if (!engine.isClosed && !engine.state.game.recoveryPaused && !_closed) {
        engine.add(const PauseForRecoveryEvent());
      }
      throw error;
    } finally {
      _writing = false;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    if (_ownsStore) engine.persistRecovery = null;
    try {
      await _tail;
    } on RecoveryException {
      // The error has already been surfaced and must not prevent lease release.
    }
    if (_ownsStore) {
      _ownsStore = false;
      await store.release();
    }
    await _errors.close();
  }
}
