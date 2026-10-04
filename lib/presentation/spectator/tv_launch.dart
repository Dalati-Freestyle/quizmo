/// Recognises a launch URL that addresses the spectator (TV) screen.
library;

import 'package:flutter/material.dart' show Brightness;

/// Path segment of the TV screen, as in `http://192.168.1.42:8080/tv`.
const String kTvPathSegment = 'tv';

/// Whether [uri] asks for the spectator screen instead of the role selection.
///
/// Three spellings are accepted so a link survives whatever the host, a QR code
/// generator or a TV browser does to it:
///
/// * the path: `http://host:8080/tv` (what the host dashboard shares),
/// * the hash route: `http://host:8080/#/tv`,
/// * the query: `http://host:8080/?view=tv`.
bool isTvLaunchUri(Uri uri) {
  if (_endsWithTv(uri.pathSegments)) return true;
  if (uri.queryParameters['view'] == kTvPathSegment) return true;

  final fragment = uri.fragment;
  if (fragment.isNotEmpty) {
    final route = Uri.tryParse(fragment);
    if (route != null && _endsWithTv(route.pathSegments)) return true;
  }
  return false;
}

/// Colour scheme requested by `?theme=light` / `?theme=dark`; dark by default,
/// because a bright panel in a dark living room is hard on the eyes.
Brightness tvBrightnessFor(Uri uri) => uri.queryParameters['theme'] == 'light'
    ? Brightness.light
    : Brightness.dark;

bool _endsWithTv(List<String> segments) {
  final meaningful = segments.where((segment) => segment.isNotEmpty);
  return meaningful.isNotEmpty && meaningful.last == kTvPathSegment;
}
