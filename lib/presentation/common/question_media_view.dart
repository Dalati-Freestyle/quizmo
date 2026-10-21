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

  Uri source(MediaAsset asset) => asset.data != null
      ? Uri.dataFromBytes(asset.bytes!, mimeType: asset.mimeType)
      : (baseUri ?? Uri.base).resolve(asset.route);

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
                AudioAttachment() => _AudioView(
                  attachment: attachment,
                  source: source(attachment.asset),
                  playing: playing,
                  playbackRevision: playbackRevision,
                  commandRevision: commandRevision,
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
                      : _VideoView(
                          maxHeight: maxVideoHeight,
                          source: source(attachment.asset!),
                          playing: playing,
                          playbackRevision: playbackRevision,
                          commandRevision: commandRevision,
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
    Widget picture() => image.asset.mimeType == 'image/svg+xml'
        ? image.asset.data != null
              ? SvgPicture.string(
                  utf8.decode(image.asset.bytes!),
                  fit: BoxFit.contain,
                )
              : SvgPicture.network(
                  source(image.asset).toString(),
                  fit: BoxFit.contain,
                )
        : image.asset.data != null
        ? Image.memory(
            image.asset.bytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                Text(context.tr("Bild konnte nicht geladen werden.")),
          )
        : Image.network(
            source(image.asset).toString(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                Text(context.tr("Bild konnte nicht geladen werden.")),
          );
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

class _AudioView extends StatefulWidget {
  const _AudioView({
    required this.attachment,
    required this.source,
    this.playing,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final bool? playing;
  final int playbackRevision;
  final int commandRevision;
  final AudioAttachment attachment;
  final Uri source;
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
      await player.setUrl(source.uri.toString());
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
    if (error != null) return Text(context.tr(error!));
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
    this.maxHeight = 300,
    this.playing,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final bool? playing;
  final int playbackRevision;
  final int commandRevision;
  final Uri source;
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
      await video.initialize();
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
    if (error != null) return Text(context.tr(error!));
    if (controller == null) return const LinearProgressIndicator();
    if (controller.value.hasError) {
      return Text(error ?? context.tr("Video konnte nicht geladen werden."));
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
