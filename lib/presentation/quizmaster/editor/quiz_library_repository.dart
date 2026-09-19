/// Platform-aware factory for the persistent quiz library.
///
/// The default deliberately fails on unsupported targets; browsers and
/// `dart:io` hosts select their own implementation without exposing platform
/// imports to the rest of the quizmaster UI.
library;

export 'quiz_library_repository_stub.dart'
    if (dart.library.html) 'quiz_library_repository_web.dart'
    if (dart.library.io) 'quiz_library_repository_io.dart';
