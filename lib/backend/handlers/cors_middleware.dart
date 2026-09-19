/// CORS middleware for the embedded host.
///
/// A player joining from a browser loads the Flutter Web bundle from a
/// different origin than the phone that hosts the quiz, so every response needs
/// permissive CORS headers and pre-flight requests must be answered directly.
library;

import 'package:shelf/shelf.dart';

const Map<String, String> _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'origin, content-type, accept',
  'access-control-max-age': '86400',
};

/// Returns a middleware that answers pre-flights and decorates every response.
Middleware corsMiddleware() => (Handler inner) {
  return (Request request) async {
    if (request.method == 'OPTIONS') {
      return Response.ok(null, headers: _corsHeaders);
    }
    final response = await inner(request);
    return response.change(headers: _corsHeaders);
  };
};

