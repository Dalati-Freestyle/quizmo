/// Quizmo — a local-first, multi-device quiz platform.
///
/// The entry point stays intentionally thin: everything that matters lives in
/// `lib/core` (pure Dart domain and engine), `lib/backend` (embedded server)
/// and `lib/presentation` (Flutter UI).
library;

import 'package:flutter/material.dart';

import 'presentation/app.dart';
import 'presentation/common/platform_media.dart';
import 'presentation/common/browser_exit_guard.dart';
import 'presentation/spectator/tv_launch.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializePlatformMedia();
  initializeBrowserExitGuard();
  // Evaluated before `runApp`: Flutter Web rewrites the address bar once the
  // router starts, so `/tv` has to be read while the original URL is intact.
  runApp(QuizmoApp(startAsTv: isTvLaunchUri(Uri.base), launchUri: Uri.base));
}
