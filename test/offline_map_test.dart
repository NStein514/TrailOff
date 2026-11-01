import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/offline_map.dart';
import 'package:trailoff/trail_catalogue.dart';
import 'package:trailoff/trail_geometry.dart';

void main() {
  test('offline areas cover the whole route plus a margin', () {
    final trail = sampleTrailCatalogue.firstWhere(
      (trail) => trail.id == 'oo-espingo',
    );
    final area = OfflineArea.forTrail(trail);
    final bounds = trailBounds(trail.route);

    expect(area.id, 'oo-espingo');
    expect(area.name, trail.name);
    expect(area.south, lessThan(bounds.south));
    expect(area.north, greaterThan(bounds.north));
    expect(area.west, lessThan(bounds.west));
    expect(area.east, greaterThan(bounds.east));

    // Roughly 1.5 km of margin on the north–south sides.
    expect(area.north - bounds.north, closeTo(1500 / 111320, 1e-9));
    expect(bounds.south - area.south, closeTo(1500 / 111320, 1e-9));
  });

  test('every route fits inside its own saved area', () {
    for (final trail in sampleTrailCatalogue) {
      final area = OfflineArea.forTrail(trail);
      final bounds = trailBounds(trail.route);
      expect(area.south, lessThanOrEqualTo(bounds.south), reason: trail.id);
      expect(area.north, greaterThanOrEqualTo(bounds.north), reason: trail.id);
      expect(area.west, lessThanOrEqualTo(bounds.west), reason: trail.id);
      expect(area.east, greaterThanOrEqualTo(bounds.east), reason: trail.id);
    }
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
