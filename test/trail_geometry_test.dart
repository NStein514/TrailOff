import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/hike_navigation.dart';
import 'package:trailoff/trail_catalogue.dart';
import 'package:trailoff/trail_geometry.dart';

void main() {
  test('bounds contain every point and report the box', () {
    const route = [
      TrailPoint(42.79, 0.594),
      TrailPoint(42.80, 0.60),
      TrailPoint(42.78, 0.59),
    ];
    final bounds = trailBounds(route);

    expect(bounds.south, 42.78);
    expect(bounds.north, 42.80);
    expect(bounds.west, 0.59);
    expect(bounds.east, 0.60);
    expect(bounds.centerLatitude, closeTo(42.79, 1e-9));
    expect(bounds.centerLongitude, closeTo(0.595, 1e-9));
    for (final point in route) {
      expect(bounds.contains(point), isTrue);
    }
    expect(bounds.contains(const TrailPoint(42.79, 0.605)), isFalse);
  });

  test('padding converts metres honestly at the local latitude', () {
    const point = TrailPoint(42.79, 0.594);
    final bounds = trailBounds(const [point]);
    final padded = bounds.expandedByMeters(1000);

    expect(padded.south, closeTo(42.79 - 1000 / 111320, 1e-9));
    expect(padded.north, closeTo(42.79 + 1000 / 111320, 1e-9));
    final expectedLongitudePad =
        1000 / (111320 * math.cos(42.79 * math.pi / 180));
    expect(padded.east - 0.594, closeTo(expectedLongitudePad, 1e-9));
    expect(padded.west, closeTo(0.594 - expectedLongitudePad, 1e-9));
    expect(padded.contains(point), isTrue);
  });

  test('length and longest segment measure consecutive points', () {
    expect(trailLengthMeters(const []), 0);
    expect(trailLengthMeters(const [TrailPoint(42.7, 0.5)]), 0);
    expect(longestSegmentMeters(const [TrailPoint(42.7, 0.5)]), 0);
    expect(
      trailLengthMeters(const [TrailPoint(0, 0), TrailPoint(0, 1)]),
      closeTo(111195, 20),
    );

    const route = [
      TrailPoint(42.7, 0.50),
      TrailPoint(42.7, 0.51),
      TrailPoint(42.7, 0.52),
    ];
    final segment = 111320 * 0.01 * math.cos(42.7 * math.pi / 180);
    expect(longestSegmentMeters(route), closeTo(segment, 5));
    expect(trailLengthMeters(route), closeTo(segment * 2, 10));
  });

  test('every catalogue route is connected and starts at its trailhead', () {
    for (final trail in sampleTrailCatalogue) {
      expect(trail.route.length, greaterThanOrEqualTo(4), reason: trail.id);
      expect(trailLengthMeters(trail.route), greaterThan(0), reason: trail.id);
      expect(
        longestSegmentMeters(trail.route),
        lessThan(2000),
        reason: '${trail.id} should not jump across the map',
      );
      final start = trail.route.first;
      expect(
        distanceMetersBetween(
          trail.trailheadLatitude,
          trail.trailheadLongitude,
          start.latitude,
          start.longitude,
        ),
        lessThan(200),
        reason: '${trail.id} should start at its trailhead',
      );
      final end = trail.route.last;
      expect(
        distanceMetersBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        ),
        lessThan(150),
        reason: '${trail.id} is a loop and should close',
      );
      final bounds = trailBounds(trail.route);
      for (final point in trail.route) {
        expect(bounds.contains(point), isTrue, reason: trail.id);
      }
      expect(
        bounds.latitudeSpan,
        lessThan(0.1),
        reason: '${trail.id} stays in one valley',
      );
      expect(
        bounds.longitudeSpan,
        lessThan(0.1),
        reason: '${trail.id} stays in one valley',
      );
    }
  });
}
