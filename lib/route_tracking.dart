import 'dart:math' as math;

import 'hike_navigation.dart';
import 'trail_geometry.dart';

/// Beyond this distance from the planned line the hiker is off route.
const offRouteWarningMeters = 200.0;

/// Once off route, the warning only clears inside this smaller distance, so
/// GPS noise around the threshold cannot flicker it on and off.
const offRouteClearMeters = 120.0;

class RouteMatch {
  const RouteMatch({
    required this.distanceMeters,
    required this.metersAlongRoute,
    required this.totalMeters,
  });

  /// Straight-line distance to the nearest point of the route.
  final double distanceMeters;

  /// Distance from the route's start to that nearest point.
  final double metersAlongRoute;

  final double totalMeters;

  double get fractionAlongRoute {
    if (totalMeters == 0) return 0;
    return (metersAlongRoute / totalMeters).clamp(0.0, 1.0).toDouble();
  }
}

/// Projects a position onto a route in a local metre plane and reports how far
/// away it is and how far along the route it sits. Returns `null` for a route
/// with no vertices.
RouteMatch? matchRoute({
  required List<TrailPoint> route,
  required double latitude,
  required double longitude,
}) {
  if (route.isEmpty) return null;

  const metresPerDegreeLatitude = 111320.0;
  final metresPerDegreeLongitude =
      metresPerDegreeLatitude * math.cos(latitude * math.pi / 180);
  double eastOf(double pointLongitude) =>
      (pointLongitude - longitude) * metresPerDegreeLongitude;
  double northOf(double pointLatitude) =>
      (pointLatitude - latitude) * metresPerDegreeLatitude;

  if (route.length == 1) {
    final east = eastOf(route.first.longitude);
    final north = northOf(route.first.latitude);
    return RouteMatch(
      distanceMeters: math.sqrt(east * east + north * north),
      metersAlongRoute: 0,
      totalMeters: 0,
    );
  }

  var walked = 0.0;
  var bestDistance = double.infinity;
  var bestAlong = 0.0;
  for (var i = 1; i < route.length; i++) {
    final start = route[i - 1];
    final end = route[i];
    final segmentLength = distanceMetersBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    final startEast = eastOf(start.longitude);
    final startNorth = northOf(start.latitude);
    final deltaEast = eastOf(end.longitude) - startEast;
    final deltaNorth = northOf(end.latitude) - startNorth;
    final lengthSquared = deltaEast * deltaEast + deltaNorth * deltaNorth;
    var t = 0.0;
    if (lengthSquared > 0) {
      final projection =
          -(startEast * deltaEast + startNorth * deltaNorth) / lengthSquared;
      t = projection.clamp(0.0, 1.0);
    }
    final closestEast = startEast + deltaEast * t;
    final closestNorth = startNorth + deltaNorth * t;
    final distance = math.sqrt(
      closestEast * closestEast + closestNorth * closestNorth,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestAlong = walked + segmentLength * t;
    }
    walked += segmentLength;
  }

  return RouteMatch(
    distanceMeters: bestDistance,
    metersAlongRoute: bestAlong.clamp(0.0, walked).toDouble(),
    totalMeters: walked,
  );
}

/// Warning state after a new fix: `null` means on route. Starts warning past
/// [offRouteWarningMeters] and only stops past [offRouteClearMeters] on the way
/// back.
double? offRouteDistanceAfter({
  required double distanceMeters,
  required double? previous,
}) {
  if (previous == null) {
    return distanceMeters > offRouteWarningMeters ? distanceMeters : null;
  }
  return distanceMeters > offRouteClearMeters ? distanceMeters : null;
}
