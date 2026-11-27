/// Guest side of preloading media in the lobby.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'chacha20.dart';
import '../protocol/messages.dart';
import 'media_cache.dart';
import 'quiz_client.dart';

/// Downloads the encrypted uploads of a quiz one after another and opens
/// them once the host sends their key.
///
/// Survives reconnects: finished files stay, a half file continues where it
/// stopped. Without a key nothing can be read, so the files may sit on the
/// device long before their question.
final class MediaPreloader {
  MediaPreloader({
    http.Client Function()? createClient,
    this.timeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(seconds: 3),
  }) : _createClient = createClient ?? http.Client.new;

  final http.Client Function() _createClient;
  final Duration timeout;
  final Duration retryDelay;

  MediaPreloadManifest _manifest = const MediaPreloadManifest();
  Uri? _baseUri;
  bool _enabled = true;
  bool _disposed = false;
  bool _failed = false;
  bool _running = false;
  Timer? _retry;
  http.Client? _client;
  final _complete = <String, Uint8List>{};
  final _partial = <String, BytesBuilder>{};
  final _keys = <String, MediaPreloadKey>{};
  final _changes = StreamController<MediaPreloadStatus>.broadcast();

  static final _nonce = Uint8List(12);

  /// Emits [status] with every change.
  Stream<MediaPreloadStatus> get changes => _changes.stream;

  /// What the host offered.
  MediaPreloadManifest get manifest => _manifest;

  /// Progress of this device.
  MediaPreloadStatus get status {
    var bytes = 0;
    var files = 0;
    for (final item in _manifest.items) {
      if (_complete.containsKey(item.handle)) {
        files++;
        bytes += item.size;
      } else {
        bytes += _partial[item.handle]?.length ?? 0;
      }
    }
    return MediaPreloadStatus(
      phase: !_enabled
          ? MediaPreloadPhase.disabled
          : files == _manifest.items.length
          ? MediaPreloadPhase.done
          : _failed
          ? MediaPreloadPhase.failed
          : MediaPreloadPhase.loading,
      loadedFiles: files,
      totalFiles: _manifest.items.length,
      loadedBytes: bytes,
      totalBytes: _manifest.totalBytes,
    );
  }

  /// Starts (or continues) with [manifest] from the host at [baseUri]. A new
  /// session (other handles) drops the files of the old one.
  void offer(MediaPreloadManifest manifest, Uri baseUri) {
    if (_disposed) return;
    final handles = {for (final item in manifest.items) item.handle};
    _complete.removeWhere((handle, _) => !handles.contains(handle));
    _partial.removeWhere((handle, _) => !handles.contains(handle));
    if (manifest != _manifest) _keys.clear();
    _manifest = manifest;
    _baseUri = baseUri;
    _changed();
    _pump();
  }

  /// The address with a fresh access token after a reconnect.
  void updateBaseUri(Uri baseUri) {
    _baseUri = baseUri;
    _pump();
  }

  /// Switches downloading on or off; files already here stay usable.
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _retry?.cancel();
      _client?.close();
    }
    _changed();
    _pump();
  }

  /// Keys the host released with a snapshot.
  void addKeys(Iterable<MediaPreloadKey> keys) {
    for (final key in keys) {
      _keys[key.assetId] = key;
    }
  }

  /// [asset] from the preloaded files, `null` while it is not here or its key
  /// did not arrive. The content is checked against the asset ID.
  Future<MediaAsset?> take(MediaAsset asset) async {
    final key = _keys[asset.id];
    final cipher = key == null ? null : _complete[key.handle];
    if (key == null || cipher == null) return null;
    // Lets a frame through before the work.
    await Future<void>.delayed(Duration.zero);
    try {
      final plain = chacha20(base64Decode(key.key), _nonce, cipher);
      if (sha256.convert(plain).toString() != asset.id) return null;
      return MediaAsset(
        id: asset.id,
        mimeType: asset.mimeType,
        data: base64Encode(plain),
        sentAspectRatio: asset.aspectRatio,
      );
    } on Object {
      return null;
    }
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(status);
  }

  void _pump() {
    if (_running || _disposed || !_enabled || _baseUri == null) return;
    final next = _manifest.items
        .where((item) => !_complete.containsKey(item.handle))
        .firstOrNull;
    if (next == null) return;
    _running = true;
    _retry?.cancel();
    unawaited(
      _download(next).then(
        (_) {
          _running = false;
          _failed = false;
          _changed();
          _pump();
        },
        onError: (Object _) {
          _running = false;
          if (_disposed || !_enabled) return;
          _failed = true;
          _changed();
          _retry = Timer(retryDelay, _pump);
        },
      ),
    );
  }

  Future<void> _download(MediaPreloadItem item) async {
    final client = _client = _createClient();
    try {
      final builder = _partial.putIfAbsent(
        item.handle,
        () => BytesBuilder(copy: false),
      );
      while (builder.length < item.size) {
        if (_disposed || !_enabled) throw StateError('Preloading stopped.');
        final start = builder.length;
        final end = (start + mediaChunkBytes).clamp(0, item.size) - 1;
        final uri = sessionMediaUri(
          _baseUri!,
          MediaAsset(id: item.handle, mimeType: 'application/octet-stream'),
        );
        final response = await client
            .send(
              http.Request('GET', uri)..headers['range'] = 'bytes=$start-$end',
            )
            .timeout(timeout);
        if (response.statusCode != 206 && response.statusCode != 200) {
          throw StateError('Preload: HTTP ${response.statusCode}.');
        }
        if (response.statusCode == 200 && start != 0) {
          throw const FormatException('The host ignored the range.');
        }
        await for (final chunk in response.stream.timeout(timeout)) {
          if (_disposed || !_enabled) throw StateError('Preloading stopped.');
          builder.add(chunk);
          if (builder.length > item.size) {
            _partial.remove(item.handle);
            throw const FormatException('Damaged preload.');
          }
          _changed();
        }
        if (builder.length == start) {
          throw const FormatException('Empty preload range.');
        }
      }
      _complete[item.handle] = _partial.remove(item.handle)!.takeBytes();
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    _client?.close();
    _complete.clear();
    _partial.clear();
    _keys.clear();
    unawaited(_changes.close());
  }
}

/// Connects a [MediaPreloader] with the client of the current connection:
/// takes the host's offer and keys, reports the progress back (on every
/// change of the phase, otherwise at most once per [reportInterval]).
final class MediaPreloadLink {
  MediaPreloadLink(
    this.preloader, {
    this.reportInterval = const Duration(seconds: 1),
  }) {
    _changes = preloader.changes.listen((_) => _scheduleReport());
  }

  final MediaPreloader preloader;
  final Duration reportInterval;
  late final StreamSubscription<MediaPreloadStatus> _changes;
  QuizClient? _client;
  StreamSubscription<MediaPreloadManifest>? _offers;
  StreamSubscription<GameSnapshotMessage>? _snapshots;
  Timer? _report;
  MediaPreloadPhase? _reportedPhase;

  /// Follows [client] from now on.
  void attach(QuizClient client) {
    detach();
    _client = client;
    _reportedPhase = null;
    _offers = client.preloads.listen((manifest) {
      preloader.offer(manifest, client.mediaBaseUri);
      _sendReport();
    });
    _snapshots = client.snapshots.listen((snapshot) {
      preloader
        ..addKeys(snapshot.mediaKeys)
        ..updateBaseUri(client.mediaBaseUri);
    });
  }

  /// Stops following the current client; the files stay.
  void detach() {
    _offers?.cancel();
    _snapshots?.cancel();
    _offers = null;
    _snapshots = null;
    _report?.cancel();
    _report = null;
    _client = null;
  }

  void _scheduleReport() {
    if (preloader.manifest.items.isEmpty) return;
    if (preloader.status.phase != _reportedPhase) {
      _sendReport();
      return;
    }
    _report ??= Timer(reportInterval, _sendReport);
  }

  void _sendReport() {
    _report?.cancel();
    _report = null;
    final client = _client;
    if (client == null || preloader.manifest.items.isEmpty) return;
    final status = preloader.status;
    _reportedPhase = status.phase;
    client.reportPreload(status);
  }

  void dispose() {
    detach();
    unawaited(_changes.cancel());
  }
}
