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
    queryParameters: launch.queryParameters['session'] == null
        ? null
        : {'session': launch.queryParameters['session']!},
  );
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
