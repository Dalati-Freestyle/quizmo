/// Finds places by name for the map question editor; only the editor asks,
/// and only the search words are sent.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A place found by [PlaceSearch].
final class PlaceHit {
  const PlaceHit({
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  /// Short name, e.g. "Eiffelturm".
  final String name;

  /// Region and country, to tell equal names apart.
  final String description;
  final double latitude;
  final double longitude;
}

/// Why a search found nothing.
final class PlaceSearchException implements Exception {
  const PlaceSearchException(this.message);

  /// A translation key.
  final String message;

  @override
  String toString() => message;
}

/// Replaceable search service.
abstract interface class PlaceSearch {
  Future<List<PlaceHit>> search(String query, {String? language});
}

/// The public Nominatim service of OpenStreetMap: one request per second at
/// most and no autocomplete, so it is only asked on an explicit search.
final class NominatimPlaceSearch implements PlaceSearch {
  NominatimPlaceSearch({
    http.Client? client,
    Uri? endpoint,
    DateTime Function() now = DateTime.now,
  }) : _client = client,
       _endpoint =
           endpoint ?? Uri.parse('https://nominatim.openstreetmap.org/search'),
       _now = now;

  final http.Client? _client;
  final Uri _endpoint;
  final DateTime Function() _now;
  DateTime? _last;

  /// Shown below the results, as the service asks for.
  static const attribution = '© OpenStreetMap contributors (Nominatim)';

  @override
  Future<List<PlaceHit>> search(String query, {String? language}) async {
    final words = query.trim();
    if (words.isEmpty) return const [];
    final last = _last;
    if (last != null) {
      final wait = const Duration(seconds: 1) - _now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _last = _now();
    final uri = _endpoint.replace(
      queryParameters: {
        'q': words,
        'format': 'jsonv2',
        'limit': '8',
        'accept-language': ?language,
      },
    );
    final http.Response response;
    try {
      final get = _client?.get ?? http.get;
      response = await get(
        uri,
        // Browsers send their own agent; native apps identify the app.
        headers: const {'User-Agent': 'Quizmo quiz editor'},
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const PlaceSearchException(
        'Die Ortssuche antwortet nicht. Prüfe die Internetverbindung.',
      );
    } on Object {
      throw const PlaceSearchException(
        'Keine Verbindung zur Ortssuche. Prüfe die Internetverbindung.',
      );
    }
    if (response.statusCode != 200) {
      throw const PlaceSearchException(
        'Die Ortssuche ist gerade nicht verfügbar. Versuche es später erneut.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PlaceSearchException(
        'Die Ortssuche ist gerade nicht verfügbar. Versuche es später erneut.',
      );
    }
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map<String, Object?>)
          if ((
                double.tryParse('${entry['lat']}'),
                double.tryParse('${entry['lon']}'),
              )
              case (final double latitude, final double longitude))
            PlaceHit(
              name: '${entry['name'] ?? ''}'.trim().isEmpty
                  ? '${entry['display_name'] ?? ''}'.split(',').first.trim()
                  : '${entry['name']}'.trim(),
              description: '${entry['display_name'] ?? ''}',
              latitude: latitude,
              longitude: longitude,
            ),
    ];
  }
}
