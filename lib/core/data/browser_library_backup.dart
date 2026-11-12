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
    final defaultIds = json['defaultQuizIds'] as List<dynamic>?;
    return (json['quizzes'] as List<dynamic>? ?? []).any(
      (dynamic quiz) => defaultIds != null
          ? !defaultIds.contains(quiz['id'])
          : !const {
                  'quiz-sample',
                  'quiz-sample-jeopardy',
                  'quiz-sample-poker',
                }.contains(quiz['id']) ||
                quiz['createdAtMicros'] != quiz['updatedAtMicros'],
    );
  } on Object {
    // A damaged library should still prompt users to preserve their data.
    return true;
  }
}
