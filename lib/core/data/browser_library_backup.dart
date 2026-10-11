import 'dart:convert';

/// Whether a browser library contains user content worth backing up.
/// SharedPreferences may wrap its JSON document in a JSON-encoded string.
bool browserLibraryNeedsBackup(String? contents) {
  if (contents == null) return false;
  try {
    final decoded = jsonDecode(contents);
    final json =
        (decoded is String ? jsonDecode(decoded) : decoded)
            as Map<String, dynamic>;
    return (json['quizzes'] as List<dynamic>? ?? []).any(
      (dynamic quiz) =>
          quiz['id'] != 'quiz-sample' ||
          quiz['createdAtMicros'] != quiz['updatedAtMicros'],
    );
  } on Object {
    // A damaged library should still prompt users to preserve their data.
    return true;
  }
}
