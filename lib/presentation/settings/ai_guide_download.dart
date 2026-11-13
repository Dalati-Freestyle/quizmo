/// Offers the AI quiz guide (`docs/ai-quiz-guide.md`, English
/// `docs/ai-quiz-guide.en.md`) as a file.
///
/// Loaded deferred from the settings, so the guide never enlarges the
/// player bundle that guests load when joining.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Asset path of the German guide; the same file as in the repository.
const kAiQuizGuideAsset = 'docs/ai-quiz-guide.md';

/// Asset path of the English guide; the same file as in the repository.
const kAiQuizGuideEnglishAsset = 'docs/ai-quiz-guide.en.md';

/// Saves (native) or downloads (web) the guide in the app language: German
/// for [german], English otherwise. Returns `false` on cancel.
Future<bool> saveAiQuizGuide({
  required String dialogTitle,
  required bool german,
}) async {
  final text = await rootBundle.loadString(
    german ? kAiQuizGuideAsset : kAiQuizGuideEnglishAsset,
  );
  final saved = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: german ? 'quizmo-ki-anleitung.md' : 'quizmo-ai-guide.md',
    bytes: utf8.encode(text),
    mimeType: 'text/markdown',
  );
  return saved != null;
}
