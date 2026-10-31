import 'dart:convert';
import 'dart:math' as math;
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

  /// Interpolate only between adjacent one-second predictions. Never extend
  /// coverage beyond the provider's timestamps, even after a fresh download.
  SatelliteSample? positionAt(DateTime time) {
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (sample.time == time) return sample;
      if (sample.time.isAfter(time)) {
        if (i == 0) return null;
        final previous = samples[i - 1];
        final gap = sample.time.difference(previous.time).inMilliseconds;
        if (gap != 1000) return null;
        final t = time.difference(previous.time).inMilliseconds / gap;
        final a = previous.direction, b = sample.direction;
        final x = a.east + (b.east - a.east) * t;
        final y = a.north + (b.north - a.north) * t;
        final z = a.up + (b.up - a.up) * t;
        final length = math.sqrt(x * x + y * y + z * z);
        if (length < 0.001) return null;
        return SatelliteSample(
          sample.name,
          time,
          SkyVector(x / length, y / length, z / length),
        );
      }
    }
    return null;
  }

  SatelliteSample? visibleAt(DateTime time) {
    final milliseconds = time.millisecondsSinceEpoch;
    if (!passes.any(
      (p) => milliseconds >= p.$1 * 1000 && milliseconds <= p.$2 * 1000,
    )) {
      return null;
    }
    final sample = positionAt(time);
    return sample != null && sample.direction.up > 0 ? sample : null;
  }
}

/// Positions plus optical passes, not ground tracks or sensor-based recognition.
/// A personal key can be supplied at build time. Never log credential-bearing URLs.
class SatelliteRepository {
  SatelliteRepository({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('N2YO_API_KEY'),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _clock;
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
      final requestedAt = _clock().toUtc();
      final results = await Future.wait([
        _get('positions/${entry.key}/$observer/300'),
        _get('visualpasses/${entry.key}/$observer/1/1'),
      ]);
      if (results.any(
        (result) =>
            result['info'] is! Map || result['info']['satid'] != entry.key,
      )) {
        throw const FormatException('Satellite identity mismatch');
      }
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
            _integer(row['timestamp']) * 1000,
            isUtc: true,
          ),
          SkyVector.horizontal(az, el),
        );
      }).toList();
      if (samples.isEmpty) throw const FormatException('Missing positions');
      if (samples.first.time.difference(requestedAt).inMilliseconds.abs() >
              30000 ||
          samples.first.time.isAfter(_clock().toUtc()) ||
          samples.last.time.isBefore(_clock().toUtc())) {
        throw const FormatException('Satellite positions are not current');
      }
      for (var i = 1; i < samples.length; i++) {
        if (samples[i].time.difference(samples[i - 1].time).inSeconds != 1) {
          throw const FormatException('Invalid position sequence');
        }
      }
      final passes = <(int, int)>[];
      for (final row in results[1]['passes'] as List) {
        final start = _integer(row['startUTC']);
        final end = _integer(row['endUTC']);
        final duration = _integer(row['duration']);
        if (end <= start || duration < 0) {
          throw const FormatException('Invalid visibility interval');
        }
        // N2YO may return passes only partially illuminated without the exact
        // illuminated subinterval. Do not claim visibility over that whole pass.
        if (end >= start && duration >= end - start) passes.add((start, end));
      }
      tracks.add(SatelliteTrack(samples, passes));
    }
    return tracks;
  }
}

int _integer(dynamic value) {
  if (value is! num || !value.isFinite || value != value.truncateToDouble()) {
    throw const FormatException('Expected an integer');
  }
  return value.toInt();
}
