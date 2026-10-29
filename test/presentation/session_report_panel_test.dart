import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/session_report_panel.dart';

void main() {
  const game = GameState(
    isFinished: true,
    completedQuestionIds: {'q'},
    players: {'p': Player(id: 'p', name: 'Änne', isConnected: false)},
    scores: ScoreState(byPlayer: {'p': 42}),
  );
  Widget app(GameState state, Future<bool> Function(SessionReport) save) =>
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SessionReportPanel(
              game: state,
              quizName: 'Schulquiz',
              saveCsv: save,
            ),
          ),
        ),
      );

  testWidgets(
    'localized final report exports current authoritative totals and warns about old saves',
    (tester) async {
      SessionReport? exported;
      Future<bool> save(SessionReport report) async {
        exported = report;
        return true;
      }

      await tester.pumpWidget(app(game, save));
      await tester.tap(find.text('Abschlussbericht'));
      await tester.pumpAndSettle();
      expect(find.text('42 Punkte'), findsOneWidget);
      expect(
        find.textContaining('Der Detailverlauf ist unvollständig'),
        findsOneWidget,
      );
      expect(find.textContaining('Am Ende getrennt'), findsOneWidget);
      final corrected = game.copyWith(
        scores: const ScoreState(byPlayer: {'p': 49}),
      );
      await tester.pumpWidget(app(corrected, save));
      await tester.pumpAndSettle();
      expect(find.text('49 Punkte'), findsOneWidget);
      await tester.ensureVisible(find.text('CSV-Export'));
      await tester.tap(find.text('CSV-Export'));
      await tester.pumpAndSettle();
      expect(exported!.summaries.single.finalScore, 49);
      expect(exported!.title, 'Schulquiz');
      expect(find.text('Bericht exportiert.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'export errors are visible and cancellation never claims success',
    (tester) async {
      var fail = true;
      await tester.pumpWidget(
        app(game, (_) async {
          if (fail) throw Exception('disk full');
          return false;
        }),
      );
      await tester.tap(find.text('Abschlussbericht'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('CSV-Export'));
      await tester.tap(find.text('CSV-Export'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CSV-Export fehlgeschlagen'), findsOneWidget);
      expect(find.text('Bericht exportiert.'), findsNothing);
      fail = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('CSV-Export'));
      await tester.pumpAndSettle();
      expect(find.text('Bericht exportiert.'), findsNothing);
    },
  );
}
