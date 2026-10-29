import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/media_attachment.dart';
import 'session_uri.dart';

Uri sessionMediaUri(Uri base, MediaAsset asset) => base.replace(
  path: '${sessionUri(base).path}${asset.route}',
  queryParameters: {'access': ?base.queryParameters['access']},
  fragment: '',
);

final class MediaDownloadProgress {
  const MediaDownloadProgress(this.received, this.total);
  final int received;
  final int? total;
  double? get fraction =>
      total == null || total == 0 ? null : (received / total!).clamp(0, 1);
}

/// An in-memory LRU owned by one admitted session, never shared across rooms.
final class SessionMediaCache {
  SessionMediaCache({
    required this.baseUri,
    this.maxBytes = 60 * 1024 * 1024,
    this.timeout = const Duration(seconds: 30),
    http.Client Function()? createClient,
  }) : _createClient = createClient ?? http.Client.new;

  final Uri baseUri;
  final int maxBytes;
  final Duration timeout;
  final http.Client Function() _createClient;
  final _assets = <String, MediaAsset>{};
  final _pending = <String, Future<MediaAsset>>{};
  final _clients = <http.Client>{};
  final _waiting = Queue<Completer<void>>();
  final _progress = <String, MediaDownloadProgress>{};
  final _updates = StreamController<void>.broadcast();
  int _bytes = 0;
  int _activeDownloads = 0;
  bool _closed = false;

  Stream<void> get updates => _updates.stream;
  MediaDownloadProgress? progress(String id) => _progress[id];

  Future<MediaAsset> load(MediaAsset asset) {
    if (_closed) return Future.error(StateError('Media session closed.'));
    if (asset.data != null) return Future.value(asset);
    final cached = _assets.remove(asset.id);
    if (cached != null) {
      _assets[asset.id] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(asset.id, () async {
      try {
        await _acquireDownload();
        try {
          if (_closed) throw StateError('Media session closed.');
          return await _download(asset);
        } finally {
          if (_waiting.isNotEmpty) {
            _waiting.removeFirst().complete();
          } else {
            _activeDownloads--;
          }
        }
      } finally {
        _pending.remove(asset.id);
        _progress.remove(asset.id);
      }
    });
  }

  Future<void> _acquireDownload() async {
    if (_activeDownloads < 4) {
      _activeDownloads++;
      return;
    }
    final ready = Completer<void>();
    _waiting.add(ready);
    try {
      await ready.future.timeout(timeout);
    } finally {
      _waiting.remove(ready);
    }
  }

  Future<MediaAsset> _download(MediaAsset asset) async {
    final client = _createClient();
    _clients.add(client);
    var active = true;
    try {
      final loaded = await (() async {
        final response = await client.send(
          http.Request('GET', sessionMediaUri(baseUri, asset)),
        );
        if (response.statusCode != 200) {
          throw StateError('Media download: HTTP ${response.statusCode}.');
        }
        final total = response.contentLength;
        if (total != null && (total <= 0 || total > maxMediaBytes)) {
          throw const FormatException('Media exceeds the 20 MiB limit.');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (_closed || !active) throw StateError('Media download cancelled.');
          if (builder.length + chunk.length > maxMediaBytes) {
            throw const FormatException('Media exceeds the 20 MiB limit.');
          }
          builder.add(chunk);
          _progress[asset.id] = MediaDownloadProgress(builder.length, total);
          _updates.add(null);
        }
        if (_closed || !active) throw StateError('Media download cancelled.');
        final bytes = builder.takeBytes();
        if (bytes.isEmpty ||
            total != null && total != bytes.length ||
            sha256.convert(bytes).toString() != asset.id) {
          throw const FormatException('Incomplete or damaged media download.');
        }
        final loaded = MediaAsset(
          id: asset.id,
          mimeType: asset.mimeType,
          data: base64Encode(bytes),
        );
        if (!_closed && loaded.data!.length <= maxBytes) {
          while (_assets.isNotEmpty &&
              _bytes + loaded.data!.length > maxBytes) {
            _bytes -= _assets.remove(_assets.keys.first)!.data!.length;
          }
          _assets[asset.id] = loaded;
          _bytes += loaded.data!.length;
        }
        return loaded;
      })().timeout(timeout);
      if (_closed) throw StateError('Media session closed.');
      return loaded;
    } finally {
      active = false;
      client.close();
      _clients.remove(client);
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final ready in _waiting) {
      ready.completeError(StateError('Media session closed.'));
    }
    _waiting.clear();
    for (final client in _clients) {
      client.close();
    }
    _assets.clear();
    _progress.clear();
    _bytes = 0;
    unawaited(_updates.close());
  }
}
