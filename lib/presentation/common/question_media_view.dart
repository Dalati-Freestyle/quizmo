import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'media_playback.dart';
import 'media_playback_source.dart';
import 'media_timeline.dart';
import 'media_volume.dart';

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
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    as youtube
    show PlayerState;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/models.dart';
import '../../core/net/media_cache.dart';
import '../../core/net/media_preloader.dart';

class SessionMediaAccess extends StatefulWidget {
  const SessionMediaAccess({
    required this.baseUri,
    required this.child,
    this.preloader,
    super.key,
  });
  final Uri? baseUri;
  final Widget child;

  /// Media preloaded in the lobby, used before anything is downloaded.
  final MediaPreloader? preloader;

  /// The preloader of the surrounding session, if any.
  static MediaPreloader? preloaderOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SessionMediaScope>()
      ?.cache
      .preloader;
  @override
  State<SessionMediaAccess> createState() => _SessionMediaAccessState();
}

class _SessionMediaAccessState extends State<SessionMediaAccess> {
  late SessionMediaCache cache;

  @override
  void initState() {
    super.initState();
    cache = _create();
  }

  SessionMediaCache _create() => SessionMediaCache(
    baseUri: widget.baseUri ?? Uri.base,
    preloader: widget.preloader,
  );

  @override
  void didUpdateWidget(SessionMediaAccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.baseUri != oldWidget.baseUri ||
        widget.preloader != oldWidget.preloader) {
      cache.dispose();
      cache = _create();
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

/// Shows the media of a question, solution, hint or slide as large as the
/// available space allows, complete and without distortion.
///
/// In a scrolling page pictures, videos and maps take the full width, but are
/// never higher than [maxMediaHeight] (default: 60 % of the screen). With
/// [fill] they share the bounded space of the parent instead (TV).
class QuestionMediaView extends StatelessWidget {
  const QuestionMediaView({
    required this.media,
    this.baseUri,
    this.playback = MediaPlayback.onDemand,
    this.playbackRevision = 0,
    this.commandRevision = 0,
    this.maxMediaHeight,
    this.fill = false,
    super.key,
  });
  final MediaPlayback playback;
  final int playbackRevision;
  final int commandRevision;
  final double? maxMediaHeight;

  /// Fills the parent without scrolling (TV). Pictures, videos and maps get
  /// a small button that shows them on (almost) the whole screen instead of
  /// the "enlarge" button below them.
  final bool fill;
  final List<MediaAttachment> media;
  final Uri? baseUri;

  /// Smallest height limit, so that media stay recognisable.
  static const minLimit = 120.0;

  /// From this width on several media stand next to each other.
  static const sideBySideWidth = 700.0;

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

  static bool _isVisual(MediaAttachment attachment) => switch (attachment) {
    ImageAttachment() || VideoAttachment() || GeoAttachment() => true,
    AudioAttachment() || CodeAttachment() => false,
  };

  Widget _loaded(
    BuildContext context,
    int index,
    MediaAttachment attachment, {
    double? slot,
  }) => _LoadedMedia(
    key: ValueKey('${attachment.asset?.id ?? attachment.hashCode}-$index'),
    attachment: attachment,
    baseUri: baseUri,
    slot: slot,
    builder: (loaded) => _ReadyMediaView(
      media: [loaded],
      baseUri: baseUri,
      playback: StillMedia.of(context) ? MediaPlayback.stopped : playback,
      playbackRevision: playbackRevision,
      commandRevision: commandRevision,
      fill: fill,
      slot: slot,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return fill ? _filled(context) : _flow(context);
  }

  Widget _filled(BuildContext context) {
    final large = [
      for (final (i, attachment) in media.indexed)
        if (attachment is! AudioAttachment) (i, attachment),
    ];
    final bars = [
      for (final (i, attachment) in media.indexed)
        if (attachment is AudioAttachment) (i, attachment),
    ];
    // Only the number decides, so a changed size never restarts a video.
    final columns = large.length <= 3
        ? large.length
        : math.sqrt(large.length).ceil();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row * math.max(columns, 1) < large.length; row++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (position, (i, attachment)) in large.indexed)
                  if (position ~/ columns == row) ...[
                    if (position % columns > 0) const SizedBox(width: 16),
                    Expanded(child: _loaded(context, i, attachment)),
                  ],
              ],
            ),
          ),
        for (final (i, attachment) in bars) _loaded(context, i, attachment),
      ],
    );
  }

  Widget _flow(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final screen = MediaQuery.sizeOf(context);
      final limit = math.max(minLimit, maxMediaHeight ?? screen.height * 0.6);
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : screen.width;
      final visuals = media.where(_isVisual).length;
      final half = visuals > 1 && width >= sideBySideWidth;
      // Always a Wrap: the widgets keep their place (and a running video)
      // when the width changes.
      return Wrap(
        spacing: 16,
        children: [
          for (final (i, attachment) in media.indexed)
            SizedBox(
              width: half && _isVisual(attachment) ? (width - 16) / 2 : width,
              child: _loaded(
                context,
                i,
                attachment,
                slot: _isVisual(attachment)
                    ? _slotHeight(
                        attachment,
                        half ? (width - 16) / 2 : width,
                        limit,
                      )
                    : null,
              ),
            ),
        ],
      );
    },
  );

  /// Height reserved for [attachment], also while it loads.
  static double _slotHeight(
    MediaAttachment attachment,
    double width,
    double limit,
  ) {
    if (attachment is VideoAttachment &&
        attachment.youtubeId != null &&
        _youtubeOpensBrowser) {
      return 76;
    }
    final ratio = switch (attachment) {
      ImageAttachment(:final asset) => asset.aspectRatio ?? 16 / 9,
      VideoAttachment(:final asset) => asset?.aspectRatio ?? 16 / 9,
      GeoAttachment() => 3 / 2,
      AudioAttachment() || CodeAttachment() => 16 / 9,
    };
    return math.min(limit, width / ratio);
  }
}

/// Windows and Linux have no embedded YouTube player.
bool get _youtubeOpensBrowser =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

class _LoadedMedia extends StatefulWidget {
  const _LoadedMedia({
    required this.attachment,
    required this.baseUri,
    required this.builder,
    this.slot,
    super.key,
  });

  /// Height of the loaded medium, reserved while it loads.
  final double? slot;
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
    Widget reserved(Widget child) => widget.slot == null
        ? Center(child: child)
        : SizedBox(
            height: widget.slot! + 16,
            child: Center(child: child),
          );
    return FutureBuilder<MediaAsset>(
      future: download,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return reserved(
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
              ),
            ),
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
            return reserved(
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
    super.playback,
    super.playbackRevision,
    super.commandRevision,
    super.fill,
    this.slot,
  });

  /// Height of a visual medium; `null` when it fills its parent.
  final double? slot;

  /// Space of the controls below an MP4 video.
  static const _videoControls = 64.0;

  @override
  Widget build(BuildContext context) {
    final attachment = media.single;
    if (StillMedia.of(context) &&
        (attachment is AudioAttachment || attachment is VideoAttachment)) {
      return _bounded(_StillPlayer(attachment: attachment));
    }
    final content = switch (attachment) {
      ImageAttachment() => _bounded(_image(context, attachment)),
      AudioAttachment() => _PlaybackRetry(
        builder: (retry) => _AudioView(
          attachment: attachment,
          source: source(attachment.asset, context),
          onRetry: retry,
          playback: playback,
          playbackRevision: playbackRevision,
          commandRevision: commandRevision,
        ),
      ),
      VideoAttachment(:final youtubeId) =>
        youtubeId != null
            ? _bounded(
                _YoutubeView(
                  id: youtubeId,
                  hideDetails: attachment.hideDetails,
                  playback: playback,
                  playbackRevision: playbackRevision,
                  commandRevision: commandRevision,
                ),
                // Our timeline below the player replaces YouTube's own
                // controls, which "hide details" switches off.
                extra: _youtubeOpensBrowser || !attachment.hideDetails
                    ? 0
                    : _videoControls,
              )
            : _bounded(
                _PlaybackRetry(
                  builder: (retry) => _VideoView(
                    mediaKey: attachment.asset!.id,
                    source: source(attachment.asset!, context),
                    onRetry: retry,
                    playback: playback,
                    playbackRevision: playbackRevision,
                    commandRevision: commandRevision,
                  ),
                ),
                extra: _videoControls,
              ),
      CodeAttachment(:final code, :final language) => _code(code, language),
      GeoAttachment() => _bounded(_map(attachment)),
    };
    final grows = fill && attachment is! AudioAttachment;
    final enlargeable =
        fill &&
        !StillMedia.of(context) &&
        switch (attachment) {
          ImageAttachment(:final zoom) => zoom,
          // YouTube has a full screen button of its own.
          VideoAttachment(:final youtubeId) => youtubeId == null,
          GeoAttachment() => true,
          AudioAttachment() || CodeAttachment() => false,
        };
    return Padding(
      key: ValueKey('${attachment.hashCode}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: grows ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (grows)
            Expanded(
              child: enlargeable ? _Enlargeable(child: content) : content,
            )
          else
            content,
          if (playback == MediaPlayback.paused &&
              (attachment is AudioAttachment || attachment is VideoAttachment))
            const _PausedByHost(),
          if (attachment case final ImageAttachment image
              when image.zoom && !fill && !StillMedia.of(context))
            Center(child: _zoomButton(context, image)),
          if (!attachment.hideDetails && attachment.caption.isNotEmpty)
            Text(
              attachment.caption,
              maxLines: fill ? 2 : null,
              overflow: fill ? TextOverflow.ellipsis : null,
              textAlign: fill ? TextAlign.center : null,
              style: const TextStyle(fontSize: 22),
            ),
        ],
      ),
    );
  }

  Widget _bounded(Widget child, {double extra = 0}) =>
      slot == null ? child : SizedBox(height: slot! + extra, child: child);

  Widget _code(String code, String language) {
    final view = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: HighlightView(
        code,
        language: language,
        theme: githubTheme,
        padding: const EdgeInsets.all(16),
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 22),
      ),
    );
    return fill ? SingleChildScrollView(primary: false, child: view) : view;
  }

  Widget _image(BuildContext context, ImageAttachment image) => SizedBox.expand(
    key: const ValueKey('media-image'),
    child: _AttachmentImage(asset: image.asset),
  );

  Widget _zoomButton(BuildContext context, ImageAttachment image) =>
      TextButton.icon(
        icon: const Icon(Icons.zoom_in),
        label: Text(context.tr('Vergrößern')),
        // Uses (almost) the whole screen: on a phone every pixel counts
        // for reading details of the picture.
        onPressed: () => showDialog<void>(
          context: context,
          barrierColor: Colors.black87,
          useSafeArea: false,
          builder: (context) => Dialog.fullscreen(
            key: const ValueKey('media-zoom-dialog'),
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 8,
                    child: _AttachmentImage(asset: image.asset),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: SafeArea(
                    child: IconButton.filledTonal(
                      tooltip: context.tr('Schließen'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _map(GeoAttachment geo) => SizedBox.expand(
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

/// A medium on the TV that can be shown on (almost) the whole screen.
///
/// The medium moves into the overlay with a [GlobalKey], so a running video
/// keeps its position and nothing loads again. Closes with the button, Esc
/// or a click next to it, and by itself when the medium leaves the stage.
class _Enlargeable extends StatefulWidget {
  const _Enlargeable({required this.child});

  final Widget child;

  @override
  State<_Enlargeable> createState() => _EnlargeableState();
}

class _EnlargeableState extends State<_Enlargeable> {
  final _controller = OverlayPortalController();
  final _medium = GlobalKey();
  bool _enlarged = false;

  void _toggle(bool enlarged) {
    setState(() => _enlarged = enlarged);
    enlarged ? _controller.show() : _controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    final medium = KeyedSubtree(key: _medium, child: widget.child);
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _toggle(false),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            key: const ValueKey('media-enlarged'),
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('media-enlarged-backdrop'),
                  onTap: () => _toggle(false),
                  child: const ColoredBox(color: Colors.black87),
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Material(
                      color: Colors.black,
                      child: _enlarged ? medium : null,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 32,
                top: 32,
                child: SafeArea(
                  child: PointerInterceptor(
                    child: IconButton.filledTonal(
                      key: const ValueKey('media-shrink'),
                      iconSize: 36,
                      tooltip: context.tr('Schließen'),
                      onPressed: () => _toggle(false),
                      icon: const Icon(Icons.fullscreen_exit),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_enlarged) medium,
          Positioned(
            right: 8,
            top: 8,
            // A video is a platform view on the web; it would take the click.
            child: PointerInterceptor(
              child: IconButton.filledTonal(
                key: const ValueKey('media-enlarge'),
                iconSize: 32,
                tooltip: context.tr('Vergrößern'),
                onPressed: _enlarged ? null : () => _toggle(true),
                icon: const Icon(Icons.fullscreen),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands for audio or video in a picture of another screen: no player is
/// created, so nothing loads and nothing makes a sound.
class _StillPlayer extends StatelessWidget {
  const _StillPlayer({required this.attachment});

  final MediaAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('still-player'),
      constraints: const BoxConstraints(minHeight: 72),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                attachment is AudioAttachment
                    ? Icons.music_note
                    : Icons.smart_display_outlined,
                size: 48,
              ),
              const SizedBox(width: 12),
              Text(
                context.tr(attachment is AudioAttachment ? 'Audio' : 'Video'),
                style: const TextStyle(fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Replaces a button without effect while the host paused the media.
class _PausedByHost extends StatelessWidget {
  const _PausedByHost();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pause_circle_outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.tr('Von der Spielleitung pausiert'),
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The browser wants a key press before it plays sound.
class _BlockedStart extends StatelessWidget {
  const _BlockedStart({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          key: const ValueKey('media-blocked'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(
                'Der Browser blockiert die Wiedergabe mit Ton. Bitte hier bestätigen.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              autofocus: true,
              onPressed: onStart,
              icon: const Icon(Icons.volume_up),
              label: Text(
                context.tr('Wiedergabe starten'),
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Reports a start the browser refused, and its end, to the surrounding
/// [MediaBlockReporter].
mixin _BlockedStartState<T extends StatefulWidget> on State<T> {
  MediaBlockReporter? _reporter;
  bool startBlocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reporter = MediaBlockReporter.maybeOf(context);
  }

  void setStartBlocked(bool blocked) {
    if (!mounted || startBlocked == blocked) return;
    setState(() => startBlocked = blocked);
    _reporter?.onChanged(this, blocked);
  }

  @override
  void dispose() {
    if (startBlocked) _reporter?.onChanged(this, false);
    super.dispose();
  }
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
) => Center(
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      mainAxisSize: MainAxisSize.min,
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
    ),
  ),
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
    this.playback = MediaPlayback.onDemand,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final MediaPlayback playback;
  final int playbackRevision;
  final int commandRevision;
  final AudioAttachment attachment;
  final Uri source;
  final VoidCallback onRetry;
  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView>
    with _BlockedStartState, FollowsHostSeek {
  final player = AudioPlayer();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The TV's own volume; elsewhere the device decides.
    if (MediaVolumeScope.of(context) case final volume?) {
      unawaited(player.setVolume(volume.effective).catchError((Object _) {}));
    }
    followHostSeek(widget.attachment.asset.id, (position) {
      unawaited(_seekTo(position));
    });
  }

  /// Jumps to [position]; a jump of the host is passed on to the TV.
  Future<void> _seekTo(Duration position, {bool report = false}) async {
    if (report) {
      MediaSeekReporter.of(context)
          ?.onSeek(widget.attachment.asset.id, position);
    }
    try {
      await player.seek(position);
    } on Object {
      /* Not loaded yet: the next jump works. */
    }
  }

  @override
  void didUpdateWidget(_AudioView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ready &&
        (oldWidget.playback != widget.playback ||
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
      switch (widget.playback) {
        case MediaPlayback.automatic:
          if (restart || player.processingState == ProcessingState.completed) {
            await player.pause();
            await player.seek(Duration.zero);
          }
          if (mounted && widget.playback == MediaPlayback.automatic) _start();
        case MediaPlayback.stopped || MediaPlayback.paused:
          await player.pause();
        case MediaPlayback.onDemand:
          // Nothing starts without a press on this device.
          break;
      }
    } on Object {
      /* Local play remains available. */
    }
  }

  void _start() {
    unawaited(
      player
          .play()
          .then((_) => setStartBlocked(false))
          .catchError((Object _) => setStartBlocked(true)),
    );
  }

  Future<void> _restartHere() async {
    await player.pause();
    await player.seek(Duration.zero);
    if (mounted && widget.playback != MediaPlayback.paused) _start();
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
    final locked = widget.playback == MediaPlayback.paused;
    final still = StillMedia.of(context);
    if (startBlocked && widget.playback == MediaPlayback.automatic) {
      return _BlockedStart(
        onStart: () {
          setStartBlocked(false);
          _start();
        },
      );
    }
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final playing =
            (snapshot.data?.playing ?? false) &&
            snapshot.data?.processingState != ProcessingState.completed;
        return Row(
          children: [
            IconButton(
              tooltip: locked
                  ? context.tr('Von der Spielleitung pausiert')
                  : playing
                  ? context.tr("Pause")
                  : context.tr("Abspielen"),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: locked || still
                  ? null
                  : () async {
                      if (playing) {
                        await player.pause();
                      } else {
                        if (player.processingState ==
                            ProcessingState.completed) {
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
              onPressed: locked || still
                  ? null
                  : () => unawaited(_restartHere()),
            ),
            Expanded(
              child: StreamBuilder<Duration?>(
                stream: player.durationStream,
                initialData: player.duration,
                builder: (context, duration) => StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, snapshot) => MediaTimeline(
                    position: snapshot.data ?? Duration.zero,
                    duration: duration.data,
                    onSeek: locked || still
                        ? null
                        : (position) =>
                              unawaited(_seekTo(position, report: true)),
                  ),
                ),
              ),
            ),
            if (widget.attachment.playbackLimitSeconds case final limit?)
              Text(
                context.tr('Limit: {0} s', [limit]),
                style: const TextStyle(fontSize: 18),
              ),
            const MediaVolumeControl(),
          ],
        );
      },
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({
    required this.mediaKey,
    required this.source,
    required this.onRetry,
    this.playback = MediaPlayback.onDemand,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final MediaPlayback playback;
  final int playbackRevision;
  final int commandRevision;
  final Uri source;
  final String mediaKey;
  final VoidCallback onRetry;
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView>
    with _BlockedStartState, FollowsHostSeek {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyVolume();
    followHostSeek(widget.mediaKey, (position) {
      unawaited(_seekTo(position));
    });
  }

  /// Jumps to [position]; a jump of the host is passed on to the TV.
  Future<void> _seekTo(Duration position, {bool report = false}) async {
    if (report) {
      MediaSeekReporter.of(context)?.onSeek(widget.mediaKey, position);
    }
    final video = controller;
    if (video == null || !video.value.isInitialized) return;
    try {
      await video.seekTo(position);
    } on Object {
      /* The next jump works. */
    }
  }

  /// The TV's own volume; elsewhere the device decides.
  void _applyVolume() {
    final volume = MediaVolumeScope.of(context);
    final video = controller;
    if (volume == null || video == null || !video.value.isInitialized) return;
    unawaited(video.setVolume(volume.effective).catchError((Object _) {}));
  }

  @override
  void didUpdateWidget(_VideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller?.value.isInitialized == true &&
        (oldWidget.playback != widget.playback ||
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
      switch (widget.playback) {
        case MediaPlayback.automatic:
          if (restart || video.value.position >= video.value.duration) {
            await video.seekTo(Duration.zero);
          }
          if (mounted && widget.playback == MediaPlayback.automatic) {
            await video.play();
          }
        case MediaPlayback.stopped || MediaPlayback.paused:
          await video.pause();
        case MediaPlayback.onDemand:
          // Nothing starts without a press on this device.
          break;
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
      if (mounted) _applyVolume();
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

  /// Whether the browser refused to start with sound (and the video itself is
  /// fine).
  bool get _refused {
    final description = controller?.value.errorDescription?.toLowerCase() ?? '';
    return widget.playback == MediaPlayback.automatic &&
        (description.contains('notallowed') ||
            description.contains('not allowed') ||
            description.contains('interact'));
  }

  void _update() {
    if (!mounted) return;
    final video = controller?.value;
    // A press on the browser's own controls must not undo the host's pause.
    if (widget.playback == MediaPlayback.paused &&
        (video?.isPlaying ?? false)) {
      unawaited(controller!.pause());
    }
    setState(() {});
    if (video != null) setStartBlocked(video.hasError && _refused);
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
    final locked = widget.playback == MediaPlayback.paused;
    final still = StillMedia.of(context);
    if (controller.value.hasError && _refused) {
      // The press counts as the interaction the browser asked for.
      return _BlockedStart(onStart: widget.onRetry);
    }
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
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: locked
                  ? context.tr('Von der Spielleitung pausiert')
                  : controller.value.isPlaying
                  ? context.tr("Pause")
                  : context.tr("Abspielen"),
              onPressed: locked || still
                  ? null
                  : () => controller.value.isPlaying
                        ? controller.pause()
                        : controller.play(),
              icon: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
            Expanded(
              child: MediaTimeline(
                position: controller.value.position,
                duration: controller.value.duration,
                onSeek: locked || still
                    ? null
                    : (position) => unawaited(_seekTo(position, report: true)),
              ),
            ),
            const MediaVolumeControl(),
          ],
        ),
      ],
    );
  }
}

class _YoutubeView extends StatefulWidget {
  const _YoutubeView({
    required this.id,
    this.hideDetails = false,
    this.playback = MediaPlayback.onDemand,
    this.playbackRevision = 0,
    this.commandRevision = 0,
  });
  final bool hideDetails;
  final MediaPlayback playback;
  final int playbackRevision;
  final int commandRevision;
  final String id;
  @override
  State<_YoutubeView> createState() => _YoutubeViewState();
}

class _YoutubeViewState extends State<_YoutubeView>
    with _BlockedStartState, FollowsHostSeek {
  MediaVolume? _volume;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _volume = MediaVolumeScope.of(context);
    _applyVolume();
    followHostSeek(_mediaKey, (position) => unawaited(_seekTo(position)));
  }

  String get _mediaKey => 'youtube:${widget.id}';

  /// Jumps to [position]; a jump of the host is passed on to the TV.
  Future<void> _seekTo(Duration position, {bool report = false}) async {
    if (report) MediaSeekReporter.of(context)?.onSeek(_mediaKey, position);
    try {
      await controller?.seekTo(
        seconds: position.inMilliseconds / 1000,
        allowSeekAhead: true,
      );
    } on Object {
      /* The next jump works. */
    }
  }

  /// The TV's own volume; elsewhere the device decides.
  void _applyVolume() {
    final volume = _volume;
    final player = controller;
    if (volume == null || player == null) return;
    final level = (volume.effective * 100).round();
    unawaited(
      (level == 0
              ? player.mute()
              : player.unMute().then((_) => player.setVolume(level)))
          .catchError((Object _) {}),
    );
  }

  @override
  void didUpdateWidget(_YoutubeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback ||
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
      switch (widget.playback) {
        case MediaPlayback.automatic:
          if (restart) {
            await player.loadVideoById(videoId: widget.id, startSeconds: 0);
          } else {
            await player.playVideo();
          }
          _watchStart();
        case MediaPlayback.stopped || MediaPlayback.paused:
          await player.pauseVideo();
        case MediaPlayback.onDemand:
          // Nothing starts without a press on this device.
          break;
      }
    } on Object {
      /* Keep the embedded player's local fallback available. */
    }
  }

  YoutubePlayerController? controller;
  bool _volumeApplied = false;
  StreamSubscription<YoutubePlayerValue>? _errors;
  Timer? _startWatch;

  /// YouTube does not report a refused start: nothing happens instead.
  void _watchStart() {
    _startWatch?.cancel();
    _startWatch = Timer(const Duration(seconds: 5), () {
      final value = controller?.value;
      if (!mounted ||
          value == null ||
          value.hasError ||
          widget.playback != MediaPlayback.automatic) {
        return;
      }
      setStartBlocked(
        value.playerState == youtube.PlayerState.unStarted ||
            value.playerState == youtube.PlayerState.cued,
      );
    });
  }

  /// Latched: the package clears `error` on the next state change, and YouTube
  /// follows an error with "unstarted", which would hide the reason again.
  YoutubeError _error = YoutubeError.none;
  bool get _openInBrowser => _youtubeOpensBrowser;

  @override
  void initState() {
    super.initState();
    if (_openInBrowser) return;
    final player = controller = YoutubePlayerController.fromVideoId(
      videoId: widget.id,
      autoPlay: widget.playback == MediaPlayback.automatic,
      params: YoutubePlayerParams(
        showControls: !widget.hideDetails,
        showFullscreenButton: true,
      ),
    );
    _errors = player.stream.listen((value) {
      if (!mounted) return;
      if (value.hasError && value.error != _error) {
        setState(() => _error = value.error);
      }
      if (value.playerState == youtube.PlayerState.playing) {
        // The iframe only takes a volume once its player exists.
        if (!_volumeApplied) {
          _volumeApplied = true;
          _applyVolume();
        }
        setStartBlocked(false);
        // A press on YouTube's own controls must not undo the host's pause.
        if (widget.playback == MediaPlayback.paused ||
            (widget.playback == MediaPlayback.stopped &&
                StillMedia.of(context))) {
          unawaited(player.pauseVideo());
        }
      }
    });
    if (widget.playback == MediaPlayback.automatic) _watchStart();
  }

  @override
  void dispose() {
    _errors?.cancel();
    _startWatch?.cancel();
    controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _openInBrowser
      ? FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoutubeOpenButton(id: widget.id),
              Text(
                context.tr(
                  'Öffnet den Browser; die Pause der Spielleitung wirkt dort nicht.',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
      : startBlocked && widget.playback == MediaPlayback.automatic
      ? _BlockedStart(
          onStart: () {
            setStartBlocked(false);
            unawaited(_applyPlayback(false));
          },
        )
      : _error != YoutubeError.none
      ? YoutubeUnavailableView(
          id: widget.id,
          error: _error,
          hideDetails: widget.hideDetails,
        )
      : _withControls(
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  YoutubePlayer(controller: controller!),
                  // While the host paused, nobody may press play in the frame.
                  if (widget.playback == MediaPlayback.paused ||
                      StillMedia.of(context))
                    PointerInterceptor(
                      child: const AbsorbPointer(child: SizedBox.expand()),
                    ),
                ],
              ),
            ),
          ),
        );

  /// The player with our timeline (and the TV's volume) below it. The
  /// timeline only stands in for YouTube's own controls, which "hide details"
  /// switches off; it shows no title.
  Widget _withControls(Widget player) {
    final locked =
        widget.playback == MediaPlayback.paused || StillMedia.of(context);
    final timeline = widget.hideDetails;
    if (!timeline && _volume == null) return player;
    return Column(
      children: [
        Expanded(child: player),
        Row(
          children: [
            if (!timeline)
              const Spacer()
            else
              Expanded(
                child: StreamBuilder<YoutubeVideoState>(
                  stream: controller!.videoStateStream,
                  builder: (context, snapshot) {
                    final duration = controller!.value.metaData.duration;
                    return MediaTimeline(
                      position: snapshot.data?.position ?? Duration.zero,
                      duration: duration == Duration.zero ? null : duration,
                      onSeek: locked
                          ? null
                          : (position) =>
                                unawaited(_seekTo(position, report: true)),
                    );
                  },
                ),
              ),
            const MediaVolumeControl(),
          ],
        ),
      ],
    );
  }
}

/// Opens the video on youtube.com (desktop hosts and refused embeds).
class YoutubeOpenButton extends StatelessWidget {
  const YoutubeOpenButton({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () =>
        launchUrl(Uri.https('www.youtube.com', '/watch', {'v': id})),
    icon: const Icon(Icons.open_in_new),
    label: Text(context.tr("YouTube-Video öffnen")),
  );
}

/// Replaces the player when YouTube refuses the video, instead of leaving an
/// empty box (the player's loading layer covers YouTube's own message).
@visibleForTesting
class YoutubeUnavailableView extends StatelessWidget {
  const YoutubeUnavailableView({
    required this.id,
    required this.error,
    this.hideDetails = false,
    super.key,
  });
  final String id;
  final YoutubeError error;

  /// Opening youtube.com would reveal the hidden title, so no link then.
  final bool hideDetails;

  @override
  Widget build(BuildContext context) {
    final (message, canOpen) = switch (error) {
      YoutubeError.notEmbeddable ||
      YoutubeError.sameAsNotEmbeddable ||
      YoutubeError.sameAsNotEmbeddable2 => (
        context.tr(
          "Dieses YouTube-Video darf nicht eingebettet werden. Der Besitzer "
          "erlaubt das Abspielen nur auf YouTube.",
        ),
        true,
      ),
      YoutubeError.videoNotFound || YoutubeError.cannotFindVideo => (
        context.tr("YouTube-Video nicht gefunden (entfernt oder privat)."),
        false,
      ),
      YoutubeError.none ||
      YoutubeError.invalidParam ||
      YoutubeError.html5Error ||
      YoutubeError.unknown => (
        context.tr("YouTube-Video kann nicht abgespielt werden."),
        true,
      ),
    };
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined, size: 48),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22),
                ),
                if (canOpen && !hideDetails) YoutubeOpenButton(id: id),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
