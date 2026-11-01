import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/offline_map.dart';
import 'package:trailoff/trail_catalogue.dart';

void main() {
  test('offline areas are boxes around the trailhead', () {
    final trail = sampleTrailCatalogue.firstWhere(
      (trail) => trail.id == 'oo-espingo',
    );
    final area = OfflineArea.forTrail(trail);

    expect(area.id, 'oo-espingo');
    expect(area.name, trail.name);
    expect(area.south, lessThan(trail.trailheadLatitude));
    expect(area.north, greaterThan(trail.trailheadLatitude));
    expect(area.west, lessThan(trail.trailheadLongitude));
    expect(area.east, greaterThan(trail.trailheadLongitude));
    expect(area.north - area.south, closeTo(0.1, 1e-9));
    expect(area.east - area.west, closeTo(0.13, 1e-9));
  });

  test('the tour trail keeps the legacy area identifier', () {
    final tour = sampleTrailCatalogue.firstWhere(
      (trail) => trail.id == defaultOfflineArea.id,
    );
    expect(OfflineArea.forTrail(tour).id, 'tour-du-portillon');
  });

  test('every catalogue trail has a distinct area', () {
    final ids = sampleTrailCatalogue.map((trail) => trail.id).toSet();
    expect(ids, hasLength(sampleTrailCatalogue.length));
    expect(
      ids,
      containsAll(
        sampleTrailCatalogue.map((trail) => OfflineArea.forTrail(trail).id),
      ),
    );
  });
}
