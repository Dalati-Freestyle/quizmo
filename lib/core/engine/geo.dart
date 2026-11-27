/// Distances on the earth, pure Dart.
library;

import 'dart:math' as math;

/// Mean earth radius in kilometres (IUGG).
const earthRadiusKm = 6371.0088;

/// Half the circumference: no place is farther away than this.
const maxDistanceKm = math.pi * earthRadiusKm;

/// Great-circle distance between two points in kilometres (haversine), also
/// across the date line and near the poles.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
}

/// Share of the points for a guess [distance] km away: everything up to
/// [fullKm] earns all, from [zeroKm] on nothing, linear in between.
double locationAccuracy(double distance, double fullKm, double zeroKm) {
  if (distance <= fullKm) return 1;
  if (distance >= zeroKm) return 0;
  // Strictly below 1 outside the full radius.
  return math.min(1 - (distance - fullKm) / (zeroKm - fullKm), 0.999999);
}

/// [km] for people: metres below one kilometre.
String formatDistance(double km) => km < 1
    ? '${(km * 1000).round()} m'
    : km < 10
    ? '${km.toStringAsFixed(1)} km'
    : '${km.round()} km';
