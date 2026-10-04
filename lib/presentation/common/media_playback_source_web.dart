import 'package:video_player/video_player.dart';

class MediaPlaybackSource {
  MediaPlaybackSource._(this.uri);
  final Uri uri;
  static Future<MediaPlaybackSource> prepare(Uri source) async =>
      MediaPlaybackSource._(source);
  Future<void> dispose() async {}
}

VideoPlayerController createMediaVideoController(Uri source) =>
    VideoPlayerController.networkUrl(source);
