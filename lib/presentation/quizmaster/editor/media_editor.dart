import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../../../core/models/models.dart';
import '../../common/question_media_view.dart';

enum _MediaKind { image, audio, video, youtube, code, geo }

class MediaEditor extends StatefulWidget {
  const MediaEditor({
    required this.media,
    required this.onChanged,
    required this.title,
    super.key,
  });
  final List<MediaAttachment> media;
  final ValueChanged<List<MediaAttachment>> onChanged;
  final String title;
  @override
  State<MediaEditor> createState() => _MediaEditorState();
}

class _MediaEditorState extends State<MediaEditor> {
  late List<MediaAttachment> media;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    media = [...widget.media];
  }

  void publish() => widget.onChanged([...media]);

  Future<void> add(_MediaKind kind) async {
    if (media.length >= 10) {
      _error(context.tr("Maximal zehn Anhänge."));
      return;
    }
    setState(() => loading = true);
    try {
      MediaAttachment? attachment;
      if (kind == _MediaKind.image ||
          kind == _MediaKind.audio ||
          kind == _MediaKind.video) {
        final extensions = switch (kind) {
          _MediaKind.image => ['png', 'jpg', 'jpeg', 'webp', 'svg'],
          _MediaKind.audio => ['mp3', 'wav', 'ogg'],
          _MediaKind.video => ['mp4'],
          _MediaKind.youtube || _MediaKind.code || _MediaKind.geo => <String>[],
        };
        final result = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: extensions,
        );
        if (result == null || !mounted) return;
        final file = result;
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        if (bytes.length > maxMediaBytes) {
          throw JsonContractException(
            context.tr("Datei zu groß oder nicht lesbar (maximal 20 MiB)."),
          );
        }
        final asset = MediaAsset.upload(bytes, file.extension ?? '');
        attachment = switch (kind) {
          _MediaKind.image => ImageAttachment(asset: asset, caption: file.name),
          _MediaKind.audio => AudioAttachment(asset: asset, caption: file.name),
          _MediaKind.video => VideoAttachment(asset: asset, caption: file.name),
          _MediaKind.youtube || _MediaKind.code || _MediaKind.geo => null,
        };
      } else {
        if (!mounted) return;
        attachment = await showDialog<MediaAttachment>(
          context: context,
          builder: (_) => _AttachmentDialog(kind: kind),
        );
      }
      if (attachment != null && mounted) {
        if (attachment.validationErrors.isNotEmpty) {
          throw JsonContractException(
            attachment.validationErrors.map(context.tr).join(' '),
          );
        }
        setState(() => media.add(attachment!));
        publish();
      }
    } on Object catch (error) {
      if (mounted) _error('$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _error(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          PopupMenuButton<_MediaKind>(
            enabled: !loading,
            onSelected: add,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _MediaKind.image,
                child: Text(context.tr("Bild hochladen")),
              ),
              PopupMenuItem(
                value: _MediaKind.audio,
                child: Text(context.tr("Audio hochladen")),
              ),
              PopupMenuItem(
                value: _MediaKind.video,
                child: Text(context.tr("MP4 hochladen")),
              ),
              PopupMenuItem(
                value: _MediaKind.youtube,
                child: Text(context.tr("YouTube-Link")),
              ),
              PopupMenuItem(
                value: _MediaKind.code,
                child: Text(context.tr("Code-Snippet")),
              ),
              PopupMenuItem(
                value: _MediaKind.geo,
                child: Text(context.tr("Kartenausschnitt")),
              ),
            ],
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(context.tr("Anhang hinzufügen")),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          for (final (i, attachment) in media.indexed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(attachment.caption)),
                        IconButton(
                          tooltip: context.tr("Anhang entfernen"),
                          onPressed: () {
                            setState(() => media.removeAt(i));
                            publish();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: Text(context.tr("Details ausblenden")),
                      subtitle: Text(
                        context.tr(
                          "Keine Beschriftung oder Dateinamen auf Spieler- und TV-Ansichten. YouTube kann eigene Titel einblenden; für Videos ohne Titel MP4 hochladen.",
                        ),
                      ),
                      value: attachment.hideDetails,
                      onChanged: (value) {
                        setState(
                          () => media[i] = attachment.withHiddenDetails(value),
                        );
                        publish();
                      },
                    ),
                    QuestionMediaView(media: [attachment]),
                    if (attachment is ImageAttachment)
                      SwitchListTile(
                        title: Text(context.tr("Zoom erlauben")),
                        value: attachment.zoom,
                        onChanged: (v) {
                          setState(
                            () => media[i] = ImageAttachment(
                              asset: attachment.asset,
                              caption: attachment.caption,
                              hideDetails: attachment.hideDetails,
                              zoom: v,
                            ),
                          );
                          publish();
                        },
                      ),
                    if (attachment is AudioAttachment) ...[
                      TextFormField(
                        key: ValueKey(attachment.asset.id),
                        initialValue:
                            attachment.playbackLimitSeconds?.toString() ?? '',
                        decoration: InputDecoration(
                          labelText: context.tr(
                            "Abspiellimit in Sekunden (optional)",
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v == null || v.isEmpty || (int.tryParse(v) ?? 0) > 0
                            ? null
                            : context.tr("Positive Sekunden angeben."),
                        onChanged: (v) {
                          media[i] = AudioAttachment(
                            asset: attachment.asset,
                            caption: attachment.caption,
                            hideDetails: attachment.hideDetails,
                            softPlaybackLimit: attachment.softPlaybackLimit,
                            playbackLimitSeconds: v.isEmpty
                                ? null
                                : int.tryParse(v) ?? 0,
                          );
                          publish();
                        },
                      ),
                      SwitchListTile(
                        title: Text(context.tr("Weiches Abspiellimit")),
                        subtitle: Text(
                          context.tr(
                            "Hart: Audio stoppt am Limit. Weich: Die Zeit ist ein Richtwert; der Spielleiter stoppt die Wiedergabe.",
                          ),
                        ),
                        value: attachment.softPlaybackLimit,
                        onChanged: (value) {
                          setState(
                            () => media[i] = MediaAttachment.fromJson({
                              ...media[i].toJson(),
                              'softPlaybackLimit': value,
                            }),
                          );
                          publish();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Text(
            context.tr(
              "Dateien: maximal 20 MiB. Karten und YouTube benötigen Internet.",
            ),
          ),
        ],
      ),
    ),
  );
}

class _AttachmentDialog extends StatefulWidget {
  const _AttachmentDialog({required this.kind});
  final _MediaKind kind;
  @override
  State<_AttachmentDialog> createState() => _AttachmentDialogState();
}

class _AttachmentDialogState extends State<_AttachmentDialog> {
  final first = TextEditingController();
  final second = TextEditingController(text: 'dart');
  final third = TextEditingController(text: '8');
  final caption = TextEditingController();
  String? error;
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    third.dispose();
    caption.dispose();
    super.dispose();
  }

  void save() {
    try {
      final attachment = switch (widget.kind) {
        _MediaKind.youtube => VideoAttachment(
          youtubeId: youtubeId(first.text.trim()),
          caption: caption.text.trim(),
        ),
        _MediaKind.code => CodeAttachment(
          code: first.text,
          language: second.text.trim(),
          caption: caption.text.trim(),
        ),
        _MediaKind.geo => GeoAttachment(
          latitude: double.parse(first.text.replaceAll(',', '.')),
          longitude: double.parse(second.text.replaceAll(',', '.')),
          zoom: double.parse(third.text),
          caption: caption.text.trim(),
        ),
        _MediaKind.image ||
        _MediaKind.audio ||
        _MediaKind.video => throw StateError('Upload expected'),
      };
      if (attachment.validationErrors.isNotEmpty) {
        throw FormatException(
          attachment.validationErrors.map(context.tr).join(' '),
        );
      }
      Navigator.pop(context, attachment);
    } on Object catch (e) {
      setState(
        () => error = context.tr("Eingaben prüfen: {0}", [context.tr('$e')]),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr("Medienanhang")),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: caption,
              decoration: InputDecoration(
                labelText: context.tr("Beschriftung (optional)"),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: first,
              minLines: widget.kind == _MediaKind.code ? 5 : 1,
              maxLines: widget.kind == _MediaKind.code ? 12 : 1,
              decoration: InputDecoration(
                labelText: switch (widget.kind) {
                  _MediaKind.youtube => context.tr("YouTube-Link"),
                  _MediaKind.code => context.tr("Quellcode"),
                  _ => context.tr("Breitengrad"),
                },
              ),
            ),
            const SizedBox(height: 20),
            if (widget.kind != _MediaKind.youtube)
              TextField(
                controller: second,
                decoration: InputDecoration(
                  labelText: widget.kind == _MediaKind.code
                      ? context.tr("Sprache (z. B. dart, python, javascript)")
                      : context.tr("Längengrad"),
                ),
              ),
            const SizedBox(height: 20),
            if (widget.kind == _MediaKind.geo)
              TextField(
                controller: third,
                decoration: InputDecoration(
                  labelText: context.tr("Zoom (1–18)"),
                ),
              ),
            if (error != null) Text(context.tr(error!)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr("Abbrechen")),
      ),
      FilledButton(onPressed: save, child: Text(context.tr('Hinzufügen'))),
    ],
  );
}

String? youtubeId(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host == 'youtu.be') return uri.pathSegments.firstOrNull;
  if (!{'youtube.com', 'www.youtube.com', 'm.youtube.com'}.contains(uri.host)) {
    return null;
  }
  if (uri.path == '/watch') return uri.queryParameters['v'];
  if (uri.pathSegments.length == 2 &&
      {'embed', 'shorts'}.contains(uri.pathSegments.first)) {
    return uri.pathSegments.last;
  }
  return null;
}
