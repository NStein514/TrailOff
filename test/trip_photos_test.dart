import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailoff/hike_recording.dart';
import 'package:trailoff/main.dart';
import 'package:trailoff/offline_map.dart';
import 'package:trailoff/trail_plan.dart';
import 'package:trailoff/trip_album_page.dart';
import 'package:trailoff/trip_photos.dart';

final _tripStart = DateTime(2026, 11, 1, 9);

class _MemoryPhotoStore implements TripPhotoStore {
  _MemoryPhotoStore([List<TripPhoto>? initial]) : photos = [...?initial];

  final List<TripPhoto> photos;
  int _nextId = 0;

  @override
  Future<List<TripPhoto>> loadAll() async => List.unmodifiable(photos);

  @override
  Future<TripPhoto> add({
    required String tripKey,
    required PickedTripPhoto photo,
    String? trailId,
    String? trailName,
  }) async {
    final stored = TripPhoto(
      id: 'photo-${_nextId++}',
      path: photo.path,
      tripKey: tripKey,
      capturedAt: DateTime.now(),
      trailId: trailId,
      trailName: trailName,
    );
    photos.insert(0, stored);
    return stored;
  }

  @override
  Future<void> remove(TripPhoto photo) async {
    photos.removeWhere((entry) => entry.id == photo.id);
  }
}

class _FakePicker implements TripPhotoPicker {
  _FakePicker(this.path);

  final String path;
  TripPhotoSource? lastSource;
  int calls = 0;

  @override
  Future<PickedTripPhoto?> pick(TripPhotoSource source) async {
    calls++;
    lastSource = source;
    return PickedTripPhoto(path);
  }
}

class _MemoryPlanStore implements TrailPlanStore {
  @override
  Future<String?> loadPlannedTrailId() async => null;

  @override
  Future<void> plan(String trailId) async {}

  @override
  Future<void> clear() async {}
}

class _IdleLocationSource implements HikeLocationSource {
  @override
  Future<void> prepare() async {}

  @override
  Stream<HikePoint> get positions => const Stream.empty();
}

class _FixedHistoryStore implements HikeHistoryStore {
  _FixedHistoryStore(this.hikes);

  final List<SavedHike> hikes;

  @override
  Future<List<SavedHike>> load() async => List.unmodifiable(hikes);

  @override
  Future<void> save(SavedHike hike) async => hikes.insert(0, hike);
}

class _StreamLocationSource implements HikeLocationSource {
  final _controller = StreamController<HikePoint>.broadcast(sync: true);

  @override
  Future<void> prepare() async {}

  @override
  Stream<HikePoint> get positions => _controller.stream;

  void add(HikePoint point) => _controller.add(point);

  Future<void> close() => _controller.close();
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

SavedHike _trip() {
  final startedAt = _tripStart;
  return SavedHike(
    startedAt: startedAt,
    finishedAt: startedAt.add(const Duration(hours: 1)),
    durationSeconds: 3600,
    distanceMeters: 3200,
    elevationGainMeters: 120,
    points: [
      HikePoint(
        latitude: 42.79,
        longitude: 0.594,
        altitude: 900,
        timestamp: startedAt,
      ),
      HikePoint(
        latitude: 42.7922,
        longitude: 0.5962,
        altitude: 940,
        timestamp: startedAt.add(const Duration(minutes: 30)),
      ),
    ],
    plannedTrailId: 'bois-pique',
    plannedTrailName: 'Bois de la Pique circuit',
  );
}

Future<void> _pumpAlbum(
  WidgetTester tester, {
  required TripPhotoStore store,
  required TripPhotoPicker picker,
  SavedHike? trip,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TripAlbumPage(trip: trip ?? _trip(), store: store, picker: picker),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDirectory;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('trailoff_photos');
  });

  tearDownAll(() => tempDirectory.delete(recursive: true));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<String> writePng(String name) async {
    final file = File('${tempDirectory.path}/$name.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
    );
    return file.path;
  }

  test('trip keys are UTC and photos survive a storage round trip', () {
    expect(
      tripKeyFor(DateTime.utc(2026, 11, 1, 9)),
      '2026-11-01T09:00:00.000Z',
    );
    // The same instant gives the same key whatever the local zone is.
    expect(
      tripKeyFor(DateTime.utc(2026, 11, 1, 9)),
      tripKeyFor(DateTime.utc(2026, 11, 1, 9).toLocal()),
    );
    expect(tripKeyFor(_tripStart), tripKeyFor(_tripStart.toLocal()));

    final photo = TripPhoto(
      id: 'photo-1',
      path: '/photos/photo-1.jpg',
      tripKey: tripKeyFor(_tripStart),
      capturedAt: DateTime(2026, 11, 1, 9, 42),
      trailId: 'bois-pique',
      trailName: 'Bois de la Pique circuit',
    );
    final restored = TripPhoto.fromJson(
      jsonDecode(jsonEncode(photo.toJson())) as Map<String, dynamic>,
    );
    expect(restored.id, photo.id);
    expect(restored.path, photo.path);
    expect(restored.tripKey, photo.tripKey);
    expect(restored.capturedAt, photo.capturedAt);
    expect(restored.trailId, 'bois-pique');
    expect(restored.trailName, 'Bois de la Pique circuit');
  });

  test('an empty store reads without touching device storage', () async {
    expect(await FileTripPhotoStore().loadAll(), isEmpty);
  });

  testWidgets('an empty album invites a photo and adding one fills it', (
    WidgetTester tester,
  ) async {
    final store = _MemoryPhotoStore();
    final picker = _FakePicker(
      (await tester.runAsync(() => writePng('first')))!,
    );

    await _pumpAlbum(tester, store: store, picker: picker);

    expect(find.text('Trip album'), findsOneWidget);
    expect(find.text('Bois de la Pique circuit'), findsOneWidget);
    expect(find.text('No photos in this album yet'), findsOneWidget);
    expect(
      find.text('Photos stay on this device with this trip.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(picker.lastSource, TripPhotoSource.camera);
    expect(store.photos, hasLength(1));
    expect(store.photos.single.tripKey, tripKeyFor(_tripStart));
    expect(store.photos.single.trailId, 'bois-pique');
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.text('1 photo kept on this device with this trip.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Add from gallery'));
    await tester.pumpAndSettle();
    expect(picker.lastSource, TripPhotoSource.gallery);
    expect(store.photos, hasLength(2));
    expect(
      find.text('2 photos kept on this device with this trip.'),
      findsOneWidget,
    );
  });

  testWidgets('a photo can be opened and deleted from the album', (
    WidgetTester tester,
  ) async {
    final path = (await tester.runAsync(() => writePng('delete-me')))!;
    final store = _MemoryPhotoStore([
      TripPhoto(
        id: 'photo-0',
        path: path,
        tripKey: tripKeyFor(_tripStart),
        capturedAt: DateTime(2026, 11, 1, 10, 5),
      ),
    ]);
    final picker = _FakePicker(path);

    await _pumpAlbum(tester, store: store, picker: picker);

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close photo'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete this photo?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect(store.photos, isEmpty);
    expect(find.text('No photos in this album yet'), findsOneWidget);
  });

  testWidgets('a photo taken mid-hike lands in the saved trip album', (
    WidgetTester tester,
  ) async {
    final locationSource = _StreamLocationSource();
    final history = _FixedHistoryStore([]);
    final store = _MemoryPhotoStore();
    final photoPath = (await tester.runAsync(() => writePng('midhike')))!;

    await tester.pumpWidget(
      TrailOffApp(
        locationSource: locationSource,
        historyStore: history,
        offlineMapRepository: _NoOfflineMaps(),
        offlineMapSupported: false,
        nativeMapSupported: false,
        trailPlanStore: _MemoryPlanStore(),
        tripPhotoStore: store,
        tripPhotoPicker: _FakePicker(photoPath),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(locationSource.close);

    await tester.scrollUntilVisible(find.text('Record a hike'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record a hike'));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('take-hike-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('take-hike-photo')));
    await tester.pumpAndSettle();

    expect(store.photos, hasLength(1));
    expect(find.text('Take a photo · 1 kept'), findsOneWidget);

    await tester.ensureVisible(find.text('Finish hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish hike'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // No GPS arrived, but the photo keeps the trip alive and reachable.
    expect(history.hikes, hasLength(1));
    expect(history.hikes.single.points, isEmpty);
    expect(
      store.photos.single.tripKey,
      tripKeyFor(history.hikes.single.startedAt),
    );
    expect(find.textContaining('saved with its photos only'), findsOneWidget);
  });

  testWidgets('a hike with no GPS and no photos is still not saved', (
    WidgetTester tester,
  ) async {
    final locationSource = _StreamLocationSource();
    final history = _FixedHistoryStore([]);

    await tester.pumpWidget(
      TrailOffApp(
        locationSource: locationSource,
        historyStore: history,
        offlineMapRepository: _NoOfflineMaps(),
        offlineMapSupported: false,
        nativeMapSupported: false,
        trailPlanStore: _MemoryPlanStore(),
        tripPhotoStore: _MemoryPhotoStore(),
        tripPhotoPicker: _FakePicker('unused.png'),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(locationSource.close);

    await tester.scrollUntilVisible(find.text('Record a hike'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record a hike'));
    await tester.pump();
    await tester.ensureVisible(find.text('Finish hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish hike'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(history.hikes, isEmpty);
    expect(find.textContaining('so this hike was not saved'), findsOneWidget);
  });

  testWidgets('a saved trip opens its album from the history list', (
    WidgetTester tester,
  ) async {
    final trip = _trip();
    final historyPhoto = (await tester.runAsync(() => writePng('history')))!;
    final unusedPhoto = (await tester.runAsync(() => writePng('unused')))!;
    final store = _MemoryPhotoStore([
      TripPhoto(
        id: 'photo-0',
        path: historyPhoto,
        tripKey: tripKeyFor(trip.startedAt),
        capturedAt: DateTime(2026, 11, 1, 10),
      ),
    ]);

    await tester.pumpWidget(
      TrailOffApp(
        locationSource: _IdleLocationSource(),
        historyStore: _FixedHistoryStore([trip]),
        offlineMapRepository: _NoOfflineMaps(),
        offlineMapSupported: false,
        nativeMapSupported: false,
        trailPlanStore: _MemoryPlanStore(),
        tripPhotoStore: store,
        tripPhotoPicker: _FakePicker(unusedPhoto),
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byType(CustomScrollView);
    for (
      var attempt = 0;
      attempt < 12 &&
          find.byTooltip('Trip album · 1 photos').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scroll, const Offset(0, -450));
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Trip album · 1 photos'), findsOneWidget);

    await tester.tap(find.byTooltip('Trip album · 1 photos'));
    await tester.pumpAndSettle();

    expect(find.text('Trip album'), findsOneWidget);
    expect(find.text('Bois de la Pique circuit'), findsWidgets);
    expect(find.byType(Image), findsOneWidget);
  });
}
