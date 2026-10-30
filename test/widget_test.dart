import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/hike_recording.dart';
import 'package:trailoff/main.dart';

void main() {
  testWidgets('records GPS points and saves a hike to history', (
    WidgetTester tester,
  ) async {
    final locationSource = _FakeLocationSource();
    final historyStore = _MemoryHikeHistoryStore();
    await tester.pumpWidget(
      TrailOffApp(locationSource: locationSource, historyStore: historyStore),
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

class _MemoryHikeHistoryStore implements HikeHistoryStore {
  final hikes = <SavedHike>[];

  @override
  Future<List<SavedHike>> load() async => List.unmodifiable(hikes);

  @override
  Future<void> save(SavedHike hike) async => hikes.insert(0, hike);
}
