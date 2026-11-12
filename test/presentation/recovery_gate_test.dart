import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/host_dashboard_page.dart';
import 'package:quizmo/presentation/quizmaster/recovery/recovery_gate.dart';

import '../helpers/memory_recovery_store.dart';

RecoveryRecord _record() {
  const question = TrueFalseQuestion(
    id: 'q',
    prompt: 'True?',
    correctAnswer: true,
  );
  final quiz = Quiz(
    id: 'quiz',
    name: 'Interrupted game',
    description: 'Test',
    category: 'Test',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    questions: const [question],
  );
  final saved = SessionCheckpoint(
    sessionId: 'session-recovery-12345',
    quiz: quiz,
    savedAtMicros: 1700000000000000,
    resumeTokenHashes: const {},
    game: const GameState(
      questionBank: [question],
      totalQuestionCount: 1,
      hostTimeMicros: 1700000000000000,
      round: RoundState(
        question: question,
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: 1699999998000000,
      ),
    ),
  );
  return RecoveryRecord(saved.encode(), jsonEncode(quiz.toJson()));
}

void main() {
  testWidgets(
    'requires explicit resume, export or discard without creating an engine',
    (tester) async {
      final store = MemoryRecoveryStore()..record = _record();
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryGate(store: store, child: const Text('New game menu')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue saved game'), findsOneWidget);
      expect(find.text('Export private session report'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('New game menu'), findsNothing);
      expect(find.byType(HostDashboardPage), findsNothing);
      expect(store.locked, isFalse);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.record, isNotNull);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();
      expect(store.record, isNull);
      expect(find.text('New game menu'), findsOneWidget);
    },
  );

  testWidgets(
    'loads paused, shows three timer choices and returns to explicit recovery',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryRecoveryStore()..record = _record();
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryGate(store: store, child: const Text('New game menu')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue saved game'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with saved time'), findsOneWidget);
      expect(find.text('Restart the full timer'), findsOneWidget);
      expect(find.text('Continue with a soft timer'), findsOneWidget);
      final engine = tester
          .element(find.byType(Scaffold).last)
          .read<QuizEngineBloc>();
      expect(engine.state.game.recoveryPaused, isTrue);
      expect(
        engine.state.game.round.elapsedAt(engine.hostNowMicros),
        const Duration(seconds: 2),
      );
      await tester.tap(find.text('Continue with a soft timer'));
      await tester.pumpAndSettle();
      expect(engine.state.game.recoveryPaused, isFalse);
      expect(engine.state.game.round.hasSoftTimer, isTrue);
      await tester.pageBack();
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && store.locked; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      await tester.pumpAndSettle();
      expect(store.locked, isFalse);
      expect(find.text('Continue saved game'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'corrupt record is visible and cannot resume or overwrite itself',
    (tester) async {
      final record = const RecoveryRecord('broken json', '{}');
      final store = MemoryRecoveryStore()..record = record;
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryGate(store: store, child: const Text('New game menu')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recovery file contains invalid JSON.'), findsOneWidget);
      expect(find.text('Continue saved game'), findsNothing);
      expect(find.text('New game menu'), findsNothing);
      expect(store.record, same(record));
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'failed duplicate continuation never releases the live host lease',
    (tester) async {
      final store = MemoryRecoveryStore()..record = _record();
      await store.acquire();
      await tester.pumpWidget(
        MaterialApp(
          home: HostDashboardPage(
            quiz: store.record!.decode().quiz,
            checkpoint: store.record!.decode(),
            recoveryStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Another host holds recovery.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(store.locked, isTrue);
      await store.release();
    },
  );
}
