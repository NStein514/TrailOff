import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/route_tracking.dart';
import 'package:trailoff/trail_geometry.dart';

const _eastWestRoute = [TrailPoint(42.79, 0.594), TrailPoint(42.79, 0.600)];

void main() {
  test('a fix on the line is on route with its progress along it', () {
    final middle = matchRoute(
      route: _eastWestRoute,
      latitude: 42.79,
      longitude: 0.597,
    )!;
    expect(middle.distanceMeters, lessThan(1));
    expect(middle.totalMeters, closeTo(490, 2));
    expect(middle.metersAlongRoute, closeTo(245, 2));
    expect(middle.fractionAlongRoute, closeTo(0.5, 0.01));

    final start = matchRoute(
      route: _eastWestRoute,
      latitude: 42.79,
      longitude: 0.594,
    )!;
    expect(start.distanceMeters, lessThan(1));
    expect(start.metersAlongRoute, closeTo(0, 1));
    expect(start.fractionAlongRoute, closeTo(0, 0.01));

    final end = matchRoute(
      route: _eastWestRoute,
      latitude: 42.79,
      longitude: 0.6006,
    )!;
    expect(end.fractionAlongRoute, 1);
  });

  test(
    'a nearby fix reports its distance to the nearest point of the line',
    () {
      final match = matchRoute(
        route: _eastWestRoute,
        latitude: 42.7927,
        longitude: 0.597,
      )!;
      expect(match.distanceMeters, closeTo(300, 2));
      expect(match.fractionAlongRoute, closeTo(0.5, 0.02));
    },
  );

  test('a fix past the end measures from the last vertex', () {
    final match = matchRoute(
      route: _eastWestRoute,
      latitude: 42.79,
      longitude: 0.606,
    )!;
    // 0.006 degrees of longitude east of the last vertex at this latitude.
    expect(match.distanceMeters, closeTo(490, 3));
    expect(match.metersAlongRoute, closeTo(match.totalMeters, 0.5));
  });

  test('routes with no or one vertex are handled', () {
    expect(
      matchRoute(route: const [], latitude: 42.79, longitude: 0.594),
      isNull,
    );
    final single = matchRoute(
      route: const [TrailPoint(42.79, 0.594)],
      latitude: 42.79,
      longitude: 0.594,
    )!;
    expect(single.distanceMeters, lessThan(1));
    expect(single.totalMeters, 0);
    expect(single.fractionAlongRoute, 0);
  });

  test('the warning starts late and clears early', () {
    expect(offRouteDistanceAfter(distanceMeters: 150, previous: null), isNull);
    expect(offRouteDistanceAfter(distanceMeters: 205, previous: null), 205);

    // Still warning just inside the warning threshold, until the clear radius.
    expect(offRouteDistanceAfter(distanceMeters: 150, previous: 205), 150);
    expect(offRouteDistanceAfter(distanceMeters: 121, previous: 205), 121);
    expect(offRouteDistanceAfter(distanceMeters: 100, previous: 205), isNull);
    expect(offRouteDistanceAfter(distanceMeters: 0, previous: 205), isNull);
  });
}
