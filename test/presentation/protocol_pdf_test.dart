import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:quizmo/core/models/game_protocol.dart';
import 'package:quizmo/presentation/player/protocol_pdf.dart';

const _protocol = GameProtocol(
  title: 'Quizabend 🎉 Größe',
  generatedAtMicros: 1700000000000000,
  format: ProtocolFormat.poker,
  teamMode: true,
  standings: [
    ProtocolStanding(
      id: 'a',
      name: 'Füchse',
      isTeam: true,
      score: 120,
      place: 1,
      memberIds: ['p1'],
      memberNames: ['Jürgen'],
    ),
    ProtocolStanding(
      id: 'b',
      name: 'Bären',
      isTeam: true,
      score: 120,
      place: 1,
    ),
  ],
  questions: [
    ProtocolQuestion(
      number: 1,
      questionId: 'q',
      prompt: 'Wie heißt die Hauptstadt? 🏙️',
      solution: 'Wahr',
      category: 'Städte',
      answers: [
        ProtocolAnswer(
          playerId: 'p1',
          player: 'Jürgen',
          team: 'Füchse',
          answer: 'Berlin 🇩🇪',
          status: ProtocolAnswerStatus.correct,
          points: 20,
          wager: 10,
        ),
      ],
    ),
  ],
  corrections: [
    ProtocolCorrection(
      atMicros: 1700000000000000,
      kind: ProtocolCorrectionKind.chips,
      target: 'Bären',
      before: 100,
      after: 120,
      delta: 20,
      reason: '🤷',
    ),
  ],
);

String _tr(String key, [List<Object?> args = const []]) {
  var text = key;
  for (final (index, arg) in args.indexed) {
    text = text.replaceAll('{$index}', '$arg');
  }
  return text;
}

void main() {
  late pw.Font regular;
  late pw.Font bold;

  setUpAll(() {
    ByteData font(String name) => ByteData.sublistView(
      File('assets/fonts/protocol/$name').readAsBytesSync(),
    );
    regular = pw.Font.ttf(font('Roboto-Regular.ttf'));
    bold = pw.Font.ttf(font('Roboto-Bold.ttf'));
  });

  test('builds a PDF with umlauts and rasterized emoji', () async {
    final emojis = <String>[];
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 4, height: 4)),
    );
    final bytes = await buildProtocolPdf(
      _protocol,
      tr: _tr,
      regular: regular,
      bold: bold,
      emoji: (emoji) {
        emojis.add(emoji);
        return png;
      },
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    expect(emojis, containsAll(['🎉', '🏙️', '🇩🇪', '🤷']));
  });

  test('builds without an emoji renderer', () async {
    final bytes = await buildProtocolPdf(
      _protocol,
      tr: _tr,
      regular: regular,
      bold: bold,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test(
    'draws emoji with the bundled Noto Emoji font without a renderer',
    () async {
      final emojiFont = pw.Font.ttf(
        ByteData.sublistView(
          File('assets/fonts/protocol/NotoEmoji-Regular.ttf').readAsBytesSync(),
        ),
      );
      final missing = <String>[];
      final bytes = await runZoned(
        () => buildProtocolPdf(
          _protocol,
          tr: _tr,
          regular: regular,
          bold: bold,
          emojiFont: emojiFont,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) {
            if (line.contains('Unable to find a font')) missing.add(line);
          },
        ),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(missing, isEmpty);
    },
  );

  test('file names are safe', () {
    expect(protocolFileName(_protocol), 'Quizabend-Größe-protokoll.pdf');
  });
}
