import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media_playback_source.dart';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    hide PlayerState;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/models.dart';
import '../../core/net/media_cache.dart';

class SessionMediaAccess extends StatefulWidget {
  const SessionMediaAccess({
    required this.baseUri,
    required this.child,
    super.key,
  });
  final Uri? baseUri;
  final Widget child;
  @override
  State<SessionMediaAccess> createState() => _SessionMediaAccessState();
}

class _SessionMediaAccessState extends State<SessionMediaAccess> {
  late SessionMediaCache cache;

  @override
  void initState() {
    super.initState();
    cache = SessionMediaCache(baseUri: widget.baseUri ?? Uri.base);
  }

  @override
  void didUpdateWidget(SessionMediaAccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.baseUri != oldWidget.baseUri) {
      cache.dispose();
      cache = SessionMediaCache(baseUri: widget.baseUri ?? Uri.base);
    }
  }

  @override
  void dispose() {
    cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SessionMediaScope(cache: cache, child: widget.child);
}

class _SessionMediaScope extends InheritedWidget {
  const _SessionMediaScope({required this.cache, required super.child});
  final SessionMediaCache cache;
  @override
  bool updateShouldNotify(_SessionMediaScope oldWidget) =>
      cache != oldWidget.cache;
}

class QuestionMediaView extends StatelessWidget {
  const QuestionMediaView({
    required this.media,
    this.baseUri,
    this.playing,
    this.playbackRevision = 0,
    this.commandRevision = 0,
    this.maxVideoHeight = 300,
    super.key,
  });
  final bool? playing;
  final int playbackRevision;
  final int commandRevision;
  final double maxVideoHeight;
  final List<MediaAttachment> media;
  final Uri? baseUri;

  Uri source(MediaAsset asset, [BuildContext? context]) {
    if (asset.data != null) {
      return Uri.parse('data:${asset.mimeType};base64,${asset.data}');
    }
    final base =
        baseUri ??
        context
            ?.dependOnInheritedWidgetOfExactType<_SessionMediaScope>()
            ?.cache
            .baseUri ??
        Uri.base;
    return sessionMediaUri(base, asset);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, attachment) in media.indexed)
        _LoadedMedia(
          key: ValueKey('${attachment.asset?.id ?? attachment.hashCode}-$i'),
          attachment: attachment,
          baseUri: baseUri,
          builder: (loaded) => _ReadyMediaView(
            media: [loaded],
            baseUri: baseUri,
            playing: playing,
            playbackRevision: playbackRevision,
            commandRevision: commandRevision,
            maxVideoHeight: maxVideoHeight,
          ),
        ),
    ],
  );
}

class _LoadedMedia extends StatefulWidget {
  const _LoadedMedia({
    required this.attachment,
    required this.baseUri,
    required this.builder,
    super.key,
  });
  final MediaAttachment attachment;
  final Uri? baseUri;
  final Widget Function(MediaAttachment) builder;
  @override
  State<_LoadedMedia> createState() => _LoadedMediaState();
}

class _LoadedMediaState extends State<_LoadedMedia> {
  SessionMediaCache? cache;
  SessionMediaCache? ownedCache;
  Future<MediaAsset>? download;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(_LoadedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_SessionMediaScope>()
        ?.cache;
    final base = widget.baseUri ?? inherited?.baseUri ?? Uri.base;
    final next = inherited?.baseUri == base ? inherited : null;
    if (cache != null && (cache == next || ownedCache?.baseUri == base)) return;
    ownedCache?.dispose();
    ownedCache = next == null ? SessionMediaCache(baseUri: base) : null;
    cache = next ?? ownedCache;
    _load();
  }

  void _load() {
    final asset = widget.attachment.asset;
    download = asset == null || asset.data != null ? null : cache!.load(asset);
  }

  @override
  void dispose() {
    ownedCache?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (download == null) return widget.builder(widget.attachment);
    return FutureBuilder<MediaAsset>(
      future: download,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            children: [
              Text(
                context.tr('Medium konnte nicht geladen werden.'),
                style: const TextStyle(fontSize: 22),
              ),
              TextButton.icon(
                onPressed: () => setState(_load),
                icon: const Icon(Icons.refresh),
                label: Text(
                  context.tr('Erneut versuchen'),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ],
          );
        }
        if (snapshot.data case final asset?) {
          final attachment = widget.attachment;
          return widget.builder(switch (attachment) {
            ImageAttachment() => ImageAttachment(
              asset: asset,
              zoom: attachment.zoom,
              caption: attachment.caption,
              hideDetails: attachment.hideDetails,
            ),
            AudioAttachment() => AudioAttachment(
              asset: asset,
              playbackLimitSeconds: attachment.playbackLimitSeconds,
              softPlaybackLimit: attachment.softPlaybackLimit,
              caption: attachment.caption,
              hideDetails: attachment.hideDetails,
            ),
            VideoAttachment() => VideoAttachment(
              asset: asset,
              caption: attachment.caption,
              hideDetails: attachment.hideDetails,
            ),
            CodeAttachment() || GeoAttachment() => attachment,
          });
        }
        return StreamBuilder<void>(
          stream: cache!.updates,
          builder: (context, _) {
            final progress = cache!.progress(widget.attachment.asset!.id);
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    context.tr('Preloading media...'),
                    style: const TextStyle(fontSize: 22),
                  ),
                  LinearProgressIndicator(value: progress?.fraction),
                  if (progress != null)
                    Text(
                      '${(progress.received / (1024 * 1024)).toStringAsFixed(1)}'
                      '${progress.total == null ? "" : " / ${(progress.total! / (1024 * 1024)).toStringAsFixed(1)}"} MiB',
                      style: const TextStyle(fontSize: 22),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ReadyMediaView extends QuestionMediaView {
  const _ReadyMediaView({
    required super.media,
    super.baseUri,
    super.playing,
    super.playbackRevision,
    super.commandRevision,
    super.maxVideoHeight,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, attachment) in media.indexed)
        Padding(
          key: ValueKey('${attachment.hashCode}-$i'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              switch (attachment) {
                ImageAttachment() => _image(context, attachment),
                AudioAttachment() => _PlaybackRetry(
                  builder: (retry) => _AudioView(
                    attachment: attachment,
                    source: source(attachment.asset, context),
                    onRetry: retry,
                    playing: playing,
                    playbackRevision: playbackRevision,
                    commandRevision: commandRevision,
                  ),
                ),
                VideoAttachment(:final youtubeId) =>
                  youtubeId != null
                      ? _YoutubeView(
                          maxHeight: maxVideoHeight,
                          id: youtubeId,
                          hideDetails: attachment.hideDetails,
                          playing: playing,
                          playbackRevision: playbackRevision,
                          commandRevision: commandRevision,
                        )
                      : _PlaybackRetry(
                          builder: (retry) => _VideoView(
                            maxHeight: maxVideoHeight,
                            source: source(attachment.asset!, context),
                            onRetry: retry,
                            playing: playing,
                            playbackRevision: playbackRevision,
                            commandRevision: commandRevision,
                          ),
                        ),
                CodeAttachment(:final code, :final language) =>
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: HighlightView(
                      code,
                      language: language,
                      theme: githubTheme,
                      padding: const EdgeInsets.all(16),
                      textStyle: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                      ),
                    ),
                  ),
                GeoAttachment() => _map(attachment),
              },
              if (!attachment.hideDetails && attachment.caption.isNotEmpty)
                Text(attachment.caption, style: const TextStyle(fontSize: 22)),
            ],
          ),
        ),
    ],
  );

  Widget _image(BuildContext context, ImageAttachment image) {
    Widget picture() => _AttachmentImage(asset: image.asset);
    return Column(
      children: [
        SizedBox(height: 240, child: picture()),
        if (image.zoom)
          TextButton.icon(
            icon: const Icon(Icons.zoom_in),
            label: Text(context.tr('Vergrößern')),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 1000,
                  height: 650,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          minScale: .5,
                          maxScale: 8,
                          child: picture(),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _map(GeoAttachment geo) => SizedBox(
    height: 300,
    child: FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(geo.latitude, geo.longitude),
        initialZoom: geo.zoom,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'quizmo',
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PlaybackRetry extends StatefulWidget {
  const _PlaybackRetry({required this.builder});
  final Widget Function(VoidCallback) builder;
  @override
  State<_PlaybackRetry> createState() => _PlaybackRetryState();
}

class _PlaybackRetryState extends State<_PlaybackRetry> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey(revision),
    child: widget.builder(() => setState(() => revision++)),
  );
}

Widget _mediaFailure(
  BuildContext context,
  String message,
  VoidCallback retry,
) => Column(
  children: [
    Text(context.tr(message), style: const TextStyle(fontSize: 22)),
    TextButton.icon(
      onPressed: retry,
      icon: const Icon(Icons.refresh),
      label: Text(
        context.tr('Erneut versuchen'),
        style: const TextStyle(fontSize: 22),
      ),
    ),
  ],
);

class _AttachmentImage extends StatefulWidget {
  const _AttachmentImage({required this.asset});
  final MediaAsset asset;
  @override
  State<_AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<_AttachmentImage> {
  late Uint8List bytes = widget.asset.bytes!;
  late String? svg = widget.asset.mimeType == 'image/svg+xml'
      ? utf8.decode(bytes)
      : null;

  @override
  void didUpdateWidget(_AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      bytes = widget.asset.bytes!;
      svg = widget.asset.mimeType == 'image/svg+xml'
          ? utf8.decode(bytes)
          : null;
    }
  }

  @override
  Widget build(BuildContext context) => svg != null
      ? SvgPicture.string(svg!, fit: BoxFit.contain)
      : Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Text(context.tr("Bild konnte nicht geladen werden.")),
        );
}

class _AudioView extends StatefulWidget {
  const _AudioView({
    required this.attachment,
    required this.source,
    required this.onRetry,
    this.playing,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final bool? playing;
  final int playbackRevision;
  final int commandRevision;
  final AudioAttachment attachment;
  final Uri source;
  final VoidCallback onRetry;
  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  final player = AudioPlayer();
  @override
  void didUpdateWidget(_AudioView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ready &&
        (oldWidget.playing != widget.playing ||
            oldWidget.commandRevision != widget.commandRevision ||
            oldWidget.playbackRevision != widget.playbackRevision)) {
      _applyPlayback(oldWidget.playbackRevision != widget.playbackRevision);
    }
  }

  void _applyPlayback(bool restart) {
    unawaited(_control(restart));
  }

  Future<void> _control(bool restart) async {
    try {
      if (restart || player.processingState == ProcessingState.completed) {
        await player.pause();
        await player.seek(Duration.zero);
      }
      if (!mounted) return;
      if (restart || widget.playing == true) {
        if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        unawaited(player.play().catchError((Object _) {}));
      } else if (widget.playing == false) {
        await player.pause();
      }
    } on Object {
      /* Local play remains available if browser autoplay is blocked. */
    }
  }

  MediaPlaybackSource? playbackSource;
  String? error;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final source = await MediaPlaybackSource.prepare(widget.source);
      if (!mounted) {
        await source.dispose();
        return;
      }
      playbackSource = source;
      await player
          .setUrl(source.uri.toString())
          .timeout(const Duration(seconds: 30));
      if (widget.attachment.playbackLimitSeconds case final limit?
          when !widget.attachment.softPlaybackLimit) {
        await player.setClip(
          start: Duration.zero,
          end: Duration(seconds: limit),
        );
      }
      if (mounted) {
        setState(() => ready = true);
        _applyPlayback(false);
      }
    } on Object {
      if (mounted) {
        setState(
          () => error = context.tr(
            "Audio kann auf diesem Gerät nicht abgespielt werden.",
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(
      player.dispose().whenComplete(() async => playbackSource?.dispose()),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return _mediaFailure(context, error!, widget.onRetry);
    if (!ready) return const LinearProgressIndicator();
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final playing =
            (snapshot.data?.playing ?? false) &&
            snapshot.data?.processingState != ProcessingState.completed;
        return Row(
          children: [
            IconButton(
              tooltip: playing ? context.tr("Pause") : context.tr("Abspielen"),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () async {
                if (playing) {
                  await player.pause();
                } else {
                  if (player.processingState == ProcessingState.completed) {
                    await player.pause();
                    await player.seek(Duration.zero);
                  }
                  try {
                    await player.play();
                  } on Object {
                    if (mounted) {
                      setState(
                        () => error = context.tr(
                          "Audio konnte nicht abgespielt werden.",
                        ),
                      );
                    }
                  }
                }
              },
            ),
            IconButton(
              tooltip: context.tr("Neustart"),
              icon: const Icon(Icons.replay),
              onPressed: () => _applyPlayback(true),
            ),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, snapshot) => Text(
                  '${(snapshot.data ?? Duration.zero).inSeconds} s${widget.attachment.playbackLimitSeconds == null ? '' : ' / ${widget.attachment.playbackLimitSeconds} s'}',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({
    required this.source,
    required this.onRetry,
    this.maxHeight = 300,
    this.playing,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final bool? playing;
  final int playbackRevision;
  final int commandRevision;
  final Uri source;
  final VoidCallback onRetry;
  final double maxHeight;
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  @override
  void didUpdateWidget(_VideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller?.value.isInitialized == true &&
        (oldWidget.playing != widget.playing ||
            oldWidget.commandRevision != widget.commandRevision ||
            oldWidget.playbackRevision != widget.playbackRevision)) {
      unawaited(
        _applyPlayback(oldWidget.playbackRevision != widget.playbackRevision),
      );
    }
  }

  Future<void> _applyPlayback(bool restart) async {
    try {
      final video = controller!;
      if (restart) await video.seekTo(Duration.zero);
      if (!mounted) return;
      if (widget.playing == true) {
        if (video.value.position >= video.value.duration) {
          await video.seekTo(Duration.zero);
        }
        await video.play();
      } else if (widget.playing == false) {
        await video.pause();
      }
    } on Object {
      /* Local play remains available if browser autoplay is blocked. */
    }
  }

  VideoPlayerController? controller;
  MediaPlaybackSource? playbackSource;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final source = await MediaPlaybackSource.prepare(widget.source);
      if (!mounted) {
        await source.dispose();
        return;
      }
      playbackSource = source;
      final video = createMediaVideoController(source.uri);
      controller = video;
      video.addListener(_update);
      await video.initialize().timeout(const Duration(seconds: 30));
      if (mounted) await _applyPlayback(false);
      _update();
    } on Object {
      if (mounted) {
        setState(
          () => error = context.tr(
            "Video kann auf diesem Gerät nicht abgespielt werden.",
          ),
        );
      }
    }
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final video = controller;
    if (video != null) {
      video.removeListener(_update);
      unawaited(
        video.dispose().whenComplete(() async => playbackSource?.dispose()),
      );
    } else {
      unawaited(playbackSource?.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (error != null) return _mediaFailure(context, error!, widget.onRetry);
    if (controller == null) return const LinearProgressIndicator();
    if (controller.value.hasError) {
      return _mediaFailure(
        context,
        "Video konnte nicht geladen werden.",
        widget.onRetry,
      );
    }
    if (!controller.value.isInitialized) return const LinearProgressIndicator();
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        IconButton(
          tooltip: controller.value.isPlaying
              ? context.tr("Pause")
              : context.tr("Abspielen"),
          onPressed: () => controller.value.isPlaying
              ? controller.pause()
              : controller.play(),
          icon: Icon(
            controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
        ),
      ],
    );
  }
}

class _YoutubeView extends StatefulWidget {
  const _YoutubeView({
    required this.id,
    this.maxHeight = 300,
    this.hideDetails = false,
    this.playing,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final bool hideDetails;
  final bool? playing;
  final int playbackRevision;
  final int commandRevision;
  final String id;
  final double maxHeight;
  @override
  State<_YoutubeView> createState() => _YoutubeViewState();
}

class _YoutubeViewState extends State<_YoutubeView> {
  @override
  void didUpdateWidget(_YoutubeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.commandRevision != widget.commandRevision ||
        oldWidget.playbackRevision != widget.playbackRevision) {
      unawaited(
        _applyPlayback(oldWidget.playbackRevision != widget.playbackRevision),
      );
    }
  }

  Future<void> _applyPlayback(bool restart) async {
    final player = controller;
    if (player == null) return;
    try {
      if (restart) {
        await player.loadVideoById(videoId: widget.id, startSeconds: 0);
        return;
      }
      if (!mounted) return;
      if (widget.playing == true) {
        await player.playVideo();
      } else if (widget.playing == false) {
        await player.pauseVideo();
      }
    } on Object {
      /* Keep the embedded player's local fallback available. */
    }
  }

  YoutubePlayerController? controller;
  bool get _openInBrowser =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    if (_openInBrowser) return;
    controller = YoutubePlayerController.fromVideoId(
      videoId: widget.id,
      autoPlay: widget.playing == true,
      params: YoutubePlayerParams(
        showControls: !widget.hideDetails,
        showFullscreenButton: true,
      ),
    );
  }

  @override
  void dispose() {
    controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _openInBrowser
      ? TextButton.icon(
          onPressed: () => launchUrl(
            Uri.https('www.youtube.com', '/watch', {'v': widget.id}),
          ),
          icon: const Icon(Icons.open_in_new),
          label: Text(context.tr("YouTube-Video öffnen")),
        )
      : Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxHeight * 16 / 9),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: YoutubePlayer(controller: controller!),
            ),
          ),
        );
}
