/// Tests for the file backed native quiz library store.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_library_store_io.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  late Directory temp;
  late Directory directory;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('quiz-library-');
    directory = Directory(p.join(temp.path, 'nested', 'quiz-library'));
  });

  tearDown(() => temp.delete(recursive: true));

  FileQuizLibraryStore store({_Legacy? legacy}) =>
      FileQuizLibraryStore(() async => directory, legacy: legacy);

  test('reads null before the first write and creates its directory', () async {
    expect(await store().read(), isNull);
    await store().write('{"a":1}');
    expect(await store().read(), '{"a":1}');
    expect(
      File(p.join(directory.path, 'library.pending')).existsSync(),
      isFalse,
    );
  });

  test('migrates the legacy document and clears it after writing', () async {
    final legacy = _Legacy('{"old":true}');
    final files = store(legacy: legacy);

    expect(await files.read(), '{"old":true}');
    await files.write('{"new":true}');

    expect(legacy.document, isNull);
    expect(
      await store(legacy: _Legacy('{"stale":true}')).read(),
      '{"new":true}',
    );
  });

  test('ignores an interrupted pending write', () async {
    await store().write('{"saved":true}');
    await File(p.join(directory.path, 'library.pending')).writeAsString('{"tr');
    expect(await store().read(), '{"saved":true}');
  });

  test('imports and reloads a quiz with media beyond 20 MiB', () async {
    // Android's SharedPreferences could not carry such a library at all.
    final bytes = Uint8List(40 * 1024 * 1024);
    for (var i = 0; i < bytes.length; i += 4096) {
      bytes[i] = i ~/ 4096 % 251;
    }
    bytes.setAll(0, const [0, 0, 0, 12, 102, 116, 121, 112]); // MP4 `ftyp`
    final video = MediaAsset.upload(bytes, 'mp4');
    final quiz = Quiz(
      id: 'big',
      name: 'Big media',
      description: 'Media heavy quiz',
      category: 'General knowledge',
      createdAt: DateTime.utc(2026, 11, 20),
      updatedAt: DateTime.utc(2026, 11, 20),
      questions: [
        Question.fromJson({
          ...const MultipleChoiceQuestion(
            id: 'question-1',
            prompt: 'Which film?',
            options: [
              AnswerOption(id: 'a', label: 'A'),
              AnswerOption(id: 'b', label: 'B'),
            ],
            correctOptionId: 'a',
            scoringRule: FixedPointsRule(),
          ).toJson(),
          'media': [VideoAttachment(asset: video).toJson()],
        }),
      ],
    );
    final repository = PersistentQuizRepository(store: store());

    await importQuiz(
      contents: exportQuizJson(quiz),
      repository: repository,
      createId: () => 'unused',
    );

    final reloaded = await PersistentQuizRepository(store: store()).loadAll();
    expect(reloaded, [quiz]);
    expect(reloaded.single.questions.single.media.single.asset?.id, video.id);
  });
}

final class _Legacy implements LegacyQuizLibrarySource {
  _Legacy(this.document);
  String? document;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> clear() async => document = null;
}
