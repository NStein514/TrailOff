import 'dart:async';

import 'package:flutter/material.dart' show CustomScrollView;
import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/hike_recording.dart';
import 'package:trailoff/main.dart';
import 'package:trailoff/offline_map.dart';

void main() {
  testWidgets('records GPS points and saves a hike to history', (
    WidgetTester tester,
  ) async {
    final locationSource = _FakeLocationSource();
    final historyStore = _MemoryHikeHistoryStore();
    final offlineMaps = _FakeOfflineMapRepository();
    await tester.pumpWidget(
      TrailOffApp(
        locationSource: locationSource,
        historyStore: historyStore,
        offlineMapRepository: offlineMaps,
        offlineMapSupported: true,
        nativeMapSupported: false,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(locationSource.close);

    await tester.ensureVisible(find.text('Record a hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record a hike'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Finish hike'), findsOneWidget);
    locationSource.add(_point(latitude: 46.8, longitude: 0.0, altitude: 120));
    locationSource.add(
      _point(latitude: 46.8, longitude: 0.0001, altitude: 132),
    );
    locationSource.add(
      _point(latitude: 46.8, longitude: 0.0002, altitude: 200, accuracy: 90),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('0.01 km'));
    await tester.pumpAndSettle();

    expect(find.text('0.01 km'), findsOneWidget);
    expect(find.text('132 m'), findsNWidgets(2));
    expect(find.textContaining('12 m climbed'), findsOneWidget);

    await tester.ensureVisible(find.text('Finish hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish hike'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Finish hike'), findsNothing);
    expect(find.textContaining('No GPS points were received'), findsNothing);
    expect(find.textContaining('Hike saved with'), findsOneWidget);
    expect(historyStore.hikes, hasLength(1));
    expect(historyStore.hikes.single.points, hasLength(2));
    expect(historyStore.hikes.single.elevationGainMeters, 12);
    expect(find.textContaining('GPS points'), findsNWidgets(2));
    expect(find.text('Past adventures'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Download map for offline use'),
      find.byType(CustomScrollView),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download map for offline use'));
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);
    offlineMaps.reportProgress(0.5, 512 * 1024);
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('512 KB downloaded'), findsOneWidget);
    offlineMaps.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Map saved · tap to remove'), findsOneWidget);
    expect(offlineMaps.lastCreatedRegionId, 27);

    await tester.tap(find.text('Map saved · tap to remove'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(offlineMaps.deletedRegionIds, [27]);
    expect(find.text('Download map for offline use'), findsOneWidget);

    final savedHike = historyStore.hikes.single;
    final gpx = toGpx(savedHike, name: 'Trail & <ridge>');
    expect(gpx, contains('<gpx version="1.1"'));
    expect(gpx, contains('<name>Trail &amp; &lt;ridge&gt;</name>'));
    expect(gpx, contains('<trkpt lat="46.8000000" lon="0.0000000">'));
    expect(gpx, contains('<ele>120.0</ele>'));
    expect(
      gpx,
      contains(
        '<time>${savedHike.points.first.timestamp.toUtc().toIso8601String()}</time>',
      ),
    );
    expect(RegExp(r'<trkpt\s').allMatches(gpx), hasLength(2));
    expect(gpx, contains('Trail &amp; &lt;ridge&gt;'));
    expect(gpxFileName(savedHike.startedAt), endsWith('.gpx'));
    expect(find.byTooltip('Share GPX'), findsOneWidget);
  });
}

HikePoint _point({
  required double latitude,
  required double longitude,
  required double altitude,
  double accuracy = 5,
}) => HikePoint(
  latitude: latitude,
  longitude: longitude,
  altitude: altitude,
  accuracy: accuracy,
  timestamp: DateTime.now(),
);

class _FakeLocationSource implements HikeLocationSource {
  final _controller = StreamController<HikePoint>.broadcast(sync: true);

  @override
  Future<void> prepare() async {}

  @override
  Stream<HikePoint> get positions => _controller.stream;

  void add(HikePoint point) => _controller.add(point);

  Future<void> close() => _controller.close();
}

class _FakeOfflineMapRepository implements OfflineMapRepository {
  void Function(double progress, int downloadedBytes)? _onProgress;
  void Function()? _onComplete;
  int? lastCreatedRegionId;
  final deletedRegionIds = <int>[];

  @override
  Future<OfflineMapRegion?> findTourRegion() async => null;

  @override
  Future<int> downloadTourRegion({
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  }) async {
    _onProgress = onProgress;
    _onComplete = onComplete;
    lastCreatedRegionId = 27;
    return 27;
  }

  void reportProgress(double progress, int bytes) =>
      _onProgress!(progress, bytes);

  void complete() => _onComplete!();

  @override
  Future<void> deleteRegion(int id) async => deletedRegionIds.add(id);
}

class _MemoryHikeHistoryStore implements HikeHistoryStore {
  final hikes = <SavedHike>[];

  @override
  Future<List<SavedHike>> load() async => List.unmodifiable(hikes);

  @override
  Future<void> save(SavedHike hike) async => hikes.insert(0, hike);
}
