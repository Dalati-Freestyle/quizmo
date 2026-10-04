import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media_playback_source.dart';

import 'package:flutter/material.dart';
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
  const QuestionMediaView({required this.media, this.baseUri, super.key});
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
                ),
                VideoAttachment(:final youtubeId) =>
                  youtubeId != null
                      ? _YoutubeView(id: youtubeId)
                      : _VideoView(source: source(attachment.asset!)),
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
              if (attachment.caption.isNotEmpty)
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
                const Text('Bild konnte nicht geladen werden.'),
          )
        : Image.network(
            source(image.asset).toString(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Text('Bild konnte nicht geladen werden.'),
          );
    return Column(
      children: [
        SizedBox(height: 240, child: picture()),
        if (image.zoom)
          TextButton.icon(
            icon: const Icon(Icons.zoom_in),
            label: const Text('Vergrößern'),
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
  const _AudioView({required this.attachment, required this.source});
  final AudioAttachment attachment;
  final Uri source;
  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  final player = AudioPlayer();
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
      if (widget.attachment.playbackLimitSeconds case final limit?) {
        await player.setClip(
          start: Duration.zero,
          end: Duration(seconds: limit),
        );
      }
      if (mounted) setState(() => ready = true);
    } on Object {
      if (mounted) {
        setState(
          () => error = 'Audio kann auf diesem Gerät nicht abgespielt werden.',
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
    if (error != null) return Text(error!);
    if (!ready) return const LinearProgressIndicator();
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Abspielen',
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () async {
                if (playing) {
                  await player.pause();
                } else {
                  if (player.processingState == ProcessingState.completed) {
                    await player.seek(Duration.zero);
                  }
                  try {
                    await player.play();
                  } on Object {
                    if (mounted) {
                      setState(
                        () => error = 'Audio konnte nicht abgespielt werden.',
                      );
                    }
                  }
                }
              },
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
  const _VideoView({required this.source});
  final Uri source;
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
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
      _update();
    } on Object {
      if (mounted) {
        setState(
          () => error = 'Video kann auf diesem Gerät nicht abgespielt werden.',
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
    if (error != null) return Text(error!);
    if (controller == null) return const LinearProgressIndicator();
    if (controller.value.hasError) {
      return Text(error ?? 'Video konnte nicht geladen werden.');
    }
    if (!controller.value.isInitialized) return const LinearProgressIndicator();
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        IconButton(
          tooltip: controller.value.isPlaying ? 'Pause' : 'Abspielen',
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
  const _YoutubeView({required this.id});
  final String id;
  @override
  State<_YoutubeView> createState() => _YoutubeViewState();
}

class _YoutubeViewState extends State<_YoutubeView> {
  late final YoutubePlayerController controller;
  @override
  void initState() {
    super.initState();
    controller = YoutubePlayerController.fromVideoId(
      videoId: widget.id,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );
  }

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux)
      ? TextButton.icon(
          onPressed: () => launchUrl(
            Uri.https('www.youtube.com', '/watch', {'v': widget.id}),
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('YouTube-Video öffnen'),
        )
      : YoutubePlayer(controller: controller);
}
