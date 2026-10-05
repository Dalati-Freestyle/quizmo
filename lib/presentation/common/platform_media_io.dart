import 'dart:io';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void initializePlatformMedia() {
  if (Platform.isWindows) {
    JustAudioMediaKit.title = 'Quizmo';
    JustAudioMediaKit.ensureInitialized(linux: false);
  }
}
