import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/data/browser_library_backup.dart';

bool _hasQuizzes = false;
bool _protocolOpen = false;
bool _installed = false;

void updateBrowserExitGuard(String? contents) {
  _hasQuizzes = browserLibraryNeedsBackup(contents);
}

void initializeBrowserExitGuard() {
  if (_installed) return;
  _installed = true;
  try {
    updateBrowserExitGuard(
      web.window.localStorage.getItem('quizmo.quiz-library.v1') ??
          web.window.localStorage.getItem('flutter.quizmo.quiz-library.v1'),
    );
  } on Object {
    /* Repository reports unavailable storage when it is used. */
  }
  web.window.addEventListener(
    'beforeunload',
    ((web.BeforeUnloadEvent event) {
      if (!_hasQuizzes && !_protocolOpen) return;
      event.preventDefault();
      event.returnValue = _protocolOpen
          ? 'The game protocol is gone after leaving. Save it first.'
          : 'Export your quizzes from the quiz library before leaving.';
    }).toJS,
  );
  web.window.addEventListener(
    'storage',
    ((web.StorageEvent event) {
      if (event.key == 'quizmo.quiz-library.v1' ||
          event.key == 'flutter.quizmo.quiz-library.v1' ||
          event.key == null) {
        updateBrowserExitGuard(event.newValue);
      }
    }).toJS,
  );
}

/// Asks before leaving while the final page with the game protocol is shown.
void setProtocolExitGuard(bool active) {
  _protocolOpen = active;
  initializeBrowserExitGuard();
}

void leaveBrowserPage() {
  _hasQuizzes = false;
  _protocolOpen = false;
  web.window.location.assign('about:blank');
}
