/// Room URLs retain their path when connecting through an internet relay.
Uri sessionUri(Uri launch) {
  final segments = launch.pathSegments;
  final room = segments.length >= 2 && segments[0] == 'rooms'
      ? '/rooms/${segments[1]}'
      : '';
  return Uri(
    scheme: launch.scheme,
    host: launch.host,
    port: launch.hasPort ? launch.port : null,
    path: room,
    queryParameters: _kept(launch.queryParameters),
  );
}

/// Query parameter carrying the access key of a password protected server.
///
/// The reverse proxy (see `deploy/README.md`) trades it for a session cookie,
/// so guests who scan an invitation never have to type the Basic Auth
/// password. It is kept on every session link so a TV can print it into its
/// own QR code and a player can reconnect after the cookie expired.
const String kAccessKeyParameter = 'quizmo_key';

Map<String, String>? _kept(Map<String, String> query) {
  final kept = {
    for (final name in const ['session', kAccessKeyParameter])
      name: ?query[name],
  };
  return kept.isEmpty ? null : kept;
}

bool isInternetSession(Uri uri) =>
    uri.pathSegments.length >= 2 && uri.pathSegments.first == 'rooms';

Uri sessionSocketUri(Uri uri) => sessionUri(uri).replace(
  scheme: uri.scheme == 'https' ? 'wss' : 'ws',
  path: '${sessionUri(uri).path}/ws',
);

bool samePlayerSession(Uri saved, Uri target) {
  final identity = saved.queryParameters['session'];
  final targetIdentity = target.queryParameters['session'];
  if (identity != null || targetIdentity != null) {
    return identity != null &&
        identity == targetIdentity &&
        (!(isInternetSession(saved) || isInternetSession(target)) ||
            saved.origin == target.origin);
  }
  return sessionUri(saved) == sessionUri(target);
}
