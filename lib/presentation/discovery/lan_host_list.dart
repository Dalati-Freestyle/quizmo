import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/net/lan_discovery.dart';
import '../l10n/app_localizations.dart';
import 'lan_discovery_backend.dart';

String lanDiscoveryProblemMessage(LanDiscoveryProblem problem) =>
    switch (problem) {
      LanDiscoveryProblem.unsupported => 'Automatic LAN discovery is unavailable on this platform. Use a QR code, link or host address.',
      LanDiscoveryProblem.permission => 'Allow local network access in system settings, then refresh. You can also use a QR code, link or host address.',
      LanDiscoveryProblem.unavailable => 'LAN discovery failed. Check Wi-Fi, local network permissions and firewall settings, then refresh. Manual joining is still available.',
    };

class LanHostList extends StatefulWidget {
  const LanHostList({
    required this.onSelected,
    this.busy = false,
    this.discovery,
    super.key,
  });
  final ValueChanged<Uri> onSelected;
  final bool busy;
  final LanDiscoveryCubit? discovery;

  @override
  State<LanHostList> createState() => _LanHostListState();
}

class _LanHostListState extends State<LanHostList> with WidgetsBindingObserver {
  late final _discovery =
      widget.discovery ??
      LanDiscoveryCubit(backend: createLanDiscoveryBackend());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_discovery.browse());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_discovery.setSuspended(state != AppLifecycleState.resumed));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_discovery.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LanDiscoveryCubit, LanDiscoveryState>(
        bloc: _discovery,
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('LAN games'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Refresh LAN games'),
                  onPressed: widget.busy ? null : _discovery.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (state.searching) const LinearProgressIndicator(),
            if (state.problem case final problem?)
              Text(context.tr(lanDiscoveryProblemMessage(problem)))
            else ...[
              Text(
                context.tr(
                  'Select a host, then enter your name to join. If none appears, check that both devices use the same LAN; guest Wi-Fi or blocked multicast can prevent discovery. QR codes, links and manual addresses still work.',
                ),
              ),
              if (state.hosts.isEmpty && !state.searching)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.tr('No reachable LAN hosts found yet.')),
                ),
              for (final host in state.hosts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    host.reachableUri == null
                        ? Icons.wifi_off
                        : Icons.lan_outlined,
                  ),
                  title: Text(host.service.name),
                  subtitle: Text(
                    [
                      if (host.reachableUri case final uri?)
                        uri.toString()
                      else
                        ...host.service.addresses.map((uri) => uri.toString()),
                      context.tr(
                        host.reachableUri == null
                            ? 'Unreachable - check host or firewall'
                            : 'Reachable',
                      ),
                    ].join('\n'),
                  ),
                  enabled: !widget.busy && host.reachableUri != null,
                  onTap: host.reachableUri == null
                      ? null
                      : () => widget.onSelected(host.reachableUri!),
                ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      );
}
