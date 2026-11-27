import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/net/chacha20.dart';

Uint8List hex(String text) {
  final clean = text.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));

  test('matches the block of RFC 8439, 2.3.2', () {
    final nonce = hex('000000090000004a00000000');
    // Counter 1 = offset 64; XOR with zeros yields the key stream.
    final stream = chacha20(key, nonce, Uint8List(64), offset: 64);
    expect(stream.sublist(0, 16), hex('10f1e7e4d13b5915500fdd1fa32071c4'));
    expect(stream.sublist(48), hex('b5129cd1de164eb9cbd083e8a2503c4e'));
  });

  test('matches the encryption of RFC 8439, 2.4.2', () {
    final nonce = hex('000000000000004a00000000');
    final plain = Uint8List.fromList(
      utf8.encode(
        "Ladies and Gentlemen of the class of '99: If I could offer you "
        'only one tip for the future, sunscreen would be it.',
      ),
    );
    final cipher = chacha20(key, nonce, plain, offset: 64);
    expect(cipher.sublist(0, 16), hex('6e2e359a2568f98041ba0728dd0d6981'));
    expect(cipher.sublist(cipher.length - 4), hex('5e42874d'));
    expect(chacha20(key, nonce, cipher, offset: 64), plain);
  });

  test('any range decrypts on its own', () {
    final nonce = Uint8List(12);
    final plain = Uint8List.fromList(List.generate(1000, (i) => i * 7));
    final whole = chacha20(key, nonce, plain);
    for (final (start, end) in [(0, 1), (3, 70), (64, 128), (130, 1000)]) {
      expect(
        chacha20(key, nonce, whole.sublist(start, end), offset: start),
        plain.sublist(start, end),
        reason: '$start-$end',
      );
    }
    expect(whole, isNot(plain));
  });
}
