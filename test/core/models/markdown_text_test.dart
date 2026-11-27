import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

bool plainLook(String source) => markdownRuns(source).every(
  (run) =>
      !run.style.bold &&
      !run.style.italic &&
      !run.style.strike &&
      !run.style.code &&
      !run.style.quote &&
      run.style.heading == 0 &&
      run.style.link == null,
);

String norm(String text) => text
    .replaceAll(RegExp(r'[ \t]+(?=\n|$)'), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceAll(RegExp(r'^\n+|\n+$'), '')
    .replaceAll('\u00a0', ' ');

void main() {
  test('plain text of every supported element', () {
    expect(
      markdownToPlain('**fett** *kursiv* ~~weg~~ `x`'),
      'fett kursiv weg x',
    );
    expect(markdownToPlain('# Titel\nText'), 'Titel\n\nText');
    expect(markdownToPlain('- a\n- b\n  - c'), '• a\n• b\n   • c');
    expect(markdownToPlain('3. x\n4. y'), '3. x\n4. y');
    expect(markdownToPlain('> zitat'), 'zitat');
    expect(markdownToPlain('```\nblock\n```'), 'block');
    expect(markdownToPlain('a\n\n---\n\nb'), 'a\n\n———\n\nb');
    expect(markdownToPlain('[Link](https://x.de)'), 'Link');
    expect(markdownToPlain(r'\*kein\*'), '*kein*');
    // A single line break stays.
    expect(markdownToPlain('Zeile 1\nZeile 2'), 'Zeile 1\nZeile 2');
    // HTML and pictures are text.
    expect(markdownToPlain('<b>x</b>'), '<b>x</b>');
    expect(markdownToPlain('![Bild](x.png)'), '![Bild](x.png)');
    // Incomplete syntax never fails.
    for (final broken in ['*', '**x', '[', '```', '> ', '#', '1.', '~~']) {
      expect(() => markdownToPlain(broken), returnsNormally, reason: broken);
    }
    expect(isBlankMarkdown('  \n \n'), isTrue);
    expect(isBlankMarkdown('***'), isFalse, reason: 'a rule is visible');
    expect(isBlankMarkdown('**x**'), isFalse);
  });

  test('only http and https links may be opened', () {
    expect(isOpenableLink('https://quizmo.app'), isTrue);
    expect(isOpenableLink('http://x.de/a'), isTrue);
    for (final bad in [
      'javascript:alert(1)',
      'file:///etc',
      'mailto:a@b.c',
      '/x',
      '',
    ]) {
      expect(isOpenableLink(bad), isFalse, reason: bad);
    }
  });

  test('escaped text of older quizzes looks exactly as before', () {
    const samples = [
      '# 1 Frage: Was ist 5 * 3 * 2?',
      '- kein Punkt\n+ auch keiner\n1. Platz\n2) Zweiter',
      '**nicht fett** _nicht kursiv_ ~~bleibt~~',
      '> kein Zitat',
      '`kein Code` und ```auch keiner```',
      '---',
      '===\nText\n---',
      '[kein Link](https://x.de) <https://x.de>',
      '&amp; &lt;b&gt; <b>html</b>',
      '    eingerückt',
      r'C:\Users\Quiz\*',
      '5 * 3 = 15, a_b_c, 2 < 3 > 1',
      '![kein Bild](x.png)',
      'Zeile 1\nZeile 2\n\n\nZeile 3',
    ];
    final random = Random(7);
    const alphabet =
        r'ab *_~`#>-+=1.)[](!<>&\ '
        '\n';
    final fuzz = [
      for (var i = 0; i < 300; i++)
        String.fromCharCodes([
          for (var j = 0; j < 1 + random.nextInt(24); j++)
            alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ]),
    ];
    for (final text in [...samples, ...fuzz]) {
      final escaped = escapeMarkdown(text);
      expect(plainLook(escaped), isTrue, reason: '"$text" -> "$escaped"');
      expect(
        norm(markdownToPlain(escaped)),
        norm(text),
        reason: '"$text" -> "$escaped"',
      );
    }
    // Text without effective Markdown stays untouched.
    for (final text in [
      'Wer war 1990 Weltmeister?',
      '5 * 3',
      'a_b_c',
      '1. Platz',
    ]) {
      expect(escapeMarkdown(text), text);
    }
  });

  group('schema 14', () {
    final source = File(
      p.join('test', 'fixtures', 'quiz_v14_with_media.quizmo.json'),
    ).readAsStringSync();
    final original = jsonDecode(source) as JsonMap;

    test('imports with escaped texts that look as before', () {
      final quiz = parseQuizImport(source);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      final question = quiz.questions.first;
      final raw = (original['questions'] as List).first as JsonMap;
      for (final (shown, before) in [
        (question.prompt, raw['prompt'] as String),
        (question.adminNotes, raw['adminNotes'] as String),
        (question.hints.single.text, (raw['hints'] as List).single['text']),
      ]) {
        expect(plainLook(shown), isTrue, reason: shown);
        expect(norm(markdownToPlain(shown)), norm(before as String));
      }
      if (quiz.slides.isNotEmpty) {
        expect(
          norm(markdownToPlain(quiz.slides.first.text)),
          norm(
            ((original['slides'] as List).first as JsonMap)['text'] as String,
          ),
        );
      }
      expect(
        (quiz.questions.last as EstimationQuestion).maxAccepted,
        340,
        reason: 'the tolerance of schema 14 stays',
      );
      expect(quiz.questions.first.media.single.asset!.bytes, isNotEmpty);
      // Export and import again keep the Markdown text unchanged.
      expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);
    });

    test('schema 15 keeps Markdown as it is', () {
      final json = {...original, 'schemaVersion': 15};
      final quiz = Quiz.fromJson(json);
      expect(
        quiz.questions.first.prompt,
        ((original['questions'] as List).first as JsonMap)['prompt'],
      );
    });

    test('reports get plain text', () async {
      final quiz = Quiz.fromJson({...original, 'schemaVersion': 15});
      final engine = QuizEngineBloc(questionBank: quiz.questions);
      addTearDown(engine.close);
      engine
        ..add(const PlayerJoinedEvent(Player(id: 'p', name: 'P')))
        ..add(StartRoundEvent(quiz.questions.first.id))
        ..add(const RevealRoundEvent());
      await pumpEventQueue();
      final csv = SessionReport.fromGame(engine.state.game, title: 'x').toCsv();
      expect(csv, contains('1 Frage: Was ist 5'));
      expect(csv, isNot(contains('# 1 Frage')));
    });
  });
}
