/// Markdown in the free text fields of a quiz (quiz schema 15): prompts, host
/// notes, hint texts and slide texts. Pure Dart, so that reports and protocols
/// get plain text without Flutter.
library;

import 'package:markdown/markdown.dart' as md;

/// How a piece of [MarkdownRun] looks.
final class MarkdownStyle {
  const MarkdownStyle({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.heading = 0,
    this.link,
    this.quote = false,
  });

  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;

  /// 1 to 3 for headings (4 to 6 count as 3), 0 otherwise.
  final int heading;

  /// Target of a link, as written.
  final String? link;
  final bool quote;

  MarkdownStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strike,
    bool? code,
    int? heading,
    String? link,
    bool? quote,
  }) => MarkdownStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    heading: heading ?? this.heading,
    link: link ?? this.link,
    quote: quote ?? this.quote,
  );
}

/// A piece of text with one look.
typedef MarkdownRun = ({String text, MarkdownStyle style});

md.Document _document() => md.Document(
  extensionSet: md.ExtensionSet(
    const [md.FencedCodeBlockSyntax()],
    [md.StrikethroughSyntax()],
  ),
  encodeHtml: false,
);

/// [source] as runs of text: blocks are separated by blank lines, list items
/// start with a bullet or their number, every line break stays.
///
/// Never throws: text that is no valid Markdown is shown as it is.
List<MarkdownRun> markdownRuns(String source) {
  if (source.isEmpty) return const [];
  final List<md.Node> nodes;
  try {
    nodes = _document().parse(source.replaceAll('\r\n', '\n'));
  } on Object {
    return [(text: source, style: const MarkdownStyle())];
  }
  final runs = <MarkdownRun>[];
  void add(String text, MarkdownStyle style) {
    if (text.isNotEmpty) runs.add((text: text, style: style));
  }

  void inline(md.Node node, MarkdownStyle style) {
    switch (node) {
      case md.Text(:final text):
        add(text, style);
      case md.UnparsedContent(:final textContent):
        add(textContent, style);
      case md.Element(:final tag, :final children):
        switch (tag) {
          case 'strong':
            for (final child in children ?? const <md.Node>[]) {
              inline(child, style.copyWith(bold: true));
            }
          case 'em':
            for (final child in children ?? const <md.Node>[]) {
              inline(child, style.copyWith(italic: true));
            }
          case 'del':
            for (final child in children ?? const <md.Node>[]) {
              inline(child, style.copyWith(strike: true));
            }
          case 'code':
            add(node.textContent, style.copyWith(code: true));
          case 'br':
            add('\n', style);
          case 'a':
            for (final child in children ?? const <md.Node>[]) {
              inline(child, style.copyWith(link: node.attributes['href']));
            }
          case 'img':
            // Pictures belong to the media of the question.
            add(
              '![${node.attributes['alt'] ?? ''}](${node.attributes['src'] ?? ''})',
              style,
            );
          default:
            for (final child in children ?? const <md.Node>[]) {
              inline(child, style);
            }
        }
    }
  }

  void block(md.Node node, MarkdownStyle style, String indent) {
    if (node is! md.Element) {
      inline(node, style);
      return;
    }
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        for (final child in children) {
          inline(child, style.copyWith(heading: level > 3 ? 3 : level));
        }
      case 'ul' || 'ol':
        final ordered = node.tag == 'ol';
        var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final (index, item) in children.indexed) {
          if (index > 0) add('\n', style);
          add('$indent${ordered ? '${number++}.' : '•'} ', style);
          final parts = item is md.Element
              ? item.children ?? const <md.Node>[]
              : [item];
          for (final (partIndex, part) in parts.indexed) {
            final nested =
                part is md.Element && (part.tag == 'ul' || part.tag == 'ol');
            if (partIndex > 0) add('\n', style);
            block(part, style, nested ? '$indent   ' : indent);
          }
        }
      case 'blockquote':
        for (final (index, child) in children.indexed) {
          if (index > 0) add('\n\n', style);
          block(child, style.copyWith(quote: true), indent);
        }
      case 'pre':
        var text = node.textContent;
        if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
        add(text, style.copyWith(code: true));
      case 'hr':
        add('———', style);
      case 'p':
        for (final child in children) {
          inline(child, style);
        }
      default:
        for (final child in children) {
          block(child, style, indent);
        }
    }
  }

  for (final (index, node) in nodes.indexed) {
    if (index > 0) add('\n\n', const MarkdownStyle());
    block(node, const MarkdownStyle(), '');
  }
  return runs;
}

/// [source] without Markdown characters, for reports, lists and screen
/// readers.
String markdownToPlain(String source) =>
    markdownRuns(source).map((run) => run.text).join();

/// Whether [source] shows nothing at all.
bool isBlankMarkdown(String source) => markdownToPlain(source).trim().isEmpty;

String _normalized(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'[ \t]+(?=\n|$)'), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceAll(RegExp(r'^\n+|\n+$'), '');

/// Whether [source] shows [wanted] as plain, unformatted text.
bool _looksLike(String source, String wanted) {
  final runs = markdownRuns(source);
  return runs.every(
        (run) =>
            !run.style.bold &&
            !run.style.italic &&
            !run.style.strike &&
            !run.style.code &&
            !run.style.quote &&
            run.style.heading == 0 &&
            run.style.link == null,
      ) &&
      _normalized(runs.map((run) => run.text).join()) == wanted;
}

final _special = RegExp(r'[\\`*_~\[\]<>#!&]');

/// Plain [text] from an older quiz, written so that it looks exactly as
/// before as Markdown: characters that would format something are escaped,
/// and only those.
String escapeMarkdown(String text) {
  if (text.isEmpty) return text;
  final wanted = _normalized(text);
  if (_looksLike(text, wanted)) return text;
  // Escape everything that may be Markdown …
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final parts = <String>[];
  for (final line in lines) {
    var current = line.replaceAllMapped(_special, (m) => '\\${m[0]}');
    // Indented code and list or heading markers at the start of a line.
    current = current.replaceFirstMapped(
      RegExp(r'^( {4,}|\t+)'),
      (m) => ' ' * m[0]!.length,
    );
    current = current.replaceFirstMapped(
      RegExp(r'^(\s*)([-+=])'),
      (m) => '${m[1]}\\${m[2]}',
    );
    current = current.replaceFirstMapped(
      RegExp(r'^(\s*\d+)([.)])'),
      (m) => '${m[1]}\\${m[2]}',
    );
    parts.add(current);
  }
  var escaped = parts.join('\n');
  // … and keep only the escapes that are needed.
  var index = 0;
  while (index < escaped.length) {
    index = escaped.indexOf('\\', index);
    if (index < 0) break;
    final candidate =
        escaped.substring(0, index) + escaped.substring(index + 1);
    if (_looksLike(candidate, wanted)) {
      escaped = candidate;
    } else {
      index += 2;
    }
  }
  return escaped;
}

/// Whether [target] may be opened by a click: only web addresses.
bool isOpenableLink(String? target) {
  final uri = Uri.tryParse(target ?? '');
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
