/// Quizmo — a local-first, multi-device quiz platform.
///
/// The entry point stays intentionally thin: everything that matters lives in
/// `lib/core` (pure Dart domain and engine), `lib/backend` (embedded server)
/// and `lib/presentation` (Flutter UI).
library;

import 'package:flutter/material.dart';

import 'presentation/app.dart';

void main() {
  runApp(const QuizmoApp());
}
