/// Human readable PDF of a finished game's protocol.
///
/// Loaded only through a deferred import from the final page, so the `pdf`
/// package never slows down joining. The PDF is built entirely in the player
/// from the protocol received at the end of the game, therefore it keeps
/// working after the host has closed the session.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/game_protocol.dart';
import '../common/protocol_labels.dart';
import 'emoji_rasterizer.dart';

/// Matches emoji (incl. ZWJ sequences, flags and keycaps).
final _emoji = RegExp(
  // The analyzer does not know Unicode property escapes; they are valid with
  // `unicode: true` (covered by protocol_pdf_test.dart).
  // ignore: valid_regexps
  r'(?:\p{Regional_Indicator}{2}'
  r'|\p{Extended_Pictographic}(?:\u{FE0F}|\p{Emoji_Modifier})*'
  r'(?:\u{200D}\p{Extended_Pictographic}(?:\u{FE0F}|\p{Emoji_Modifier})*)*'
  r'|[0-9#*]\u{FE0F}?\u{20E3})',
  unicode: true,
);

/// Builds the PDF bytes of [protocol].
///
/// [emoji] renders an emoji to a colour PNG (browser only). Emoji it cannot
/// render are drawn with [emojiFont] (monochrome Noto Emoji) when given.
Future<Uint8List> buildProtocolPdf(
  GameProtocol protocol, {
  required Translate tr,
  required pw.Font regular,
  required pw.Font bold,
  Uint8List? Function(String emoji)? emoji,
  pw.Font? emojiFont,
}) {
  final fallback = [?emojiFont];
  final theme = pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    fontFallback: fallback,
  );
  final base = pw.TextStyle(font: regular, fontSize: 10);
  final strong = pw.TextStyle(font: bold, fontSize: 10);

  pw.Widget text(String value, [pw.TextStyle? style]) {
    final textStyle = style ?? base;
    final size = textStyle.fontSize ?? 10;
    final spans = <pw.InlineSpan>[];
    var last = 0;
    for (final match in _emoji.allMatches(value)) {
      final glyph = match.group(0)!;
      final image = glyph.runes.length == 1 && glyph.runes.first < 0x2100
          ? null
          : emoji?.call(glyph);
      if (image == null) continue;
      if (match.start > last) {
        spans.add(pw.TextSpan(text: value.substring(last, match.start)));
      }
      spans.add(
        pw.WidgetSpan(
          child: pw.Image(pw.MemoryImage(image), height: size * 1.1),
          baseline: -size * 0.15,
        ),
      );
      last = match.end;
    }
    if (spans.isEmpty) return pw.Text(value, style: textStyle);
    if (last < value.length) {
      spans.add(pw.TextSpan(text: value.substring(last)));
    }
    return pw.RichText(
      text: pw.TextSpan(style: textStyle, children: spans),
    );
  }

  pw.Widget cell(String value, {bool header = false, pw.TextAlign? align}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: align == pw.TextAlign.right
            ? pw.Align(
                alignment: pw.Alignment.centerRight,
                child: text(value, header ? strong : base),
              )
            : text(value, header ? strong : base),
      );

  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
    Set<int> right = const {},
  }) => pw.Table(
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
    ),
    columnWidths: widths,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final (index, header) in headers.indexed)
            cell(
              header,
              header: true,
              align: right.contains(index) ? pw.TextAlign.right : null,
            ),
        ],
      ),
      for (final row in rows)
        pw.TableRow(
          children: [
            for (final (index, value) in row.indexed)
              cell(
                value,
                align: right.contains(index) ? pw.TextAlign.right : null,
              ),
          ],
        ),
    ],
  );

  pw.Widget heading(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: text(value, pw.TextStyle(font: bold, fontSize: 14)),
  );

  final unit = protocolUnit(protocol, tr);
  final document = pw.Document(
    title: protocol.title,
    subject: tr('Spielprotokoll'),
    creator: 'Quizmo',
    theme: theme,
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          tr('Seite {0} von {1}', [context.pageNumber, context.pagesCount]),
          style: pw.TextStyle(
            font: regular,
            fontSize: 8,
            color: PdfColors.grey600,
          ),
        ),
      ),
      build: (context) => [
        text(protocol.title, pw.TextStyle(font: bold, fontSize: 20)),
        pw.SizedBox(height: 4),
        text(
          '${tr('Spielprotokoll')} · ${tr(protocolFormatKey(protocol.format))}'
          ' · ${protocolDateTime(protocol.generatedAtMicros)}',
          pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.grey700),
        ),
        heading(tr('Platzierung')),
        table(
          [tr('Platz'), protocol.teamMode ? tr('Team') : tr('Spieler'), unit],
          [
            for (final standing in protocol.standings)
              [
                '${standing.place}.',
                standing.memberNames.isEmpty
                    ? standing.name
                    : '${standing.name} (${standing.memberNames.join(', ')})',
                '${standing.score}',
              ],
          ],
          widths: const {
            0: pw.FixedColumnWidth(44),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(70),
          },
          right: const {2},
        ),
        heading(tr('Fragen')),
        if (protocol.questions.isEmpty)
          text(tr('Es wurden keine Fragen gespielt.')),
        for (final question in protocol.questions) ...[
          pw.SizedBox(height: 8),
          text(
            '${question.number}. ${question.prompt}',
            pw.TextStyle(font: bold, fontSize: 11),
          ),
          if (protocolQuestionTags(question, tr) case final tags
              when tags.isNotEmpty)
            text(
              tags.join(' · '),
              pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          text(tr('Lösung: {0}', [tr(question.solution)]), strong),
          pw.SizedBox(height: 4),
          table(
            [tr('Spieler'), tr('Antwort'), tr('Ergebnis'), unit],
            [
              for (final answer in question.answers)
                [
                  answer.team == null
                      ? answer.player
                      : '${answer.player} (${answer.team})',
                  answer.answer == null ? '—' : tr(answer.answer!),
                  [
                    tr(protocolStatusKey(answer.status)),
                    if (answer.wager case final wager?)
                      tr('Einsatz: {0}', [wager]),
                    if (answer.practice) tr('Nur Übung'),
                  ].join(' · '),
                  answer.points == null ? '' : signed(answer.points!),
                ],
            ],
            widths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(2),
              3: pw.FixedColumnWidth(50),
            },
            right: const {3},
          ),
        ],
        heading(tr('Korrekturverlauf')),
        if (protocol.corrections.isEmpty)
          text(tr('Noch keine manuellen Korrekturen.'))
        else
          table(
            [
              tr('Zeit'),
              tr('Art'),
              tr('Ziel'),
              tr('Änderung'),
              tr('Begründung'),
            ],
            [
              for (final entry in protocol.corrections)
                [
                  protocolTime(entry.atMicros),
                  [
                    tr(protocolCorrectionKey(entry.kind)),
                    if (entry.isReversal) tr('Rücknahme'),
                    entry.question ?? tr('Ohne Bezug zu einer Frage'),
                  ].join('\n'),
                  entry.target,
                  '${protocolCorrectionChange(entry, tr, arrow: '->')}'
                      '${entry.delta == null ? '' : ' (${signed(entry.delta!)})'}',
                  entry.reason ?? '',
                ],
            ],
            widths: const {
              0: pw.FixedColumnWidth(48),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(3),
            },
          ),
      ],
    ),
  );
  return document.save();
}

/// Builds the PDF with the bundled fonts and offers it as a download.
///
/// Returns `false` when the user cancelled the save dialog.
Future<bool> downloadProtocolPdf(GameProtocol protocol, Translate tr) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/protocol/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/protocol/Roboto-Bold.ttf'),
  );
  final emojiFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/protocol/NotoEmoji-Regular.ttf'),
  );
  final bytes = await buildProtocolPdf(
    protocol,
    tr: tr,
    regular: regular,
    bold: bold,
    emoji: rasterizeEmoji,
    emojiFont: emojiFont,
  );
  final saved = await FilePicker.saveFile(
    dialogTitle: tr('Protokoll als PDF speichern'),
    fileName: protocolFileName(protocol),
    bytes: bytes,
    mimeType: 'application/pdf',
  );
  return saved != null;
}

/// File name of the protocol PDF, e.g. `Quizabend-protokoll.pdf`.
String protocolFileName(GameProtocol protocol) {
  final stem = protocol.title.trim().replaceAll(
    RegExp('[^a-zA-Z0-9äöüÄÖÜß_-]+'),
    '-',
  );
  return '${stem.isEmpty ? 'quiz' : stem}-protokoll.pdf';
}
