import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

import '../../../core/models/models.dart';

Future<MediaAsset> readMediaUpload(PlatformFile file) async {
  // length() may fall back to reading the entire file. Only trust metadata here.
  final length = file.lengthSync();
  if (length == null) {
    throw const JsonContractException(
      'The picker could not determine the file size. Choose a local file whose size is available.',
    );
  }
  if (length <= 0 || length > maxMediaBytes) {
    throw const JsonContractException(
      'Datei zu groß oder nicht lesbar (maximal 20 MiB).',
    );
  }
  // Validate again after reading: a file may change after the picker returns.
  final bytes = await file.readAsBytes();
  final asset = MediaAsset.upload(bytes, file.extension ?? '');
  if (asset.mimeType.startsWith('image/') &&
      asset.mimeType != 'image/svg+xml') {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      descriptor.dispose();
    } on Object {
      throw const JsonContractException(
        'This image is damaged or cannot be decoded on this platform. Choose PNG, JPEG or WebP.',
      );
    } finally {
      buffer.dispose();
    }
  }
  return asset;
}

class OptimizedMediaImage {
  const OptimizedMediaImage({
    required this.asset,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
  });

  final MediaAsset asset;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;
}

Future<OptimizedMediaImage> optimizeMediaImage(
  Uint8List bytes, {
  required int maxDimension,
}) async {
  if (maxDimension < 1) throw ArgumentError.value(maxDimension, 'maxDimension');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final width = descriptor.width;
      final height = descriptor.height;
      final scale = (maxDimension / (width > height ? width : height)).clamp(
        0.0,
        1.0,
      );
      final targetWidth = (width * scale).round().clamp(1, width);
      final targetHeight = (height * scale).round().clamp(1, height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      try {
        if (codec.frameCount != 1) {
          throw const JsonContractException(
            'Animated images are kept unchanged. Optimization would remove animation.',
          );
        }
        final frame = await codec.getNextFrame();
        try {
          final encoded = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (encoded == null) {
            throw const JsonContractException('Image optimization failed.');
          }
          return OptimizedMediaImage(
            asset: MediaAsset.upload(
              encoded.buffer.asUint8List(
                encoded.offsetInBytes,
                encoded.lengthInBytes,
              ),
              'png',
            ),
            originalWidth: width,
            originalHeight: height,
            width: frame.image.width,
            height: frame.image.height,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
