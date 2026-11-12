/// Decodes a Wi-Fi QR code from a picture, e.g. a screenshot of Android's
/// "Share Wi-Fi" screen.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../../../core/models/guest_wifi.dart';

/// Returns the Wi-Fi credentials in [bytes] (PNG, JPEG, …) or `null`.
Future<GuestWifi?> decodeWifiQrImage(Uint8List bytes) async {
  final text = await compute(decodeQrText, bytes);
  return text == null ? null : GuestWifi.tryParseQr(text);
}

/// Decodes the first QR code in [bytes]; synchronous, run it off the UI.
@visibleForTesting
String? decodeQrText(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  // Phone screenshots are large; the finder patterns survive downscaling.
  if (image.width > 1400 || image.height > 1400) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 1400)
        : img.copyResize(image, height: 1400);
  }
  final pixels = image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List();
  final source = RGBLuminanceSource(image.width, image.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final bitmap in [
    BinaryBitmap(HybridBinarizer(source)),
    BinaryBitmap(GlobalHistogramBinarizer(source)),
    BinaryBitmap(HybridBinarizer(InvertedLuminanceSource(source))),
  ]) {
    try {
      return QRCodeReader().decode(bitmap, hints: hints).text;
    } on ReaderException {
      continue;
    }
  }
  return null;
}
