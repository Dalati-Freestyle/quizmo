/// Keeps the documentation's internal links and referenced paths valid.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _documents = [
  'README.md',
  'AGENTS.md',
  'docs/quiz-file-format.md',
  'docs/question-types-and-media.md',
  'docs/ai-quiz-guide.md',
  'docs/ai-quiz-guide.en.md',
  'deploy/README.md',
];

/// GitHub style anchor of a heading.
String _anchor(String heading) => heading
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
    .replaceAll(' ', '-');

void main() {
  for (final path in _documents) {
    test('links in $path resolve', () {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);
      final text = file.readAsStringSync();
      final directory = File(path).parent.path;
      final anchors = {
        for (final match in RegExp(
          r'^#{1,6} (.+)$',
          multiLine: true,
        ).allMatches(text))
          _anchor(match.group(1)!),
      };
      for (final match in RegExp(r'\]\(([^)\s]+)\)').allMatches(text)) {
        final target = match.group(1)!;
        if (target.startsWith('http') || target.startsWith('mailto:')) {
          continue;
        }
        if (target.startsWith('#')) {
          expect(
            anchors,
            contains(target.substring(1)),
            reason: '$path links to missing anchor $target',
          );
          continue;
        }
        final relative = target.split('#').first;
        final resolved = '$directory/$relative';
        expect(
          File(resolved).existsSync() || Directory(resolved).existsSync(),
          isTrue,
          reason: '$path links to missing $target',
        );
      }
    });
  }

  test('commands and files named in the README exist', () {
    for (final path in [
      'tool/bundle_web_client.dart',
      'tool/bump_version.ps1',
      'tool/generate_localizations.dart',
      'bin/server.dart',
      'server/pubspec.yaml',
      'deploy/compose.yaml',
      'deploy/Caddyfile',
      'deploy/Caddyfile.basic-auth',
      'deploy/.env.example',
      'docs/ai-quiz-guide.md',
      'docs/ai-quiz-guide.en.md',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
