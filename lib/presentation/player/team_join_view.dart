import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../../core/protocol/messages.dart';

class TeamJoinView extends StatefulWidget {
  const TeamJoinView({
    required this.lobby,
    required this.onJoin,
    required this.onCreate,
    required this.onBack,
    this.busy = false,
    this.error,
    super.key,
  });

  final LobbySnapshotMessage lobby;
  final void Function(String? teamId, String code) onJoin;
  final void Function(String name, String code) onCreate;
  final VoidCallback onBack;
  final bool busy;
  final String? error;

  @override
  State<TeamJoinView> createState() => _TeamJoinViewState();
}

class _TeamJoinViewState extends State<TeamJoinView> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _teamId;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lobby = widget.lobby;
    final selected = lobby.teams.containsKey(_teamId) ? _teamId : null;
    final name = _name.text.trim();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr("Team auswählen"),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  "Tritt einem bestehenden Team bei oder erstelle dein eigenes.",
                ),
              ),
              const SizedBox(height: 24),
              if (lobby.locked)
                Text(
                  context.tr(
                    'The lobby is locked. Existing players can still reconnect.',
                  ),
                ),
              if (lobby.requireApproval)
                Text(context.tr('New participants need host approval.')),
              if (lobby.codeRequired)
                TextField(
                  controller: _code,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  maxLength: 64,
                  decoration: InputDecoration(
                    labelText: context.tr('Join code'),
                  ),
                ),
              if (lobby.teams.isEmpty)
                Text(context.tr("Es gibt noch keine Teams.")),
              DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr("Team")),
                hint: Text(
                  lobby.requiresTeam
                      ? context.tr("Team wählen")
                      : context.tr("Solo"),
                ),
                items: [
                  if (!lobby.requiresTeam)
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.tr("Solo")),
                    ),
                  for (final team in lobby.teams.values)
                    DropdownMenuItem(
                      value: team.id,
                      child: Text(team.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: widget.busy
                    ? null
                    : (id) => setState(() => _teamId = id == '' ? null : id),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    widget.busy ||
                        lobby.locked ||
                        (lobby.requiresTeam && selected == null)
                    ? null
                    : () => widget.onJoin(selected, _code.text),
                child: Text(context.tr("Spiel beitreten")),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                enabled: !widget.busy,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: context.tr("Neuer Teamname"),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (!widget.busy && !lobby.locked && name.isNotEmpty) {
                    widget.onCreate(name, _code.text);
                  }
                },
              ),
              OutlinedButton.icon(
                onPressed: widget.busy || lobby.locked || name.isEmpty
                    ? null
                    : () => widget.onCreate(name, _code.text),
                icon: const Icon(Icons.group_add_outlined),
                label: Text(context.tr("Team erstellen und beitreten")),
              ),
              if (widget.busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                Text(
                  context.tr("Uhr synchronisieren und beitreten …"),
                  textAlign: TextAlign.center,
                ),
              ],
              if (widget.error case final error?) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr(error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              TextButton(
                onPressed: widget.busy ? null : widget.onBack,
                child: const Text('Zurück'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> showTeamNameDialog(BuildContext context, String name) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TeamNameDialog(name: name),
    );

class _TeamNameDialog extends StatefulWidget {
  const _TeamNameDialog({required this.name});
  final String name;
  @override
  State<_TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<_TeamNameDialog> {
  late final controller = TextEditingController(text: widget.name);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr("Team umbenennen")),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: context.tr("Teamname")),
        validator: (value) => value == null || value.trim().isEmpty
            ? context.tr("Teamnamen eingeben")
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr("Abbrechen")),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: Text(context.tr("Speichern")),
      ),
    ],
  );
}
