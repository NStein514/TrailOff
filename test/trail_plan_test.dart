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

class _NoOfflineMaps implements OfflineMapRepository {
  @override
  Future<OfflineMapRegion?> findTourRegion() async => null;

  @override
  Future<int> downloadTourRegion({
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  }) async => 0;

  @override
  Future<void> deleteRegion(int id) async {}
}

Future<void> _pumpDashboard(WidgetTester tester, TrailPlanStore store) async {
  await tester.pumpWidget(
    TrailOffApp(
      locationSource: _IdleLocationSource(),
      historyStore: _EmptyHistoryStore(),
      offlineMapRepository: _NoOfflineMaps(),
      offlineMapSupported: false,
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
    final store = _MemoryPlanStore('portillon-loop');
    await _pumpDashboard(tester, store);
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
