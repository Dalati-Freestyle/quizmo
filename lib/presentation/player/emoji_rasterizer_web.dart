import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const _size = 72;
final _cache = <String, Uint8List?>{};

/// Returns a PNG of [emoji] drawn with the browser's emoji font.
Uint8List? rasterizeEmoji(String emoji) => _cache.putIfAbsent(emoji, () {
  try {
    final canvas = web.HTMLCanvasElement()
      ..width = _size
      ..height = _size;
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context
      ..font =
          '${_size * 0.8}px "Apple Color Emoji","Segoe UI Emoji",'
          '"Noto Color Emoji","Twemoji Mozilla",sans-serif'
      ..textAlign = 'center'
      ..textBaseline = 'middle';
    final width = context.measureText(emoji).width;
    if (width > _size) {
      canvas.width = width.ceil();
      context
        ..font =
            '${_size * 0.8}px "Apple Color Emoji","Segoe UI Emoji",'
            '"Noto Color Emoji","Twemoji Mozilla",sans-serif'
        ..textAlign = 'center'
        ..textBaseline = 'middle';
    }
    context.fillText(emoji, canvas.width / 2, _size / 2 + _size * 0.04);
    final url = canvas.toDataURL('image/png');
    return base64Decode(url.substring(url.indexOf(',') + 1));
  } on Object {
    return null;
  }
});
