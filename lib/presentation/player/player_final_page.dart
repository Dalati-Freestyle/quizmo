/// The page players see once the quiz is over.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../common/browser_exit_guard.dart';
import '../common/protocol_view.dart';
import '../l10n/app_localizations.dart';
import 'protocol_pdf.dart' deferred as protocol_pdf;

/// Final standings with the own placement highlighted, plus the protocol to
/// view and download.
///
/// Everything is rendered from [GameState.protocol], which arrives with the
/// last snapshot, so the page keeps working after the host closed the room.
/// Nothing is stored in the browser: a reload after the session ended loses
/// the page, which is why it warns before leaving.
class PlayerFinalPage extends StatefulWidget {
  /// Creates the page.
  const PlayerFinalPage({
    required this.game,
    required this.playerId,
    super.key,
  });

  /// Last snapshot; [GameState.protocol] must be set.
  final GameState game;

  /// The viewing player.
  final String? playerId;

  @override
  State<PlayerFinalPage> createState() => _PlayerFinalPageState();
}

class _PlayerFinalPageState extends State<PlayerFinalPage> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    setProtocolExitGuard(true);
  }

  @override
  void dispose() {
    setProtocolExitGuard(false);
    super.dispose();
  }

  GameProtocol get _protocol => widget.game.protocol!;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    String tr(String key, [List<Object?> args = const []]) =>
        context.tr(key, args);
    try {
      await protocol_pdf.loadLibrary();
      final saved = await protocol_pdf.downloadProtocolPdf(_protocol, tr);
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr('Protokoll gespeichert.'))),
        );
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('PDF konnte nicht erstellt werden: {0}', [error])),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _view() {
    final own = _protocol.standingOf(widget.playerId)?.id;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(context.tr('Spielprotokoll'))),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ProtocolView(protocol: _protocol, highlightId: own),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final protocol = _protocol;
    final own = protocol.standingOf(widget.playerId);
    final unit = protocol.usesChips
        ? context.tr('Chips')
        : context.tr('Punkte');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('Quiz beendet'),
                style: theme.textTheme.headlineMedium,
              ),
              Text(protocol.title, style: theme.textTheme.titleMedium),
              if (own != null) ...[
                const SizedBox(height: 12),
                Card(
                  key: const ValueKey('own-placement'),
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.tr(
                        own.isTeam
                            ? 'Dein Team {0} belegt Platz {1} von {2} mit {3} {4}.'
                            : 'Du belegst Platz {1} von {2} mit {3} {4}.',
                        [
                          own.name,
                          own.place,
                          protocol.standings.length,
                          own.score,
                          unit,
                        ],
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                context.tr('Platzierung'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              FinalStandingsList(protocol: protocol, highlightId: own?.id),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('view-protocol'),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(context.tr('Protokoll ansehen')),
                    onPressed: _view,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('download-protocol'),
                    icon: _downloading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(context.tr('Als PDF herunterladen')),
                    onPressed: _downloading ? null : _download,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Das Protokoll wird nicht gespeichert. Sobald der Spielleiter die Sitzung geschlossen hat, ist es nach dem Neuladen oder Schließen dieser Seite weg. Lade es vorher herunter, wenn du es behalten möchtest.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
