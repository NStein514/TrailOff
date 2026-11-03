import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailoff/hike_navigation.dart';
import 'package:trailoff/hike_recording.dart';
import 'package:trailoff/main.dart';
import 'package:trailoff/offline_map.dart';
import 'package:trailoff/trail_plan.dart';

class _MemoryPlanStore implements TrailPlanStore {
  _MemoryPlanStore([this.id]);

  String? id;

  @override
  Future<String?> loadPlannedTrailId() async => id;

  @override
  Future<void> plan(String trailId) async => id = trailId;

  @override
  Future<void> clear() async => id = null;
}

class _FakeLocationSource implements HikeLocationSource {
  final _controller = StreamController<HikePoint>.broadcast(sync: true);

  @override
  Future<void> prepare() async {}

  @override
  Stream<HikePoint> get positions => _controller.stream;

  void add(HikePoint point) => _controller.add(point);

  Future<void> close() => _controller.close();
}

class _MemoryHistoryStore implements HikeHistoryStore {
  final hikes = <SavedHike>[];

  @override
  Future<List<SavedHike>> load() async => List.unmodifiable(hikes);

  @override
  Future<void> save(SavedHike hike) async => hikes.insert(0, hike);
}

class _NoOfflineMaps implements OfflineMapRepository {
  @override
  Future<OfflineMapRegion?> findRegion(OfflineArea area) async => null;

  @override
  Future<int> downloadRegion({
    required OfflineArea area,
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  }) async => 1;

  @override
  Future<void> deleteRegion(int id) async {}
}

HikePoint _point(double latitude, double longitude, {double altitude = 900}) =>
    HikePoint(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracy: 6,
      timestamp: DateTime(2026, 11, 1, 9),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('distance and bearing match known great-circle values', () {
    expect(
      distanceMetersBetween(0, 0, 0, 1),
      closeTo(111195, 20),
      reason: 'one degree of longitude on the equator',
    );
    expect(
      distanceMetersBetween(0, 0, 1, 0),
      closeTo(111195, 20),
      reason: 'one degree of latitude is constant',
    );
    expect(distanceMetersBetween(42.79, 0.594, 42.79, 0.594), 0);

    expect(initialBearingDegrees(0, 0, 1, 0), closeTo(0, 0.001));
    expect(initialBearingDegrees(0, 0, 0, 1), closeTo(90, 0.001));
    expect(initialBearingDegrees(0, 0, -1, 0), closeTo(180, 0.001));
    expect(initialBearingDegrees(0, 0, 0, -1), closeTo(270, 0.001));
  });

  test('compass points wrap around north', () {
    expect(compassPoint(0), 'N');
    expect(compassPoint(20), 'N');
    expect(compassPoint(45), 'NE');
    expect(compassPoint(90), 'E');
    expect(compassPoint(135), 'SE');
    expect(compassPoint(180), 'S');
    expect(compassPoint(225), 'SW');
    expect(compassPoint(270), 'W');
    expect(compassPoint(315), 'NW');
    expect(compassPoint(350), 'N');
    expect(compassPoint(-90), 'W');
    expect(compassPoint(720), 'N');
  });

  test('trailhead bearing reports metric distance and direction', () {
    final bearing = bearingToTrailhead(
      fromLatitude: 42.80,
      fromLongitude: 0.60,
      trailheadLatitude: 42.79,
      trailheadLongitude: 0.594,
    );
    expect(bearing.distanceMeters, closeTo(1215, 15));
    expect(bearing.distanceLabel(), '1.2 km');
    // Standing north-east of the trailhead, so the way back is south-west.
    expect(bearing.directionLabel, 'SW');
    expect(bearing.summary(), '1.2 km · SW');

    const close = TrailheadBearing(distanceMeters: 850, bearingDegrees: 200);
    expect(close.distanceLabel(), '850 m');
    expect(close.directionLabel, 'S');
  });

  test('saved hikes keep their planned trail through storage', () {
    final startedAt = DateTime(2026, 11, 1, 9);
    final hike = SavedHike(
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(hours: 1)),
      durationSeconds: 3600,
      distanceMeters: 3200,
      elevationGainMeters: 120,
      points: [_point(42.79, 0.594)],
      plannedTrailId: 'bois-pique',
      plannedTrailName: 'Bois de la Pique circuit',
    );

    final restored = SavedHike.fromJson(
      jsonDecode(jsonEncode(hike.toJson())) as Map<String, dynamic>,
    );
    expect(restored.plannedTrailId, 'bois-pique');
    expect(restored.plannedTrailName, 'Bois de la Pique circuit');
    expect(restored.points, hasLength(1));
  });

  test('hikes saved before planning existed still load', () {
    final legacy =
        jsonDecode(
              jsonEncode({
                'startedAt': '2026-10-30T08:00:00.000',
                'finishedAt': '2026-10-30T10:00:00.000',
                'durationSeconds': 7200,
                'distanceMeters': 8000.0,
                'elevationGainMeters': 400.0,
                'points': [_point(42.7, 0.5).toJson()],
              }),
            )
            as Map<String, dynamic>;

    final restored = SavedHike.fromJson(legacy);
    expect(restored.plannedTrailId, isNull);
    expect(restored.plannedTrailName, isNull);
    expect(restored.distanceMeters, 8000);
  });

  testWidgets('warns when the live track leaves the planned route', (
    WidgetTester tester,
  ) async {
    final locationSource = _FakeLocationSource();
    await tester.pumpWidget(
      TrailOffApp(
        locationSource: locationSource,
        historyStore: _MemoryHistoryStore(),
        offlineMapRepository: _NoOfflineMaps(),
        offlineMapSupported: false,
        nativeMapSupported: false,
        trailPlanStore: _MemoryPlanStore('bois-pique'),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(locationSource.close);

    await tester.scrollUntilVisible(find.text('Record a hike'), 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Record a hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record a hike'));
    await tester.pump();
    expect(find.byKey(const Key('off-route-warning')), findsNothing);

    // Kilometres away from the Bois de la Pique circuit.
    locationSource.add(_point(42.80, 0.61));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('off-route-warning')));
    expect(find.byKey(const Key('off-route-warning')), findsOneWidget);
    expect(find.text('OFF THE PLANNED ROUTE'), findsOneWidget);
    expect(
      find.textContaining('from the line. Head back towards it.'),
      findsOneWidget,
    );

    // Standing on a vertex of the route again clears the warning.
    locationSource.add(_point(42.7922, 0.5962));
    await tester.pump();
    expect(find.byKey(const Key('off-route-warning')), findsNothing);
  });

  testWidgets('recording follows the plan and history keeps the trail', (
    WidgetTester tester,
  ) async {
    final locationSource = _FakeLocationSource();
    final historyStore = _MemoryHistoryStore();
    await tester.pumpWidget(
      TrailOffApp(
        locationSource: locationSource,
        historyStore: historyStore,
        offlineMapRepository: _NoOfflineMaps(),
        offlineMapSupported: false,
        nativeMapSupported: false,
        trailPlanStore: _MemoryPlanStore('bois-pique'),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(locationSource.close);

    await tester.scrollUntilVisible(find.text('Record a hike'), 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Record a hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record a hike'));
    await tester.pump();

    // Heading north-east away from the trailhead.
    locationSource.add(_point(42.80, 0.60));
    await tester.pump();

    final expected = bearingToTrailhead(
      fromLatitude: 42.80,
      fromLongitude: 0.60,
      trailheadLatitude: 42.79,
      trailheadLongitude: 0.594,
    );
    expect(
      find.text('Back to Bois de la Pique circuit trailhead'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.textContaining(expected.summary()));
    expect(find.text('${expected.summary()} · straight line'), findsOneWidget);

    await tester.ensureVisible(find.text('Finish hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish hike'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(historyStore.hikes, hasLength(1));
    expect(historyStore.hikes.single.plannedTrailId, 'bois-pique');
    expect(
      historyStore.hikes.single.plannedTrailName,
      'Bois de la Pique circuit',
    );
    expect(
      toGpx(historyStore.hikes.single, name: 'Bois de la Pique circuit'),
      contains('<name>Bois de la Pique circuit</name>'),
    );

    final scroll = find.byType(CustomScrollView);
    for (
      var attempt = 0;
      attempt < 12 && find.text('Past adventures').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scroll, const Offset(0, -450));
      await tester.pumpAndSettle();
    }
    expect(find.text('Past adventures'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Bois de la Pique circuit'),
      ),
      findsOneWidget,
    );
  });
}
