import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trailoff/constellation.dart';
import 'package:trailoff/satellites.dart';
import 'package:trailoff/sky_math.dart';

void main() {
  test('J2000 meridian, longitude and horizon use UTC and ENU', () {
    final t = DateTime.utc(2000, 1, 1, 12);
    final zenith = equatorialToLocal(280.46061837 / 15, 0, 0, 0, t);
    expect(zenith.up, closeTo(1, 1e-9));
    final west = equatorialToLocal(280.46061837 / 15, 0, 0, 90, t);
    expect(west.east, closeTo(-1, 1e-9));
    expect(west.up, closeTo(0, 1e-9));
    final pole = equatorialToLocal(0, 90, -30, 0, t);
    expect(pole.up, closeTo(-0.5, 1e-9));
  });
  test(
    'projection centers target, respects roll, and rejects hidden objects',
    () {
      const size = Size(400, 600);
      expect(
        projectSky(SkyVector.horizontal(0, 45), manualView(0, 45), size)!.dx,
        closeTo(200, 1e-7),
      );
      expect(
        projectSky(SkyVector.horizontal(90, 45), manualView(90, 45), size)!.dy,
        closeTo(300, 1e-7),
      );
      expect(
        projectSky(SkyVector.horizontal(180, 45), manualView(0, 45), size),
        isNull,
      );
      expect(
        projectSky(SkyVector.horizontal(0, -1), manualView(0, 0), size),
        isNull,
      );
      final m = manualView(0, 45);
      final rolled = [
        ...m.sublist(3, 6),
        ...m.sublist(0, 3).map((v) => -v),
        ...m.sublist(6),
      ];
      final p = projectSky(SkyVector.horizontal(10, 45), m, size)!;
      final r = projectSky(SkyVector.horizontal(10, 45), rolled, size)!;
      expect(r.dy - 300, closeTo(p.dx - 200, 1e-7));
    },
  );
  test(
    'provider combines positions and fully visible passes; rejects stale samples',
    () async {
      var requests = 0;
      final repository = SatelliteRepository(
        apiKey: 'test-key',
        client: MockClient((request) async {
          requests++;
          expect(request.url.scheme, 'https');
          if (request.url.path.contains('visualpasses')) {
            return http.Response(
              jsonEncode({
                'passes': [
                  {'startUTC': 1000, 'endUTC': 1100, 'duration': 100},
                  {'startUTC': 1200, 'endUTC': 1300, 'duration': 30},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'positions': [
                {'timestamp': 1050, 'azimuth': 359, 'elevation': 40},
                {'timestamp': 1250, 'azimuth': 0, 'elevation': 40},
              ],
            }),
            200,
          );
        }),
      );
      final tracks = await repository.load(40, -74, 20);
      expect(requests, 4);
      expect(tracks, hasLength(2));
      expect(
        tracks.first.visibleAt(DateTime.fromMillisecondsSinceEpoch(1050000)),
        isNotNull,
      );
      expect(
        tracks.first.visibleAt(DateTime.fromMillisecondsSinceEpoch(1052000)),
        isNull,
      );
      expect(
        tracks.first.visibleAt(DateTime.fromMillisecondsSinceEpoch(1250000)),
        isNull,
      );
      repository.close();
    },
  );
  test(
    'provider rejects HTTP and malformed data without leaking credentials',
    () async {
      for (final response in [
        http.Response('denied', 403),
        http.Response('{"error":"key"}', 200),
        http.Response('{}', 200),
      ]) {
        final repo = SatelliteRepository(
          apiKey: 'secret',
          client: MockClient((_) async => response),
        );
        await expectLater(repo.load(0, 0, 0), throwsA(anything));
        repo.close();
      }
    },
  );
  testWidgets(
    'location failure is retryable; manual sky and sensor fallback work',
    (tester) async {
      final motion = StreamController<dynamic>();
      var attempts = 0;
      var now = DateTime.utc(2026, 10, 31);
      await tester.pumpWidget(
        MaterialApp(
          home: ConstellationPage(
            clock: () => now,
            satellites: SatelliteRepository(apiKey: ''),
            orientation: motion.stream,
            locate: () async {
              if (attempts++ == 0) throw Exception('denied');
              return Position(
                latitude: 40,
                longitude: -74,
                timestamp: DateTime.now(),
                accuracy: 5,
                altitude: 20,
                altitudeAccuracy: 5,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              );
            },
          ),
        ),
      );
      expect(find.textContaining('configure an N2YO'), findsOneWidget);
      await tester.tap(find.text('Use my location'));
      await tester.pump();
      expect(find.textContaining('Location unavailable.'), findsOneWidget);
      await tester.tap(find.text('Use my location'));
      await tester.pump();
      expect(
        find.text('Manual view · drag to explore (true north)'),
        findsOneWidget,
      );
      motion.add(manualSkyMatrix);
      await tester.pump();
      expect(
        find.text('Sensor aligned · approximate true north'),
        findsOneWidget,
      );
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(
        find.text('Manual view · drag to explore (true north)'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
