/// Host side of preloading media in the lobby.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/models.dart';
import '../net/chacha20.dart';

/// Every attachment guests may see in [game] right now: the active slide,
/// the question with its shown hints, the solution after the reveal and the
/// final review. Both the plain media route and the preload keys use it.
List<MediaAttachment> visibleGuestMedia(GameState game) {
  final round = game.round;
  final question = round.question;
  return [
    ...?game.activeSlide?.media,
    if (question != null) ...[
      ...question.media,
      for (final hint in round.shownHints) ...hint.media,
      if (round.status == RoundStatus.revealed && !game.resultsHidden)
        ...question.solutionMedia,
    ],
    if (game.showFinalReview)
      for (final completed in game.roundHistory)
        if (completed.question case final archived?) ...[
          ...archived.media,
          for (final hint in completed.shownHints) ...hint.media,
          ...archived.solutionMedia,
        ],
  ];
}

/// One upload of the quiz under its random handle and key.
final class PreloadEntry {
  PreloadEntry._(this.handle, this.asset, this.key);

  final String handle;
  final MediaAsset asset;
  final Uint8List key;

  static final _nonce = Uint8List(12);

  /// Bytes [start] to [end] (both included) of the encrypted file.
  Uint8List encryptedRange(int start, int end) => chacha20(
    key,
    _nonce,
    asset.bytes!.sublist(start, end + 1),
    offset: start,
  );

  MediaPreloadKey get wireKey => MediaPreloadKey(
    handle: handle,
    assetId: asset.id,
    key: base64Encode(key),
  );
}

/// The uploads of one hosted quiz with a random handle and key each, created
/// once per session. Keys never leave the host before [keysFor] says so.
final class MediaPreloadRegistry {
  MediaPreloadRegistry(GameState host, {Random? random}) {
    final generator = random ?? Random.secure();
    String randomHex(int bytes) => [
      for (var i = 0; i < bytes; i++)
        generator.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final media = [
      for (final question in host.questionBank) ...[
        ...question.media,
        for (final hint in question.hints) ...hint.media,
        ...question.solutionMedia,
      ],
      for (final slide in host.slides) ...slide.media,
    ];
    var online = 0;
    for (final attachment in media) {
      final asset = attachment.asset;
      if (asset == null || asset.bytes == null) {
        if (attachment is VideoAttachment || attachment is GeoAttachment) {
          online++;
        }
        continue;
      }
      if (_byAsset.containsKey(asset.id)) continue;
      final entry = PreloadEntry._(
        randomHex(32),
        asset,
        Uint8List.fromList([
          for (var i = 0; i < 32; i++) generator.nextInt(256),
        ]),
      );
      _byAsset[asset.id] = entry;
      _byHandle[entry.handle] = entry;
    }
    manifest = MediaPreloadManifest(
      items: [
        for (final entry in _byAsset.values)
          MediaPreloadItem(
            handle: entry.handle,
            size: entry.asset.bytes!.length,
          ),
      ],
      onlineCount: online,
    );
  }

  final _byAsset = <String, PreloadEntry>{};
  final _byHandle = <String, PreloadEntry>{};

  /// What guests may download in the lobby.
  late final MediaPreloadManifest manifest;

  /// The entry served under [handle], if any.
  PreloadEntry? byHandle(String handle) => _byHandle[handle];

  /// Keys of the uploads guests may see in [game].
  List<MediaPreloadKey> keysFor(GameState game) => [
    for (final id in {
      for (final attachment in visibleGuestMedia(game)) ?attachment.asset?.id,
    })
      if (_byAsset[id] case final entry?) entry.wireKey,
  ];
}

/// The preload progress of every connected device, for the host's lobby.
final class MediaPreloadStatuses {
  final _statuses =
      <String, ({String name, bool tv, MediaPreloadStatus status})>{};
  final _changes = StreamController<void>.broadcast();

  /// Emits with every change.
  Stream<void> get changes => _changes.stream;

  /// Devices by their connection, in the order they reported first.
  Map<String, ({String name, bool tv, MediaPreloadStatus status})> get all =>
      Map.unmodifiable(_statuses);

  void report(
    String deviceId, {
    required String name,
    required bool tv,
    required MediaPreloadStatus status,
  }) {
    final next = (name: name, tv: tv, status: status);
    if (_statuses[deviceId] == next) return;
    _statuses[deviceId] = next;
    if (!_changes.isClosed) _changes.add(null);
  }

  void remove(String deviceId) {
    if (_statuses.remove(deviceId) != null && !_changes.isClosed) {
      _changes.add(null);
    }
  }

  void close() => unawaited(_changes.close());
}
