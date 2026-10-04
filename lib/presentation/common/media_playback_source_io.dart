import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

/// Native players need a local file for editor previews of embedded uploads.
class MediaPlaybackSource {
  MediaPlaybackSource._(this.uri, this._directory);
  final Uri uri;
  final Directory? _directory;
  static Future<MediaPlaybackSource> prepare(Uri source) async {
    if (source.scheme != 'data') return MediaPlaybackSource._(source, null);
    final data = source.data!;
    final extension = switch (data.mimeType) {
      'audio/mpeg' => 'mp3',
      'audio/wav' => 'wav',
      'audio/ogg' => 'ogg',
      'video/mp4' => 'mp4',
      _ => throw const FormatException('Unsupported playback format'),
    };
    final directory = await Directory.systemTemp.createTemp('quizmo-media-');
    try {
      final file = File(p.join(directory.path, 'preview.$extension'));
      await file.writeAsBytes(data.contentAsBytes(), flush: true);
      return MediaPlaybackSource._(p.toUri(file.path), directory);
    } on Object {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

VideoPlayerController createMediaVideoController(Uri source) =>
    source.scheme == 'file'
    ? VideoPlayerController.file(File(p.fromUri(source)))
    : VideoPlayerController.networkUrl(source);
