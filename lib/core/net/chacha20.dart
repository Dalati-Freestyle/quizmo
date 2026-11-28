/// ChaCha20 stream cipher (RFC 8439), pure Dart for every platform.
///
/// Media preloaded in the lobby travel encrypted; the key of a medium is only
/// sent when it may be seen. The cipher is a stream cipher, so any byte range
/// can be encrypted or decrypted on its own. Integrity comes from the SHA-256
/// asset ID, which the client checks after decrypting.
library;

import 'dart:typed_data';

/// XORs [data] with the ChaCha20 key stream of [key] (32 bytes) and [nonce]
/// (12 bytes), starting [offset] bytes into the stream. Encrypts and
/// decrypts alike; returns a new list.
Uint8List chacha20(
  Uint8List key,
  Uint8List nonce,
  Uint8List data, {
  int offset = 0,
}) {
  if (key.length != 32) throw ArgumentError('ChaCha20 needs a 32 byte key.');
  if (nonce.length != 12) {
    throw ArgumentError('ChaCha20 needs a 12 byte nonce.');
  }
  if (offset < 0) throw RangeError.value(offset, 'offset');
  final output = Uint8List(data.length);
  final keyWords = key.buffer.asByteData(key.offsetInBytes, 32);
  final nonceWords = nonce.buffer.asByteData(nonce.offsetInBytes, 12);
  final state = Uint32List(16)
    ..[0] = 0x61707865
    ..[1] = 0x3320646e
    ..[2] = 0x79622d32
    ..[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = keyWords.getUint32(i * 4, Endian.little);
  }
  for (var i = 0; i < 3; i++) {
    state[13 + i] = nonceWords.getUint32(i * 4, Endian.little);
  }
  final working = Uint32List(16);
  final block = Uint8List(64);
  final blockWords = block.buffer.asUint32List();
  final littleEndianHost = Endian.host == Endian.little;
  var counter = offset ~/ 64;
  var skip = offset % 64;
  var position = 0;
  while (position < data.length) {
    state[12] = counter;
    working.setAll(0, state);
    for (var round = 0; round < 10; round++) {
      _quarter(working, 0, 4, 8, 12);
      _quarter(working, 1, 5, 9, 13);
      _quarter(working, 2, 6, 10, 14);
      _quarter(working, 3, 7, 11, 15);
      _quarter(working, 0, 5, 10, 15);
      _quarter(working, 1, 6, 11, 12);
      _quarter(working, 2, 7, 8, 13);
      _quarter(working, 3, 4, 9, 14);
    }
    if (littleEndianHost) {
      for (var i = 0; i < 16; i++) {
        blockWords[i] = working[i] + state[i];
      }
    } else {
      final bytes = block.buffer.asByteData();
      for (var i = 0; i < 16; i++) {
        bytes.setUint32(
          i * 4,
          (working[i] + state[i]) & 0xffffffff,
          Endian.little,
        );
      }
    }
    final take = (64 - skip).clamp(0, data.length - position);
    for (var i = 0; i < take; i++) {
      output[position + i] = data[position + i] ^ block[skip + i];
    }
    position += take;
    skip = 0;
    counter = (counter + 1) & 0xffffffff;
  }
  return output;
}

void _quarter(Uint32List x, int a, int b, int c, int d) {
  // Writing into the Uint32List wraps every sum to 32 bits, also in
  // JavaScript.
  x[a] = x[a] + x[b];
  x[d] = _rotate(x[d] ^ x[a], 16);
  x[c] = x[c] + x[d];
  x[b] = _rotate(x[b] ^ x[c], 12);
  x[a] = x[a] + x[b];
  x[d] = _rotate(x[d] ^ x[a], 8);
  x[c] = x[c] + x[d];
  x[b] = _rotate(x[b] ^ x[c], 7);
}

int _rotate(int value, int bits) =>
    ((value << bits) | ((value & 0xffffffff) >>> (32 - bits))) & 0xffffffff;
