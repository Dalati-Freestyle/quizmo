import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/media_upload.dart';

final class TestMediaFile extends PlatformFile {
  TestMediaFile({
    this.size,
    this.statSize,
    this.name = 'image.png',
    Uint8List? bytes,
  }) : bytes = bytes ?? Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  /// Size reported by the picker itself (null on Windows).
  final int? size;

  /// Size the file system reports through [length].
  final int? statSize;
  final Uint8List bytes;
  bool read = false;
  @override
  final String name;
  @override
  Uri get uri => Uri.parse('file:///image.png');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => size;
  @override
  Future<int?> length() async => size ?? statSize;
  @override
  Stream<Uint8List> readAsByteStream() =>
      throw StateError('Must not read as a stream');
  @override
  Future<Uint8List> readAsBytes() async {
    read = true;
    return bytes;
  }
}

Future<Uint8List> imageBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff4267ab), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('readMediaUpload', () {
    for (final size in [maxMediaBytes + 1, 0, -1, null]) {
      test('rejects size $size before any byte read', () async {
        final file = TestMediaFile(size: size);
        await expectLater(
          readMediaUpload(file),
          throwsA(isA<JsonContractException>()),
        );
        expect(file.read, isFalse);
      });
    }

    for (final statSize in [maxMediaBytes + 1, 0, null]) {
      test(
        'rejects file system size $statSize without picker metadata',
        () async {
          final file = TestMediaFile(statSize: statSize);
          await expectLater(
            readMediaUpload(file),
            throwsA(isA<JsonContractException>()),
          );
          expect(file.read, isFalse);
        },
      );
    }

    test('accepts a picked file without size metadata (Windows)', () async {
      final bytes = await imageBytes(2, 1);
      final file = TestMediaFile(statSize: bytes.length, bytes: bytes);
      final asset = await readMediaUpload(file);
      expect(asset.bytes, orderedEquals(bytes));
    });

    test('without a limit (advanced setting) larger files are read', () async {
      final bytes = Uint8List(maxMediaBytes + 1)
        ..setAll(0, const [137, 80, 78, 71, 13, 10, 26, 10]);
      final file = TestMediaFile(size: bytes.length, bytes: bytes);
      await expectLater(
        readMediaUpload(file),
        throwsA(
          isA<JsonContractException>().having(
            (e) => e.message,
            'message',
            contains('Erweiterte Einstellungen'),
          ),
        ),
      );
      expect(file.read, isFalse);
      // The PNG signature alone does not decode; reaching that check proves
      // the size limit is gone.
      await expectLater(
        readMediaUpload(file, maxBytes: null),
        throwsA(
          isA<JsonContractException>().having(
            (e) => e.message,
            'message',
            contains('cannot be decoded'),
          ),
        ),
      );
      expect(file.read, isTrue);
    });

    test('allows the exact 20 MiB metadata boundary', () async {
      final file = TestMediaFile(
        size: maxMediaBytes,
        bytes: await imageBytes(2, 1),
      );
      final asset = await readMediaUpload(file);
      expect(file.read, isTrue);
      expect(asset.bytes, orderedEquals(file.bytes));
    });

    test(
      'rejects a matching PNG signature with an invalid image body',
      () async {
        await expectLater(
          readMediaUpload(TestMediaFile(size: 8)),
          throwsA(isA<JsonContractException>()),
        );
      },
    );

    test(
      'validates actual bytes even when picker metadata reports less',
      () async {
        final file = TestMediaFile(
          size: 8,
          bytes: Uint8List(maxMediaBytes + 1),
        );
        await expectLater(
          readMediaUpload(file),
          throwsA(isA<JsonContractException>()),
        );
      },
    );

    test('rejects a disguised unsupported format', () async {
      final file = TestMediaFile(size: 8, bytes: Uint8List(8));
      await expectLater(
        readMediaUpload(file),
        throwsA(isA<JsonContractException>()),
      );
    });

    test('rejects an unsupported extension', () async {
      final file = TestMediaFile(size: 8, name: 'image.exe');
      await expectLater(
        readMediaUpload(file),
        throwsA(isA<JsonContractException>()),
      );
    });
  });

  group('optimizeMediaImage', () {
    test('preserves landscape aspect ratio and produces valid PNG', () async {
      final original = await imageBytes(120, 60);
      final copy = await optimizeMediaImage(original, maxDimension: 40);
      expect((copy.width, copy.height), (40, 20));
      expect((copy.originalWidth, copy.originalHeight), (120, 60));
      expect(copy.asset.mimeType, 'image/png');
      expect(copy.asset.validate, returnsNormally);
    });

    test('preserves portrait aspect ratio without upscaling', () async {
      final original = await imageBytes(20, 40);
      final smaller = await optimizeMediaImage(original, maxDimension: 10);
      expect((smaller.width, smaller.height), (5, 10));
      final copy = await optimizeMediaImage(original, maxDimension: 100);
      expect((copy.width, copy.height), (20, 40));
    });

    test('rejects invalid limits and corrupt image content', () async {
      await expectLater(
        optimizeMediaImage(Uint8List(8), maxDimension: 0),
        throwsArgumentError,
      );
      await expectLater(
        optimizeMediaImage(Uint8List(8), maxDimension: 100),
        throwsA(anything),
      );
    });
  });
}
