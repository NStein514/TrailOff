import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trailoff/constellation.dart';
import 'package:trailoff/satellites.dart';
import 'package:trailoff/sky_math.dart';

Position position(double latitude) => Position(
  latitude: latitude,
  longitude: -74,
  timestamp: DateTime.utc(2026, 10, 31),
  accuracy: 5,
  altitude: 20,
  altitudeAccuracy: 5,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Future<void> showSky(
  WidgetTester tester, {
  required Future<Position> Function() locate,
  required Stream<dynamic> orientation,
  SatelliteRepository? repository,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final satellites = repository ?? SatelliteRepository(apiKey: '');
  addTearDown(satellites.close);
  await tester.pumpWidget(
    MaterialApp(
      home: ConstellationPage(
        locate: locate,
        orientation: orientation,
        satellites: satellites,
        clock: clock,
      ),
    ),
  );
  await tester.tap(find.text('Use my location'));
  await tester.pump();
}

Future<void> suspend(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
}

Future<void> resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // Stream cancellation may complete in the root zone outside the fake clock.
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('expired positions are not reported as no visible satellites', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 31);
    final repository = PendingSatellites();
    final motion = StreamController<dynamic>.broadcast();
    await showSky(
      tester,
      repository: repository,
      clock: () => now,
      orientation: motion.stream,
      locate: () async => position(40),
    );
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Live satellite predictions'),
    );
    await tester.pump();
    repository.requests.single.complete([
      SatelliteTrack([
        for (var i = 0; i < 3; i++)
          SatelliteSample(
            'ISS',
            now.add(Duration(seconds: i)),
            SkyVector.horizontal(0, 45),
          ),
      ], []),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text('No full-visibility predictions for ISS or Hubble now.'),
      findsOneWidget,
    );
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.text('No full-visibility predictions for ISS or Hubble now.'),
      findsNothing,
    );
    expect(
      find.textContaining('do not cover the current time'),
      findsOneWidget,
    );
    expect(repository.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    unawaited(motion.close());
    await tester.pump();
  });
  testWidgets(
    'permission-dialog inactivity does not duplicate a pending location request',
    (tester) async {
      final fix = Completer<Position>();
      var requests = 0;
      final motion = StreamController<dynamic>.broadcast();
      await showSky(
        tester,
        orientation: motion.stream,
        locate: () {
          requests++;
          return fix.future;
        },
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await resume(tester);
      expect(requests, 1);
      fix.complete(position(40));
      await tester.pumpAndSettle();
      expect(find.textContaining('40.000°'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
    },
  );
  testWidgets(
    'resume discards pre-suspension location, even if it arrives last',
    (tester) async {
      final fixes = <Completer<Position>>[];
      final motion = StreamController<dynamic>.broadcast();
      await showSky(
        tester,
        orientation: motion.stream,
        locate: () {
          final fix = Completer<Position>();
          fixes.add(fix);
          return fix.future;
        },
      );
      expect(fixes, hasLength(1));
      await suspend(tester);
      await resume(tester);
      expect(fixes, hasLength(2));
      fixes.last.complete(position(42));
      await tester.pump();
      fixes.first.complete(position(40));
      await tester.pump();
      expect(find.textContaining('42.000°'), findsOneWidget);
      expect(find.textContaining('40.000°'), findsNothing);
      motion.add(manualSkyMatrix);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(
        find.text('Sensor aligned · approximate true north'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
    },
  );

  testWidgets(
    'suspension stops orientation and resume subscribes once with a new location',
    (tester) async {
      var starts = 0, stops = 0, fixes = 0;
      final motion = StreamController<dynamic>.broadcast(
        onListen: () => starts++,
        onCancel: () => stops++,
      );
      await showSky(
        tester,
        orientation: motion.stream,
        locate: () async => position(40 + (fixes++).toDouble()),
      );
      motion.add(manualSkyMatrix);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(starts, 1);
      await suspend(tester);
      expect(stops, 1);
      await tester.pump(const Duration(minutes: 5));
      expect(fixes, 1);
      await resume(tester);
      expect(fixes, 2);
      expect(starts, 2);
      expect(find.textContaining('41.000°'), findsOneWidget);
      expect(
        find.text('Sensor aligned · approximate true north'),
        findsNothing,
      );
      motion.add(manualSkyMatrix);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(
        find.text('Sensor aligned · approximate true north'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(stops, 2);
      unawaited(motion.close());
      await tester.pump();
    },
  );

  testWidgets(
    'malformed, failed and ended sensor streams immediately fall back',
    (tester) async {
      final motion = StreamController<dynamic>.broadcast();
      await showSky(
        tester,
        orientation: motion.stream,
        locate: () async => position(40),
      );
      for (final invalid in [
        null,
        'bad event',
        [1, 2],
        List.filled(9, 'bad'),
        List.filled(9, double.nan),
      ]) {
        motion.add(manualSkyMatrix);
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        expect(
          find.text('Sensor aligned · approximate true north'),
          findsOneWidget,
        );
        motion.add(invalid);
        await tester.pump();
        expect(
          find.text('Manual view · drag to explore (true north)'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      motion.addError(StateError('sensor disconnected'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      motion.add(manualSkyMatrix);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      unawaited(motion.close());
      await tester.pump();
      expect(
        find.text('Manual view · drag to explore (true north)'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late satellite response cannot overwrite resumed observer context',
    (tester) async {
      final repository = PendingSatellites();
      var fixes = 0;
      final motion = StreamController<dynamic>.broadcast();
      await showSky(
        tester,
        repository: repository,
        orientation: motion.stream,
        locate: () async => position(40 + (fixes++).toDouble()),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Live satellite predictions'),
      );
      await tester.pump();
      expect(repository.latitudes, [40]);
      await suspend(tester);
      await resume(tester);
      repository.requests.first.complete([]);
      await tester.pump();
      expect(find.text('N2YO · ISS & Hubble only'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.latitudes, [40, 41]);
      repository.requests.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('N2YO · ISS & Hubble only'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
    },
  );
}

class PendingSatellites extends SatelliteRepository {
  PendingSatellites() : super(apiKey: 'test');
  final requests = <Completer<List<SatelliteTrack>>>[];
  final latitudes = <double>[];
  @override
  Future<List<SatelliteTrack>> load(
    double latitude,
    double longitude,
    double altitude,
  ) {
    latitudes.add(latitude);
    final request = Completer<List<SatelliteTrack>>();
    requests.add(request);
    return request.future;
  }
}
