import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/data/browser_library_backup.dart';

bool _hasQuizzes = false;
bool _protocolOpen = false;
bool _installed = false;

const String _backupFlagKey = 'quizmo.quiz-library.needs-backup';
const List<String> _legacyLibraryKeys = [
  'quizmo.quiz-library.v1',
  'flutter.quizmo.quiz-library.v1',
];

/// Remembers whether the library holds quizzes worth exporting.
///
/// The library itself lives in IndexedDB, which can neither be read
/// synchronously at startup nor notifies other tabs. A small `localStorage`
/// flag does both: [initializeBrowserExitGuard] reads it without loading the
/// library, and other tabs receive its `storage` event.
void updateBrowserExitGuard(String? contents) {
  _hasQuizzes = browserLibraryNeedsBackup(contents);
  try {
    web.window.localStorage.setItem(_backupFlagKey, _hasQuizzes ? '1' : '0');
  } on Object {
    /* Without site data the reminder still works in this tab. */
  }
}

void initializeBrowserExitGuard() {
  if (_installed) return;
  _installed = true;
  try {
    final storage = web.window.localStorage;
    // Libraries of older versions stay in localStorage until the first save.
    final legacy = _legacyLibraryKeys.map(storage.getItem).nonNulls;
    _hasQuizzes =
        storage.getItem(_backupFlagKey) == '1' ||
        legacy.any(browserLibraryNeedsBackup);
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
      final key = event.key;
      if (key == _backupFlagKey) {
        _hasQuizzes = event.newValue == '1';
      } else if (key == null) {
        _hasQuizzes = false;
      } else if (_legacyLibraryKeys.contains(key) && event.newValue != null) {
        _hasQuizzes = browserLibraryNeedsBackup(event.newValue);
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
