/// Unit tests for standalone quiz import and export.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final quiz = Quiz(
    id: 'quiz-import',
    name: 'Importable quiz',
    description: 'For import tests.',
    category: 'Testing',
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
    questions: const [
      MultipleChoiceQuestion(
        id: 'question-1',
        prompt: 'Choose the valid option.',
        options: [
          AnswerOption(id: 'a', label: 'A'),
          AnswerOption(id: 'b', label: 'B'),
        ],
        correctOptionId: 'a',
        scoringRule: FixedPointsRule(),
      ),
    ],
  );

  test('imports a valid file and exports readable JSON', () async {
    final repository = InMemoryQuizRepository();
    final contents = exportQuizJson(quiz);

    final imported = await importQuiz(
      contents: contents,
      repository: repository,
      createId: () => 'unused',
    );

    expect(imported, quiz);
    expect(await repository.loadAll(), [quiz]);
    expect(contents, contains('\n  "schemaVersion": 2'));
  });

  test('rejects malformed JSON', () {
    expect(
      () => parseQuizImport('{not valid JSON'),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('not valid JSON'),
        ),
      ),
    );
  });

  test('rejects an unknown question type', () {
    final json = _jsonFor(quiz)
      ..['questions'] = [
        {...quiz.questions.single.toJson(), 'type': 'futureUnknownType'},
      ];

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('Unknown question type "futureUnknownType"'),
        ),
      ),
    );
  });

  test('rejects an unknown scoring rule', () {
    final json = _jsonFor(quiz)
      ..['questions'] = [
        {
          ...quiz.questions.single.toJson(),
          'scoringRule': {'type': 'mystery'},
        },
      ];

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('Unknown scoring rule "mystery"'),
        ),
      ),
    );
  });

  test('rejects an MC question without a valid correct option', () {
    final json = _jsonFor(quiz)
      ..['questions'] = [
        {
          ...quiz.questions.single.toJson(),
          'correctOptionId': 'missing-option',
        },
      ];

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('correctOptionId'),
        ),
      ),
    );
  });

  test('rejects an unsupported schema version', () {
    final json = _jsonFor(quiz)..['schemaVersion'] = 999;

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported quiz schemaVersion 999'),
        ),
      ),
    );
  });

  test('assigns a new ID instead of overwriting an existing quiz', () async {
    final repository = InMemoryQuizRepository([quiz]);

    final imported = await importQuiz(
      contents: exportQuizJson(quiz),
      repository: repository,
      createId: () => 'quiz-import-copy',
      now: () => DateTime.utc(2026, 9, 20),
    );

    expect(imported.id, 'quiz-import-copy');
    expect((await repository.loadAll()).map((item) => item.id), [
      'quiz-import',
      'quiz-import-copy',
    ]);
  });

  group('version compatibility', () {
    test('newer schemas request an update before decoding content', () async {
      final repository = InMemoryQuizRepository([quiz]);
      final json = {
        'schemaVersion': Quiz.currentSchemaVersion + 1,
        'questions': [
          {'type': 'unknownFutureQuestion'},
        ],
      };
      await expectLater(
        importQuiz(
          contents: jsonEncode(json),
          repository: repository,
          createId: () => 'unused',
        ),
        throwsA(
          isA<QuizImportUpdateRequiredException>()
              .having(
                (error) => error.requiredSchemaVersion,
                'requiredSchemaVersion',
                Quiz.currentSchemaVersion + 1,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Update Quizmo'),
              ),
        ),
      );
      expect(await repository.loadAll(), [quiz]);
    });

    test('invalid versions do not request an app update', () {
      for (final version in [null, '2', 1.5, 0, -1]) {
        expect(
          () => parseQuizImport(jsonEncode({'schemaVersion': version})),
          throwsA(
            isA<QuizImportException>().having(
              (error) => error is QuizImportUpdateRequiredException,
              'requiresUpdate',
              isFalse,
            ),
          ),
        );
      }
    });

    test('imports a fixed pre-media version 1 fixture', () {
      final restored = parseQuizImport(
        File('test/fixtures/quiz_v1_before_media.quizmo.json')
            .readAsStringSync(),
      );
      expect(restored.schemaVersion, Quiz.currentSchemaVersion);
      expect(restored.format, const StandardFormat());
      expect(restored.teams.single.name, 'Red');
      expect(restored.questions.every((q) => q.media.isEmpty), isTrue);
      expect(restored.questions.every((q) => q.solutionMedia.isEmpty), isTrue);
      expect((restored.questions.last as BuzzerQuestion).lockOutOnMiss, isTrue);
      expect(parseQuizImport(exportQuizJson(restored)), restored);
    });

    for (final version in [null, '1', 1.5, 0, -1, 999]) {
      test(
        'rejects invalid version $version without changing storage',
        () async {
          final repository = InMemoryQuizRepository([quiz]);
          final json = quiz.toJson()..['schemaVersion'] = version;
          if (version == null) json.remove('schemaVersion');
          await expectLater(
            importQuiz(
              contents: jsonEncode(json),
              repository: repository,
              createId: () => 'new',
            ),
            throwsA(isA<QuizImportException>()),
          );
          expect(await repository.loadAll(), [quiz]);
        },
      );
    }
  });

  group('portable multimedia', () {
    final image = MediaAsset.upload(
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1]),
      'png',
    );
    final audio = MediaAsset.upload(Uint8List.fromList([73, 68, 51, 1]), 'mp3');
    final video = MediaAsset.upload(
      Uint8List.fromList([0, 0, 0, 12, 102, 116, 121, 112, 1]),
      'mp4',
    );
    final media = <MediaAttachment>[
      ImageAttachment(asset: image, caption: 'Image', zoom: false),
      AudioAttachment(asset: audio, playbackLimitSeconds: 5),
      VideoAttachment(asset: video),
      const VideoAttachment(youtubeId: 'dQw4w9WgXcQ'),
      const CodeAttachment(code: 'print("hello");', language: 'dart'),
      const GeoAttachment(latitude: 52.52, longitude: 13.405, zoom: 10),
    ];
    final withMedia = quiz.copyWith(
      teams: const [Team(id: 'red', name: 'Red', colorValue: 0xFFFF0000)],
      questions: [
        Question.fromJson({
          ...quiz.questions.single.toJson(),
          'media': media.map((m) => m.toJson()).toList(),
          'solutionMedia': [ImageAttachment(asset: image).toJson()],
        }),
      ],
    );

    test(
      'hidden media details survive export and are removed from snapshots',
      () {
        final source = withMedia.copyWith(
          questions: [
            Question.fromJson({
              ...withMedia.questions.single.toJson(),
              'media': media
                  .map((m) => m.withHiddenDetails(true).toJson())
                  .toList(),
              'solutionMedia': [
                ImageAttachment(
                  asset: image,
                  caption: 'secret-solution.png',
                  hideDetails: true,
                ).toJson(),
              ],
            }),
          ],
        );
        final restored = parseQuizImport(exportQuizJson(source));
        expect(restored, source);
        final hidden = restored.questions.single.forWire(reveal: false);
        expect(hidden.solutionMedia, isEmpty);
        expect(
          hidden.media.every((m) => m.hideDetails && m.caption.isEmpty),
          isTrue,
        );
        expect(
          hidden.media
              .where((m) => m.asset != null)
              .every((m) => m.asset!.data == null),
          isTrue,
        );
        final revealed = restored.questions.single.forWire(reveal: true);
        expect(revealed.solutionMedia.single.caption, isEmpty);
        expect(source.questions.single.media.first.caption, 'Image');
        expect(
          source.questions.single.solutionMedia.single.caption,
          'secret-solution.png',
        );
      },
    );

    test(
      'fixed version 1 media fixture migrates with all bytes and solutions',
      () {
        final restored = parseQuizImport(
          File('test/fixtures/quiz_v1_with_media.quizmo.json')
              .readAsStringSync(),
        );
        expect(restored.schemaVersion, Quiz.currentSchemaVersion);
        expect(restored.questions.first.media.single.caption, 'legacy.png');
        expect(restored.questions.first.media.single.hideDetails, isFalse);
        expect(restored.questions.first.media.single.asset!.bytes, image.bytes);
        expect(
          restored.questions.first.solutionMedia.single.asset!.bytes,
          audio.bytes,
        );
        expect(
          restored.questions.first.solutionMedia.single.hideDetails,
          isFalse,
        );
        expect(parseQuizImport(exportQuizJson(restored)), restored);
      },
    );

    for (final format in <QuizFormat>[
      const StandardFormat(),
      const PokerFormat(startingChips: 250),
      const JeopardyFormat(
        JeopardyBoard(
          rowPoints: [100],
          penalizeWrongAnswers: true,
          allowSteal: false,
          categories: [
            JeopardyCategory(
              name: 'Media',
              cells: [
                JeopardyCell(questionId: 'question-1', isDailyDouble: true),
              ],
            ),
          ],
        ),
      ),
    ]) {
      test(
        'imports all media and format settings for ${format.label}',
        () async {
          final source = withMedia.copyWith(format: format);
          final repository = InMemoryQuizRepository();
          final imported = await importQuiz(
            contents: exportQuizJson(source),
            repository: repository,
            createId: () => 'unused',
          );
          expect(imported, source);
          expect(
            imported.questions.single.media.first.asset!.bytes,
            image.bytes,
          );
          expect(
            imported.questions.single.solutionMedia.single.asset!.bytes,
            image.bytes,
          );
          expect(await repository.loadAll(), [source]);
        },
      );
    }

    for (final badData in <String?>[
      null,
      'not base64!',
      base64Encode([1, 2, 3]),
    ]) {
      test(
        'rejects missing or corrupt media ($badData) before saving',
        () async {
          final json = withMedia.toJson();
          final question = (json['questions'] as List).single as JsonMap;
          final attachment = (question['media'] as List).first as JsonMap;
          (attachment['asset'] as JsonMap)['data'] = badData;
          final repository = InMemoryQuizRepository([quiz]);
          await expectLater(
            importQuiz(
              contents: jsonEncode(json),
              repository: repository,
              createId: () => 'unused',
            ),
            throwsA(isA<QuizImportException>()),
          );
          expect(await repository.loadAll(), [quiz]);
        },
      );
    }
  });

  test('rejects non-UTF-8 files and decodes Unicode quiz names', () {
    expect(
      () => decodeQuizFile(Uint8List.fromList([255, 254, 0])),
      throwsA(isA<QuizImportException>()),
    );
    final source = quiz.copyWith(name: 'Quiz: Grüße 🌍');
    expect(
      parseQuizImport(decodeQuizFile(utf8.encode(exportQuizJson(source)))),
      source,
    );
  });

  test('enforces import and export size limits for text without media', () {
    final source = quiz.copyWith(description: 'a' * maxQuizFileBytes);
    expect(() => exportQuizJson(source), throwsA(isA<QuizImportException>()));
    expect(
      () => parseQuizImport(jsonEncode(source.toJson())),
      throwsA(isA<QuizImportException>()),
    );
  });
}

Map<String, Object?> _jsonFor(Quiz quiz) =>
    Map<String, Object?>.from(quiz.toJson());
