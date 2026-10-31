import 'dart:convert';
import 'package:http/http.dart' as http;
import 'sky_math.dart';

class SatelliteSample {
  const SatelliteSample(this.name, this.time, this.direction);
  final String name;
  final DateTime time;
  final SkyVector direction;
}

class SatelliteTrack {
  SatelliteTrack(this.samples, this.passes);
  final List<SatelliteSample> samples;
  final List<(int, int)> passes;

  SatelliteSample? visibleAt(DateTime time) {
    final seconds = time.millisecondsSinceEpoch ~/ 1000;
    if (!passes.any((p) => seconds >= p.$1 && seconds <= p.$2)) return null;
    // Never extrapolate expired samples or draw a below-horizon object.
    for (final s in samples) {
      if ((s.time.difference(time).inMilliseconds).abs() <= 600 &&
          s.direction.up > 0) {
        return s;
      }
    }
    return null;
  }
}

/// Positions plus optical passes, not ground tracks or sensor-based recognition.
/// A personal key can be supplied at build time. Never log credential-bearing URLs.
class SatelliteRepository {
  SatelliteRepository({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('N2YO_API_KEY'),
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final String apiKey;
  bool get configured => apiKey.isNotEmpty;
  void close() => _client.close();

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse(
      'https://api.n2yo.com/rest/v1/satellite/$path/&apiKey=${Uri.encodeComponent(apiKey)}',
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException('Satellite service unavailable');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw const FormatException('Satellite service rejected request');
    }
    return json;
  }

  Future<List<SatelliteTrack>> load(
    double latitude,
    double longitude,
    double altitude,
  ) async {
    if (!configured) return [];
    final observer = '$latitude/$longitude/$altitude';
    final tracks = <SatelliteTrack>[];
    for (final entry in const {25544: 'ISS', 20580: 'Hubble'}.entries) {
      final results = await Future.wait([
        _get('positions/${entry.key}/$observer/300'),
        _get('visualpasses/${entry.key}/$observer/1/1'),
      ]);
      final samples = (results[0]['positions'] as List).map((row) {
        final az = (row['azimuth'] as num).toDouble();
        final el = (row['elevation'] as num).toDouble();
        if (!az.isFinite ||
            !el.isFinite ||
            az < 0 ||
            az > 360 ||
            el.abs() > 90) {
          throw const FormatException('Invalid satellite coordinates');
        }
        return SatelliteSample(
          entry.value,
          DateTime.fromMillisecondsSinceEpoch(
            (row['timestamp'] as num).toInt() * 1000,
            isUtc: true,
          ),
          SkyVector.horizontal(az, el),
        );
      }).toList();
      if (samples.isEmpty) throw const FormatException('Missing positions');
      final passes = <(int, int)>[];
      for (final row in results[1]['passes'] as List) {
        final start = (row['startUTC'] as num).toInt();
        final end = (row['endUTC'] as num).toInt();
        final duration = (row['duration'] as num).toInt();
        // N2YO may return passes only partially illuminated without the exact
        // illuminated subinterval. Do not claim visibility over that whole pass.
        if (end >= start && duration >= end - start) passes.add((start, end));
      }
      tracks.add(SatelliteTrack(samples, passes));
    }
    return tracks;
  }
}
