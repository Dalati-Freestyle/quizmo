import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/session_access.dart';
import '../common/adaptive_layout.dart';
import '../l10n/app_localizations.dart';

class SessionAccessPanel extends StatefulWidget {
  const SessionAccessPanel({required this.access, super.key});
  final SessionAccess access;

  @override
  State<SessionAccessPanel> createState() => _SessionAccessPanelState();
}

class _SessionAccessPanelState extends State<SessionAccessPanel> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SessionAccess, SessionAccessState>(
    bloc: widget.access,
    builder: (context, state) => PanelCard(
      title: context.tr('Session access'),
      icon: Icons.admin_panel_settings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Lock new joins')),
            subtitle: Text(
              context.tr(
                'Admitted players can still reconnect with their resume token.',
              ),
            ),
            value: state.locked,
            onChanged: (value) => widget.access.configure(locked: value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Approve new participants')),
            value: state.requireApproval,
            onChanged: (value) =>
                widget.access.configure(requireApproval: value),
          ),
          Text(
            context.tr(
              state.codeHash == null
                  ? 'No join code required.'
                  : 'Join code enabled.',
            ),
          ),
          TextField(
            controller: _code,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 64,
            decoration: InputDecoration(
              labelText: context.tr('New join code (6 to 64 characters)'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _code.text.length < 6
                    ? null
                    : () {
                        widget.access.configure(code: _code.text);
                        _code.clear();
                        setState(() {});
                      },
                child: Text(context.tr('Set join code')),
              ),
              if (state.codeHash != null)
                TextButton(
                  onPressed: () => widget.access.configure(code: ''),
                  child: Text(context.tr('Remove join code')),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Allow spectators')),
            value: state.allowSpectators,
            onChanged: (value) =>
                widget.access.configure(allowSpectators: value),
          ),
          Text(
            context.tr(
              'Spectators need the join code, but no approval. The lobby lock only affects players. Disabling spectators or changing the code disconnects existing TVs.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Remove invalidates the resume token; a new admission is possible. Ban excludes the known identity for this session. Without accounts, another browser or device cannot be reliably recognized.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Keep invitation links, join codes and resume tokens confidential.',
            ),
          ),
          if (state.bannedPlayerIds.isNotEmpty)
            Text(
              context.tr('Banned identities: {0}', [
                state.bannedPlayerIds.length,
              ]),
            ),
          const SizedBox(height: 12),
          Text(context.tr('Waiting for approval')),
          if (!state.requests.values.any(
            (r) => r.decision == AdmissionDecision.waiting,
          ))
            Text(context.tr('No pending requests.')),
          for (final entry in state.requests.entries)
            if (entry.value.decision == AdmissionDecision.waiting)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: context.tr('Reject'),
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          widget.access.decide(entry.key, approve: false),
                    ),
                    IconButton(
                      tooltip: context.tr('Approve'),
                      icon: const Icon(Icons.check),
                      onPressed: state.locked
                          ? null
                          : () =>
                                widget.access.decide(entry.key, approve: true),
                    ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}
