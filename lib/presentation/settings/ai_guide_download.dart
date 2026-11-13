/// Offers the AI quiz guide (`docs/ai-quiz-guide.md`) as a file.
///
/// Loaded deferred from the settings, so the guide never enlarges the
/// player bundle that guests load when joining.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Asset path of the guide; the same file as in the repository.
const kAiQuizGuideAsset = 'docs/ai-quiz-guide.md';

/// Saves (native) or downloads (web) the guide. Returns `false` on cancel.
Future<bool> saveAiQuizGuide({required String dialogTitle}) async {
  final text = await rootBundle.loadString(kAiQuizGuideAsset);
  final saved = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: 'quizmo-ki-anleitung.md',
    bytes: utf8.encode(text),
    mimeType: 'text/markdown',
  );
  return saved != null;
}
