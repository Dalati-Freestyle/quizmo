/// Reads the aspect ratio of pictures and MP4 videos from their bytes, so a
/// view can reserve the right space before anything is decoded.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Whether a JPEG photo carries GPS coordinates in its EXIF data, which would
/// tell players where it was taken.
bool hasGpsMetadata(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
  final data = ByteData.sublistView(bytes);
  var offset = 2;
  while (offset + 4 < bytes.length && bytes[offset] == 0xFF) {
    final marker = bytes[offset + 1];
    final length = data.getUint16(offset + 2);
    if (marker == 0xDA) break;
    if (marker == 0xE1 &&
        offset + 10 < bytes.length &&
        String.fromCharCodes(bytes, offset + 4, offset + 8) == 'Exif') {
      final tiff = offset + 10;
      if (tiff + 8 > bytes.length) return false;
      final endian = bytes[tiff] == 0x49 ? Endian.little : Endian.big;
      final directory = tiff + data.getUint32(tiff + 4, endian);
      if (directory + 2 > bytes.length) return false;
      final entries = data.getUint16(directory, endian);
      for (var i = 0; i < entries; i++) {
        final entry = directory + 2 + i * 12;
        if (entry + 2 > bytes.length) break;
        if (data.getUint16(entry, endian) == 0x8825) return true;
      }
      return false;
    }
    offset += 2 + length;
  }
  return false;
}

/// Width divided by height, `null` when [bytes] do not tell.
double? mediaAspectRatio(Uint8List bytes, String mimeType) {
  try {
    final size = switch (mimeType) {
      'image/png' => _png(bytes),
      'image/jpeg' => _jpeg(bytes),
      'image/webp' => _webp(bytes),
      'image/svg+xml' => _svg(bytes),
      'video/mp4' => _mp4(bytes),
      _ => null,
    };
    if (size == null || size.$1 <= 0 || size.$2 <= 0) return null;
    final ratio = size.$1 / size.$2;
    return ratio.isFinite && ratio > 0.01 && ratio < 100 ? ratio : null;
  } on Object {
    return null;
  }
}

(double, double)? _png(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
}

(double, double)? _jpeg(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var swap = false;
  var offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    final length = data.getUint16(offset + 2);
    if (marker == 0xE1) swap = _rotated(bytes, offset + 4, length - 2) ?? swap;
    final isFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrame) {
      final height = data.getUint16(offset + 5).toDouble();
      final width = data.getUint16(offset + 7).toDouble();
      return swap ? (height, width) : (width, height);
    }
    offset += 2 + length;
  }
  return null;
}

/// Whether the EXIF orientation turns the picture by 90 degrees.
bool? _rotated(Uint8List bytes, int start, int length) {
  if (length < 14 || start + length > bytes.length) return null;
  if (String.fromCharCodes(bytes, start, start + 4) != 'Exif') return null;
  final tiff = start + 6;
  final endian = bytes[tiff] == 0x49 ? Endian.little : Endian.big;
  final data = ByteData.sublistView(bytes, 0, start + length);
  final directory = tiff + data.getUint32(tiff + 4, endian);
  final entries = data.getUint16(directory, endian);
  for (var i = 0; i < entries; i++) {
    final entry = directory + 2 + i * 12;
    if (data.getUint16(entry, endian) == 0x0112) {
      return data.getUint16(entry + 8, endian) >= 5;
    }
  }
  return false;
}

(double, double)? _webp(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int uint24(int at) => bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16;
  return switch (String.fromCharCodes(bytes, 12, 16)) {
    'VP8 ' => (
      (data.getUint16(26, Endian.little) & 0x3FFF).toDouble(),
      (data.getUint16(28, Endian.little) & 0x3FFF).toDouble(),
    ),
    'VP8L' => () {
      final bits = data.getUint32(21, Endian.little);
      return (
        ((bits & 0x3FFF) + 1).toDouble(),
        (((bits >> 14) & 0x3FFF) + 1).toDouble(),
      );
    }(),
    'VP8X' => ((uint24(24) + 1).toDouble(), (uint24(27) + 1).toDouble()),
    _ => null,
  };
}

(double, double)? _svg(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final tag = RegExp(
    r'<svg\b[^>]*>',
    caseSensitive: false,
  ).firstMatch(text)?.group(0);
  if (tag == null) return null;
  double? length(String name) {
    final value = RegExp(
      '\\s$name\\s*=\\s*["\']([0-9.]+)(px)?["\']',
      caseSensitive: false,
    ).firstMatch(tag)?.group(1);
    return value == null ? null : double.tryParse(value);
  }

  final width = length('width');
  final height = length('height');
  if (width != null && height != null) return (width, height);
  final box = RegExp(
    'viewBox\\s*=\\s*["\']([^"\']+)["\']',
    caseSensitive: false,
  ).firstMatch(tag)?.group(1)?.trim().split(RegExp(r'[\s,]+'));
  if (box == null || box.length != 4) return null;
  return (double.parse(box[2]), double.parse(box[3]));
}

/// Looks for the first track header with a size near the start or the end,
/// where MP4 files keep their index.
(double, double)? _mp4(Uint8List bytes) {
  const head = 1 << 20;
  const tail = 4 << 20;
  return _trackSize(bytes, 0, bytes.length < head ? bytes.length : head) ??
      (bytes.length > head
          ? _trackSize(
              bytes,
              bytes.length > tail ? bytes.length - tail : 0,
              bytes.length,
            )
          : null);
}

(double, double)? _trackSize(Uint8List bytes, int from, int to) {
  final data = ByteData.sublistView(bytes);
  for (var i = from + 4; i + 92 < to; i++) {
    // "tkhd"
    if (bytes[i] != 0x74 ||
        bytes[i + 1] != 0x6B ||
        bytes[i + 2] != 0x68 ||
        bytes[i + 3] != 0x64) {
      continue;
    }
    // Version 1 headers use 64 bit times.
    final matrix = i + 4 + 4 + (bytes[i + 4] == 1 ? 32 : 20) + 16;
    if (matrix + 44 > to) continue;
    final width = data.getUint32(matrix + 36) / 65536;
    final height = data.getUint32(matrix + 40) / 65536;
    if (width <= 0 || height <= 0) continue;
    final turned = data.getInt32(matrix) == 0 && data.getInt32(matrix + 4) != 0;
    return turned ? (height, width) : (width, height);
  }
  return null;
}
