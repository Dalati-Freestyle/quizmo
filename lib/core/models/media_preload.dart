/// Preloading of media in the lobby (wire models).
///
/// Guests download every uploaded medium of the quiz encrypted before the
/// game, under a random handle that says nothing about the file. The key of a
/// medium only travels once guests may see it, so preloading never spoils a
/// question or a solution.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

/// One encrypted medium to preload.
final class MediaPreloadItem extends Equatable {
  const MediaPreloadItem({required this.handle, required this.size});

  factory MediaPreloadItem.fromJson(JsonMap json) => MediaPreloadItem(
    handle: json.readString('handle'),
    size: json.readInt('size'),
  );

  /// Random 64 hex characters; served at `/api/media/<handle>`.
  final String handle;

  /// Size in bytes.
  final int size;

  JsonMap toJson() => {'handle': handle, 'size': size};

  @override
  List<Object?> get props => [handle, size];
}

/// What a guest may preload: every upload of the quiz, plus the number of
/// online media (YouTube, maps) that cannot be preloaded.
final class MediaPreloadManifest extends Equatable {
  const MediaPreloadManifest({this.items = const [], this.onlineCount = 0});

  factory MediaPreloadManifest.fromJson(JsonMap json) => MediaPreloadManifest(
    items: json.readList('items', MediaPreloadItem.fromJson),
    onlineCount: json.readIntOrNull('onlineCount') ?? 0,
  );

  final List<MediaPreloadItem> items;
  final int onlineCount;

  int get totalBytes => items.fold(0, (sum, item) => sum + item.size);

  JsonMap toJson() => {
    'items': [for (final item in items) item.toJson()],
    'onlineCount': onlineCount,
  };

  @override
  List<Object?> get props => [items, onlineCount];
}

/// The key of a medium guests may see now: which asset the [handle] holds
/// and how to decrypt it (ChaCha20, base64 [key], zero nonce).
final class MediaPreloadKey extends Equatable {
  const MediaPreloadKey({
    required this.handle,
    required this.assetId,
    required this.key,
  });

  factory MediaPreloadKey.fromJson(JsonMap json) => MediaPreloadKey(
    handle: json.readString('handle'),
    assetId: json.readString('asset'),
    key: json.readString('key'),
  );

  final String handle;
  final String assetId;
  final String key;

  JsonMap toJson() => {'handle': handle, 'asset': assetId, 'key': key};

  @override
  List<Object?> get props => [handle, assetId, key];
}

/// How far a device got with preloading.
enum MediaPreloadPhase {
  /// Still downloading.
  loading,

  /// Everything is on the device.
  done,

  /// The player switched preloading off.
  disabled,

  /// A download failed and is retried.
  failed;

  static MediaPreloadPhase fromName(String name) => values.firstWhere(
    (phase) => phase.name == name,
    orElse: () => throw JsonContractException('Unknown preload phase "$name".'),
  );
}

/// Progress of one device, reported to the host.
final class MediaPreloadStatus extends Equatable {
  const MediaPreloadStatus({
    required this.phase,
    this.loadedFiles = 0,
    this.totalFiles = 0,
    this.loadedBytes = 0,
    this.totalBytes = 0,
  });

  factory MediaPreloadStatus.fromJson(JsonMap json) => MediaPreloadStatus(
    phase: MediaPreloadPhase.fromName(json.readString('phase')),
    loadedFiles: json.readInt('loadedFiles'),
    totalFiles: json.readInt('totalFiles'),
    loadedBytes: json.readInt('loadedBytes'),
    totalBytes: json.readInt('totalBytes'),
  );

  final MediaPreloadPhase phase;
  final int loadedFiles;
  final int totalFiles;
  final int loadedBytes;
  final int totalBytes;

  /// Share of the bytes on the device, 1 without media.
  double get fraction =>
      totalBytes <= 0 ? 1 : (loadedBytes / totalBytes).clamp(0.0, 1.0);

  JsonMap toJson() => {
    'phase': phase.name,
    'loadedFiles': loadedFiles,
    'totalFiles': totalFiles,
    'loadedBytes': loadedBytes,
    'totalBytes': totalBytes,
  };

  @override
  List<Object?> get props => [
    phase,
    loadedFiles,
    totalFiles,
    loadedBytes,
    totalBytes,
  ];
}
