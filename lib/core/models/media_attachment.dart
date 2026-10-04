import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

import 'json.dart';

const maxMediaBytes = 20 * 1024 * 1024;

final class MediaAsset extends Equatable {
  const MediaAsset({required this.id, required this.mimeType, this.data});
  final String id;
  final String mimeType;
  final String? data;
  Uint8List? get bytes => data == null ? null : base64Decode(data!);
  String get route => '/api/media/$id';

  factory MediaAsset.upload(Uint8List bytes, String extension) {
    if (bytes.isEmpty || bytes.length > maxMediaBytes) {
      throw const JsonContractException(
        'Medien dürfen maximal 20 MiB groß sein.',
      );
    }
    final mime = switch (extension.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'mp4' => 'video/mp4',
      _ => throw const JsonContractException(
        'Nicht unterstütztes Dateiformat.',
      ),
    };
    final asset = MediaAsset(
      id: sha256.convert(bytes).toString(),
      mimeType: mime,
      data: base64Encode(bytes),
    );
    asset.validate();
    return asset;
  }

  factory MediaAsset.fromJson(JsonMap json) {
    final asset = MediaAsset(
      id: json.readString('id'),
      mimeType: json.readString('mimeType'),
      data: json.readStringOrNull('data'),
    );
    asset.validate();
    return asset;
  }

  void validate() {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !const {
          'image/png',
          'image/jpeg',
          'image/webp',
          'image/svg+xml',
          'audio/mpeg',
          'audio/wav',
          'audio/ogg',
          'video/mp4',
        }.contains(mimeType)) {
      throw const JsonContractException('Ungültiges Medien-Asset.');
    }
    if (data == null) return;
    if (data!.length > (maxMediaBytes * 4 / 3).ceil() + 4) {
      throw const JsonContractException('Medien-Asset zu groß.');
    }
    final decoded = bytes!;
    if (decoded.isEmpty ||
        decoded.length > maxMediaBytes ||
        sha256.convert(decoded).toString() != id) {
      throw const JsonContractException('Beschädigtes Medien-Asset.');
    }
    bool starts(List<int> signature) =>
        decoded.length >= signature.length &&
        signature.indexed.every((e) => decoded[e.$1] == e.$2);
    String chunk(int start, int end) => decoded.length < end
        ? ''
        : String.fromCharCodes(decoded.sublist(start, end));
    final valid = switch (mimeType) {
      'image/png' => starts([137, 80, 78, 71, 13, 10, 26, 10]),
      'image/jpeg' => starts([255, 216, 255]),
      'image/webp' => chunk(0, 4) == 'RIFF' && chunk(8, 12) == 'WEBP',
      'audio/wav' => chunk(0, 4) == 'RIFF' && chunk(8, 12) == 'WAVE',
      'audio/ogg' => chunk(0, 4) == 'OggS',
      'audio/mpeg' =>
        chunk(0, 3) == 'ID3' ||
            decoded.length > 1 && decoded[0] == 255 && decoded[1] & 224 == 224,
      'video/mp4' => chunk(4, 8) == 'ftyp',
      'image/svg+xml' => _safeSvg(utf8.decode(decoded)),
      _ => false,
    };
    if (!valid) {
      throw const JsonContractException(
        'Dateiinhalt passt nicht zum Medienformat oder enthält unsicheres SVG.',
      );
    }
  }

  JsonMap toJson({bool includeData = true}) => {
    'id': id,
    'mimeType': mimeType,
    if (includeData && data != null) 'data': data,
  };
  @override
  List<Object?> get props => [id, mimeType, data];
}

bool _safeSvg(String svg) =>
    svg.contains(RegExp(r'<svg\b', caseSensitive: false)) &&
    !svg.contains(
      RegExp(
        r'<\s*(?:[\w.-]+:)?(script|foreignObject|iframe|image|use|style|animate|set)\b|\bon\w+\s*=|href\s*=|url\s*\(|<!DOCTYPE|<!ENTITY',
        caseSensitive: false,
      ),
    );

sealed class MediaAttachment extends Equatable {
  const MediaAttachment({this.caption = ''});
  final String caption;
  MediaAsset? get asset => null;
  JsonMap toJson({bool includeData = true});
  static MediaAttachment fromJson(JsonMap json) => switch (json.readString(
    'type',
  )) {
    'image' => ImageAttachment(
      asset: MediaAsset.fromJson(json.readObject('asset')),
      caption: json.readString('caption'),
      zoom: json.readBool('zoom', orElse: true),
    ),
    'audio' => AudioAttachment(
      asset: MediaAsset.fromJson(json.readObject('asset')),
      caption: json.readString('caption'),
      playbackLimitSeconds: json.readIntOrNull('playbackLimitSeconds'),
    ),
    'video' => VideoAttachment(
      asset: json['asset'] == null
          ? null
          : MediaAsset.fromJson(json.readObject('asset')),
      youtubeId: json.readStringOrNull('youtubeId'),
      caption: json.readString('caption'),
    ),
    'code' => CodeAttachment(
      code: json.readString('code'),
      language: json.readString('language'),
      caption: json.readString('caption'),
    ),
    'geo' => GeoAttachment(
      latitude: readFiniteDouble(json, 'latitude'),
      longitude: readFiniteDouble(json, 'longitude'),
      zoom: readFiniteDouble(json, 'zoom'),
      caption: json.readString('caption'),
    ),
    final tag => throw JsonContractException('Unbekannter Medientyp "$tag".'),
  };
  List<String> get validationErrors => [
    ...switch (this) {
      ImageAttachment(:final asset) => [
        if (!asset.mimeType.startsWith('image/')) 'Bildformat erwartet.',
      ],
      AudioAttachment(:final asset, :final playbackLimitSeconds) => [
        if (!asset.mimeType.startsWith('audio/')) 'Audioformat erwartet.',
        if (playbackLimitSeconds != null && playbackLimitSeconds <= 0)
          'Abspiellimit muss positiv sein.',
      ],
      VideoAttachment(:final asset, :final youtubeId) => [
        if ((asset == null) == (youtubeId == null) ||
            asset != null && asset.mimeType != 'video/mp4' ||
            youtubeId != null &&
                !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(youtubeId))
          'MP4 oder gültige YouTube-ID angeben.',
      ],
      CodeAttachment(:final code, :final language) => [
        if (code.isEmpty ||
            code.length > 100000 ||
            !RegExp(r'^[a-zA-Z0-9_+-]{1,30}$').hasMatch(language))
          'Code und gültige Sprache angeben.',
      ],
      GeoAttachment(:final latitude, :final longitude, :final zoom) => [
        if (!latitude.isFinite ||
            latitude.abs() > 90 ||
            !longitude.isFinite ||
            longitude.abs() > 180 ||
            !zoom.isFinite ||
            zoom < 1 ||
            zoom > 18)
          'Ungültiger Kartenausschnitt.',
      ],
    },
  ];
}

final class ImageAttachment extends MediaAttachment {
  const ImageAttachment({required this.asset, this.zoom = true, super.caption});
  @override
  final MediaAsset asset;
  final bool zoom;
  @override
  JsonMap toJson({bool includeData = true}) => {
    'type': 'image',
    'caption': caption,
    'zoom': zoom,
    'asset': asset.toJson(includeData: includeData),
  };
  @override
  List<Object?> get props => [asset, zoom, caption];
}

final class AudioAttachment extends MediaAttachment {
  const AudioAttachment({
    required this.asset,
    this.playbackLimitSeconds,
    super.caption,
  });
  @override
  final MediaAsset asset;
  final int? playbackLimitSeconds;
  @override
  JsonMap toJson({bool includeData = true}) => {
    'type': 'audio',
    'caption': caption,
    'playbackLimitSeconds': playbackLimitSeconds,
    'asset': asset.toJson(includeData: includeData),
  };
  @override
  List<Object?> get props => [asset, playbackLimitSeconds, caption];
}

final class VideoAttachment extends MediaAttachment {
  const VideoAttachment({this.asset, this.youtubeId, super.caption});
  @override
  final MediaAsset? asset;
  final String? youtubeId;
  @override
  JsonMap toJson({bool includeData = true}) => {
    'type': 'video',
    'caption': caption,
    'asset': asset?.toJson(includeData: includeData),
    'youtubeId': youtubeId,
  };
  @override
  List<Object?> get props => [asset, youtubeId, caption];
}

final class CodeAttachment extends MediaAttachment {
  const CodeAttachment({
    required this.code,
    this.language = 'dart',
    super.caption,
  });
  final String code;
  final String language;
  @override
  JsonMap toJson({bool includeData = true}) => {
    'type': 'code',
    'caption': caption,
    'code': code,
    'language': language,
  };
  @override
  List<Object?> get props => [code, language, caption];
}

final class GeoAttachment extends MediaAttachment {
  const GeoAttachment({
    required this.latitude,
    required this.longitude,
    this.zoom = 8,
    super.caption,
  });
  final double latitude;
  final double longitude;
  final double zoom;
  @override
  JsonMap toJson({bool includeData = true}) => {
    'type': 'geo',
    'caption': caption,
    'latitude': latitude,
    'longitude': longitude,
    'zoom': zoom,
  };
  @override
  List<Object?> get props => [latitude, longitude, zoom, caption];
}

List<MediaAttachment> readMedia(JsonMap json, String key) =>
    json[key] == null ? const [] : json.readList(key, MediaAttachment.fromJson);
