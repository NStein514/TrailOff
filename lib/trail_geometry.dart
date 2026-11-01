import 'dart:math' as math;

import 'hike_navigation.dart';

/// One vertex of a catalogue route. Sample geometry, drawn and used to size
/// offline downloads; it is not a surveyed track.
class TrailPoint {
  const TrailPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class TrailBounds {
  const TrailBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  double get latitudeSpan => north - south;
  double get longitudeSpan => east - west;
  double get centerLatitude => (north + south) / 2;
  double get centerLongitude => (east + west) / 2;

  bool contains(TrailPoint point) =>
      point.latitude >= south &&
      point.latitude <= north &&
      point.longitude >= west &&
      point.longitude <= east;

  /// Grows the box by [metres] on every side, converting the north–south
  /// distance with the box's own latitude so the margin is honest.
  TrailBounds expandedByMeters(double metres) {
    const metresPerDegreeLatitude = 111320.0;
    final latitudePad = metres / metresPerDegreeLatitude;
    final metresPerDegreeLongitude =
        metresPerDegreeLatitude * math.cos(centerLatitude * math.pi / 180);
    final longitudePad = metres / math.max(1, metresPerDegreeLongitude);
    return TrailBounds(
      south: (south - latitudePad).clamp(-90.0, 90.0),
      west: west - longitudePad,
      north: (north + latitudePad).clamp(-90.0, 90.0),
      east: east + longitudePad,
    );
  }
}

/// Bounding box of a route, or a single point's box when it is empty.
TrailBounds trailBounds(List<TrailPoint> route) {
  if (route.isEmpty) {
    return const TrailBounds(south: 0, west: 0, north: 0, east: 0);
  }
  var south = route.first.latitude;
  var north = route.first.latitude;
  var west = route.first.longitude;
  var east = route.first.longitude;
  for (final point in route) {
    if (point.latitude < south) south = point.latitude;
    if (point.latitude > north) north = point.latitude;
    if (point.longitude < west) west = point.longitude;
    if (point.longitude > east) east = point.longitude;
  }
  return TrailBounds(south: south, west: west, north: north, east: east);
}

/// Length of the drawn line, in metres. Catalogue distance figures stay
/// authoritative; this is here so the geometry can be checked for sanity.
double trailLengthMeters(List<TrailPoint> route) {
  var total = 0.0;
  for (var i = 1; i < route.length; i++) {
    total += distanceMetersBetween(
      route[i - 1].latitude,
      route[i - 1].longitude,
      route[i].latitude,
      route[i].longitude,
    );
  }
  return total;
}

/// Longest straight segment, used to catch geometry that jumps across the map.
double longestSegmentMeters(List<TrailPoint> route) {
  var longest = 0.0;
  for (var i = 1; i < route.length; i++) {
    final segment = distanceMetersBetween(
      route[i - 1].latitude,
      route[i - 1].longitude,
      route[i].latitude,
      route[i].longitude,
    );
    if (segment > longest) longest = segment;
  }
  return longest;
}
