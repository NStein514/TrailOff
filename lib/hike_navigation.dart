import 'dart:math' as math;

const _earthRadiusMeters = 6371000.0;

double _radians(double degrees) => degrees * math.pi / 180;

/// Great-circle distance between two points, in metres.
double distanceMetersBetween(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final dLat = _radians(toLatitude - fromLatitude);
  final dLng = _radians(toLongitude - fromLongitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(fromLatitude)) *
          math.cos(_radians(toLatitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
}

/// Initial bearing from one point to another, clockwise from true north.
double initialBearingDegrees(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final fromLat = _radians(fromLatitude);
  final toLat = _radians(toLatitude);
  final dLng = _radians(toLongitude - fromLongitude);
  final y = math.sin(dLng) * math.cos(toLat);
  final x =
      math.cos(fromLat) * math.sin(toLat) -
      math.sin(fromLat) * math.cos(toLat) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

const _compassPoints = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// Eight-point compass label, e.g. `NE` for a 45 degree bearing.
String compassPoint(double bearingDegrees) {
  final normalized = (bearingDegrees % 360 + 360) % 360;
  return _compassPoints[(normalized / 45).round() % 8];
}

class TrailheadBearing {
  const TrailheadBearing({
    required this.distanceMeters,
    required this.bearingDegrees,
  });

  final double distanceMeters;
  final double bearingDegrees;

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  String get directionLabel => compassPoint(bearingDegrees);

  String get summary => '$distanceLabel · $directionLabel';
}

/// Distance and direction from the current position back to the trailhead.
TrailheadBearing bearingToTrailhead({
  required double fromLatitude,
  required double fromLongitude,
  required double trailheadLatitude,
  required double trailheadLongitude,
}) => TrailheadBearing(
  distanceMeters: distanceMetersBetween(
    fromLatitude,
    fromLongitude,
    trailheadLatitude,
    trailheadLongitude,
  ),
  bearingDegrees: initialBearingDegrees(
    fromLatitude,
    fromLongitude,
    trailheadLatitude,
    trailheadLongitude,
  ),
);
