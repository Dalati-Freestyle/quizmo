import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/l10n/translations.g.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/settings/locale_cubit.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/common/question_result_view.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

class MemoryLanguageStore implements LanguagePreferenceStore {
  String? value;
  bool fail = false;
  Completer<String?>? pendingRead;
  @override
  Future<String?> read() async =>
      pendingRead == null ? value : pendingRead!.future;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Storage unavailable');
    this.value = value;
  }
}

void main() {
  test(
    'locale resolution respects language order and falls back to English',
    () {
      Locale resolve(List<Locale> locales) => AppLocalizations.resolveLocale(
        locales,
        AppLocalizations.supportedLocales,
      );
      expect(resolve([const Locale('de', 'AT')]), const Locale('de'));
      expect(resolve([const Locale('en', 'US')]), const Locale('en'));
      expect(
        resolve([const Locale('fr'), const Locale('de')]),
        const Locale('de'),
      );
      expect(resolve([const Locale('fr')]), const Locale('en'));
      expect(resolve([]), const Locale('en'));
    },
  );

  test('catalogs match their sources and preserve placeholders', () {
    final placeholder = RegExp(r'\{\d+\}');
    Set<String> tokens(String text) =>
        placeholder.allMatches(text).map((match) => match.group(0)!).toSet();
    expect(germanMessages.keys.toSet(), englishMessages.keys.toSet());
    for (final catalog in {
      'de': germanMessages,
      'en': englishMessages,
    }.entries) {
      final source = jsonDecode(
        File('lib/presentation/l10n/${catalog.key}.json').readAsStringSync(),
      );
      expect(catalog.value, source);
      for (final entry in catalog.value.entries) {
        expect(tokens(entry.value), tokens(entry.key), reason: entry.key);
      }
    }
  });

  test(
    'translates notices and validation without changing argument content',
    () {
      const english = AppLocalizations(Locale('en'));
      const german = AppLocalizations(Locale('de'));
      expect(english.text('Freitext'), 'Short answer');
      expect(german.text('Fixed 300 pts'), 'Fest 300 Punkte');
      expect(english.text('Quiz gestartet.'), 'Quiz started.');
      expect(
        german.text('{0} joined.', ['Host a quiz']),
        'Host a quiz ist beigetreten.',
      );
      expect(
        german.text('Question "Meine Frage" needs a prompt.'),
        'Frage „Meine Frage“ benötigt einen Fragetext.',
      );
      expect(
        english.text(
          'Mindestens eine Textlösung angeben.\nFehlertoleranz muss zwischen 0 und 5 liegen.',
        ),
        'Provide at least one text answer.\nTypo tolerance must be between 0 and 5.',
      );
      expect(english.text('Unknown custom message'), 'Unknown custom message');
    },
  );

  test('persists language and reset to system across controllers', () async {
    final store = MemoryLanguageStore();
    final first = LocaleCubit(store: store);
    await first.select(LanguagePreference.de);
    await first.close();
    final second = LocaleCubit(store: store);
    await second.load();
    expect(second.state.preference, LanguagePreference.de);
    await second.select(LanguagePreference.system);
    expect(store.value, 'system');
    expect(second.state.preference.locale, isNull);
    await second.close();
  });

  test('late loading cannot overwrite a manual choice', () async {
    final store = MemoryLanguageStore()..pendingRead = Completer<String?>();
    final cubit = LocaleCubit(store: store);
    final loading = cubit.load();
    await cubit.select(LanguagePreference.en);
    store.pendingRead!.complete('de');
    await loading;
    expect(cubit.state.preference, LanguagePreference.en);
    await cubit.close();
  });

  test(
    'saving recovers after storage failure and keeps the latest choice',
    () async {
      final store = MemoryLanguageStore()..fail = true;
      final cubit = LocaleCubit(store: store);
      await cubit.select(LanguagePreference.de);
      expect(cubit.state.error, isNotNull);
      store.fail = false;
      await Future.wait([
        cubit.select(LanguagePreference.en),
        cubit.select(LanguagePreference.system),
      ]);
      expect(store.value, 'system');
      expect(cubit.state.error, isNull);
      await cubit.close();
    },
  );

  testWidgets(
    'host results localize labels while preserving written solutions',
    (tester) async {
      const question = ShortAnswerQuestion(
        id: 'q',
        prompt: 'Meine Frage',
        acceptedAnswers: ['Wahr'],
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: QuestionResultView(
              question: question,
              game: GameState(),
              host: true,
            ),
          ),
        ),
      );
      expect(find.text('Short answer'), findsOneWidget);
      expect(find.text('Solution: Wahr'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV translates controls and preserves prompts and answer choices',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const question = MultipleChoiceQuestion(
        id: 'q',
        prompt: 'Host a quiz',
        options: [
          AnswerOption(id: 'a', label: 'Wahr'),
          AnswerOption(id: 'b', label: 'Settings'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: TvScreen(
              state: SpectatorSessionState(
                status: QuizClientStatus.connected,
                snapshotReceivedAt: DateTime.now(),
                game: const GameState(
                  round: RoundState(
                    question: question,
                    status: RoundStatus.acceptingAnswers,
                  ),
                ),
              ),
              joinUri: Uri.parse('http://localhost:8080'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(germanMessages['OPEN']!), findsOneWidget);
      expect(find.text('Host a quiz'), findsOneWidget);
      expect(find.text('Wahr'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'uses browser/system language, switches live and preserves player form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.localesTestValue = [const Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final cubit = LocaleCubit(store: MemoryLanguageStore());
      addTearDown(cubit.close);
      await tester.pumpWidget(QuizmoApp(localeCubit: cubit));
      await tester.pumpAndSettle();
      expect(find.text(germanMessages['Host a quiz']!), findsOneWidget);
      await tester.tap(find.text(germanMessages['Open player view']!));
      await tester.pumpAndSettle();
      final nameField = find.widgetWithText(
        TextFormField,
        germanMessages['Your name']!,
      );
      await tester.enterText(nameField, 'Wahr / Falsch');
      await tester.tap(find.byTooltip('Einstellungen'));
      await tester.pumpAndSettle();
      expect(find.text('Erweiterte Einstellungen'), findsOneWidget);
      expect(find.text('Beispielquizzes neu erstellen'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Advanced settings'), findsOneWidget);
      expect(find.text('Recreate example quizzes'), findsOneWidget);
      expect(cubit.state.preference, LanguagePreference.en);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Wahr / Falsch'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('System language'));
      await tester.pumpAndSettle();
      expect(find.text('Einstellungen'), findsOneWidget);
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'GB')];
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
