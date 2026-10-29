import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/data/session_checkpoint.dart';
import '../../../core/data/session_recovery.dart';
import '../../l10n/app_localizations.dart';
import '../host_dashboard_page.dart' deferred as host;
import 'recovery_store.dart';

class RecoveryGate extends StatefulWidget {
  const RecoveryGate({required this.child, this.store, super.key});
  final Widget child;
  final SessionRecoveryStore? store;
  static Future<void> reload(BuildContext context) async {
    await context.findAncestorStateOfType<_RecoveryGateState>()?._load();
  }

  @override
  State<RecoveryGate> createState() => _RecoveryGateState();
}

class _RecoveryGateState extends State<RecoveryGate> {
  SessionRecoveryStore? _store;
  SessionCheckpoint? _checkpoint;
  RecoveryRecord? _contents;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _checkpoint = null;
    _contents = null;
    try {
      _store ??= widget.store ?? await createRecoveryStore();
      _contents = await _store!.read();
      _checkpoint = _contents?.decode();
      _error = null;
    } on Object catch (error) {
      _error = '$error';
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _resume() async {
    setState(() {
      _busy = true;
    });
    try {
      await host.loadLibrary();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => host.HostDashboardPage(
            quiz: _checkpoint!.quiz,
            checkpoint: _checkpoint,
            recoveryStore: _store,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              'Recovery view could not be opened. Reload Quizmo and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
    });
    try {
      await FilePicker.saveFile(
        dialogTitle: context.tr('Export private session report'),
        fileName: 'session.quizmo-report.json',
        bytes: utf8.encode(_checkpoint!.exportReport()),
        mimeType: 'application/json',
      );
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Report export failed. Check storage permissions and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _discard() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete saved game?')),
        content: Text(
          context.tr(
            'This permanently deletes the saved game and participant resume credentials.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Discard')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await _store!.acquire();
      try {
        if (!_contents!.matches(await _store!.read())) {
          throw const RecoveryException(
            'The saved game changed. Reload recovery before deleting.',
          );
        }
        await _store!.delete();
      } finally {
        await _store!.release();
      }
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_contents == null && _error == null) return widget.child;
    final checkpoint = _checkpoint;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Saved game recovery'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (checkpoint != null) ...[
                  Text(
                    checkpoint.quiz.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    DateTime.fromMicrosecondsSinceEpoch(
                      checkpoint.savedAtMicros,
                    ).toLocal().toString(),
                  ),
                  Text(
                    context.tr(
                      'Recovery starts paused. Choose saved time, a fresh timer or a soft timer on the host dashboard. Accepted answers and points are retained.',
                    ),
                  ),
                  Text(
                    context.tr(
                      'Internet recovery creates a new room. Old internet links are invalid; share the new invitation and TV links. LAN addresses may also change.',
                    ),
                  ),
                  Text(
                    context.tr(
                      'Resume uses this device and browser profile. The private report contains answers, solutions and media, but no resume credentials and cannot restore player access. Do not share it publicly.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _resume,
                    child: Text(context.tr('Continue saved game')),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _export,
                    child: Text(context.tr('Export private session report')),
                  ),
                ],
                if (_error != null)
                  Text(
                    context.tr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: Text(context.tr('Retry')),
                ),
                if (_contents != null)
                  TextButton(
                    onPressed: _busy ? null : _discard,
                    child: Text(context.tr('Discard')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
