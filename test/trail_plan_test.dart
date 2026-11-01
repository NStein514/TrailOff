import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailoff/hike_recording.dart';
import 'package:trailoff/main.dart';
import 'package:trailoff/offline_map.dart';
import 'package:trailoff/trail_catalogue.dart';
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

class _IdleLocationSource implements HikeLocationSource {
  @override
  Future<void> prepare() async {}

  @override
  Stream<HikePoint> get positions => const Stream.empty();
}

class _EmptyHistoryStore implements HikeHistoryStore {
  @override
  Future<List<SavedHike>> load() async => const [];

  @override
  Future<void> save(SavedHike hike) async {}
}

class _RecordingOfflineMaps implements OfflineMapRepository {
  _RecordingOfflineMaps({Map<String, bool>? savedAreas})
    : savedAreas = savedAreas ?? {};

  final Map<String, bool> savedAreas;
  OfflineArea? lastArea;

  @override
  Future<OfflineMapRegion?> findRegion(OfflineArea area) async {
    final complete = savedAreas[area.id];
    if (complete == null) return null;
    return OfflineMapRegion(id: area.id.hashCode, isComplete: complete);
  }

  @override
  Future<int> downloadRegion({
    required OfflineArea area,
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  }) async {
    lastArea = area;
    return 7;
  }

  @override
  Future<void> deleteRegion(int id) async {}
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  TrailPlanStore store, {
  OfflineMapRepository? offlineMaps,
  bool offlineMapSupported = false,
}) async {
  await tester.pumpWidget(
    TrailOffApp(
      locationSource: _IdleLocationSource(),
      historyStore: _EmptyHistoryStore(),
      offlineMapRepository: offlineMaps ?? _RecordingOfflineMaps(),
      offlineMapSupported: offlineMapSupported,
      nativeMapSupported: false,
      trailPlanStore: store,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the planned trail is stored and cleared on device', () async {
    final store = SharedPreferencesTrailPlanStore();
    expect(await store.loadPlannedTrailId(), isNull);

    await store.plan('glere-refuge');
    expect(await store.loadPlannedTrailId(), 'glere-refuge');

    await store.clear();
    expect(await store.loadPlannedTrailId(), isNull);
  });

  test('plans for unknown trails are ignored', () {
    expect(plannedTrail(sampleTrailCatalogue, null), isNull);
    expect(plannedTrail(sampleTrailCatalogue, 'removed-trail'), isNull);
    expect(
      plannedTrail(sampleTrailCatalogue, 'glere-refuge')?.name,
      'Refuge de la Glère',
    );
  });

  testWidgets('dashboard shows the plan, refits it and clears it', (
    WidgetTester tester,
  ) async {
    final store = _MemoryPlanStore('tour-du-portillon');
    await _pumpDashboard(tester, store);
    expect(find.text('Lac du Portillon'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-trail')),
      250,
    );

    expect(find.text('Your plan'), findsOneWidget);
    expect(find.text('Lac du Portillon loop'), findsOneWidget);
    expect(find.text('12.4 km · +1120 m ascent · 5 h 30'), findsOneWidget);
    expect(find.text('Too demanding today'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('ability-selector')),
      240,
    );
    await tester.tap(find.byKey(const Key('ability-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-trail')),
      -240,
    );
    expect(find.text('Fits today'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-plan')));
    await tester.pumpAndSettle();
    expect(store.id, isNull);
    expect(find.textContaining('No trail planned yet'), findsOneWidget);
    expect(find.text('Lac du Portillon loop'), findsNothing);
  });

  testWidgets('offline download follows the planned trail', (
    WidgetTester tester,
  ) async {
    final maps = _RecordingOfflineMaps();
    await _pumpDashboard(
      tester,
      _MemoryPlanStore('oo-espingo'),
      offlineMaps: maps,
      offlineMapSupported: true,
    );

    // The drawn fallback must not keep claiming to show the tour.
    expect(find.text('Lac du Portillon'), findsNothing);
    expect(find.text('Lac d’Oô & Espingo'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Download map for offline use'),
      250,
    );
    await tester.tap(find.text('Download map for offline use'));
    await tester.pump();

    expect(maps.lastArea?.id, 'oo-espingo');
    expect(maps.lastArea?.name, 'Lac d’Oô & Espingo');
    expect(maps.lastArea!.south, closeTo(42.678, 0.0001));
    expect(maps.lastArea!.north, closeTo(42.778, 0.0001));
  });

  testWidgets('a saved area is recognised for the planned trail only', (
    WidgetTester tester,
  ) async {
    final maps = _RecordingOfflineMaps(savedAreas: {'bois-pique': true});
    await _pumpDashboard(
      tester,
      _MemoryPlanStore('bois-pique'),
      offlineMaps: maps,
      offlineMapSupported: true,
    );

    await tester.scrollUntilVisible(
      find.text('Map saved · tap to remove'),
      250,
    );
    expect(find.text('Map saved · tap to remove'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-trail')),
      250,
    );
    await tester.tap(find.byKey(const Key('clear-plan')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Download map for offline use'),
      -250,
    );
    expect(find.text('Download map for offline use'), findsOneWidget);
  });

  testWidgets('the packing checklist follows the planned trail', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, _MemoryPlanStore('tour-du-portillon'));
    await tester.scrollUntilVisible(
      find.text('Tailored to Lac du Portillon loop · 12.4 km · +1120 m'),
      300,
    );
    expect(
      find.text('Tailored to Lac du Portillon loop · 12.4 km · +1120 m'),
      findsOneWidget,
    );
    expect(find.text('Trekking poles'), findsOneWidget);
    // The dashboard starts on dry conditions, so this is a half litre above
    // the 3 L the same route needs in the wet.
    expect(find.text('About 3.5 L for 5 h 30 on the trail'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-trail')),
      -300,
    );
    await tester.tap(find.byKey(const Key('clear-plan')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Suggested essentials · check off what you have packed'),
      300,
    );
    expect(find.text('Trekking poles'), findsNothing);
  });

  testWidgets('dashboard invites a route when nothing is planned', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, _MemoryPlanStore());
    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-trail')),
      250,
    );

    expect(find.textContaining('No trail planned yet'), findsOneWidget);
    expect(find.text('Find a route'), findsOneWidget);
  });
}
