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
  );
}

bool isInternetSession(Uri uri) =>
    uri.pathSegments.length >= 2 && uri.pathSegments.first == 'rooms';

Uri sessionSocketUri(Uri uri) => sessionUri(uri).replace(
  scheme: uri.scheme == 'https' ? 'wss' : 'ws',
  path: '${sessionUri(uri).path}/ws',
);
