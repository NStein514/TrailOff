import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trailoff/satellites.dart';
import 'package:trailoff/sky_math.dart';

DateTime at(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

void main() {
  test('interpolation crosses north, not the opposite side of the sky', () {
    final track = SatelliteTrack(
      [
        SatelliteSample('ISS', at(1000000), SkyVector.horizontal(359, 45)),
        SatelliteSample('ISS', at(1001000), SkyVector.horizontal(1, 45)),
      ],
      [(999, 1001)],
    );
    final sample = track.visibleAt(at(1000500))!;
    expect(sample.direction.east, closeTo(0, 1e-8));
    expect(sample.direction.north, greaterThan(0.7));
    expect(sample.time, at(1000500));
    expect(track.positionAt(at(999999)), isNull);
    expect(track.positionAt(at(1001001)), isNull);
  });

  test('coverage, optical visibility and horizon are independent', () {
    final track = SatelliteTrack(
      [
        SatelliteSample('ISS', at(1000000), SkyVector.horizontal(0, -1)),
        SatelliteSample('ISS', at(1001000), SkyVector.horizontal(0, 1)),
        SatelliteSample('ISS', at(1002000), SkyVector.horizontal(0, 2)),
      ],
      [(999, 1001)],
    );
    expect(track.positionAt(at(1000000)), isNotNull);
    expect(track.visibleAt(at(1000000)), isNull);
    expect(track.visibleAt(at(1001000)), isNotNull);
    expect(track.visibleAt(at(1001001)), isNull);
    expect(track.positionAt(at(1001001)), isNotNull);
    final gap = SatelliteTrack([track.samples.first, track.samples.last], []);
    expect(gap.positionAt(at(1001000)), isNull);
  });

  for (final invalid in [
    'wrong id',
    'missing id',
    'stale',
    'future',
    'duplicate',
    'gap',
    'reversed',
    'fractional time',
    'bad pass',
  ]) {
    test('rejects $invalid provider response', () async {
      final repo = SatelliteRepository(
        apiKey: 'private-key',
        clock: () => at(1000000),
        client: MockClient((request) async {
          final id = int.parse(request.url.pathSegments[4]);
          final info = invalid == 'missing id'
              ? <String, Object>{}
              : {'satid': invalid == 'wrong id' ? 1 : id};
          if (request.url.path.contains('visualpasses')) {
            return http.Response(
              jsonEncode({
                'info': info,
                'passes': [
                  {
                    'startUTC': 1000,
                    'endUTC': invalid == 'bad pass' ? 999 : 1100,
                    'duration': 100,
                  },
                ],
              }),
              200,
            );
          }
          final times = switch (invalid) {
            'stale' => [900, 901],
            'future' => [1100, 1101],
            'duplicate' => [1000, 1000],
            'gap' => [1000, 1002],
            'reversed' => [1001, 1000],
            'fractional time' => [1000.5, 1001.5],
            _ => [1000, 1001],
          };
          return http.Response(
            jsonEncode({
              'info': info,
              'positions': [
                for (final time in times)
                  {'timestamp': time, 'azimuth': 10, 'elevation': 30},
              ],
            }),
            200,
          );
        }),
      );
      await expectLater(repo.load(40, -74, 20), throwsFormatException);
      repo.close();
    });
  }

  test(
    'valid current coverage with no optical passes remains valid data',
    () async {
      final repo = SatelliteRepository(
        apiKey: 'test',
        clock: () => at(1000500),
        client: MockClient((request) async {
          final data = <String, Object>{
            'info': {'satid': int.parse(request.url.pathSegments[4])},
          };
          if (request.url.path.contains('visualpasses')) {
            data['passes'] = [];
          } else {
            data['positions'] = [
              for (var s = 1000; s <= 1002; s++)
                {'timestamp': s, 'azimuth': 10, 'elevation': 30},
            ];
          }
          return http.Response(jsonEncode(data), 200);
        }),
      );
      final tracks = await repo.load(40, -74, 20);
      expect(tracks, hasLength(2));
      for (final track in tracks) {
        expect(track.positionAt(at(1000500)), isNotNull);
        expect(track.visibleAt(at(1000500)), isNull);
      }
      repo.close();
    },
  );
}
