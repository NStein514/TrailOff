import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

double distanceBetweenPoints(HikePoint start, HikePoint end) {
  const earthRadiusMeters = 6371000.0;
  final latitudeDelta = _degreesToRadians(end.latitude - start.latitude);
  final longitudeDelta = _degreesToRadians(end.longitude - start.longitude);
  final startLatitude = _degreesToRadians(start.latitude);
  final endLatitude = _degreesToRadians(end.latitude);
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(startLatitude) *
          math.cos(endLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;

class HikePoint {
  const HikePoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestamp,
    this.accuracy = 0,
  });

  final double latitude;
  final double longitude;
  final double altitude;
  final DateTime timestamp;
  final double accuracy;

  factory HikePoint.fromPosition(Position position) => HikePoint(
    latitude: position.latitude,
    longitude: position.longitude,
    altitude: position.altitude,
    timestamp: position.timestamp,
    accuracy: position.accuracy,
  );

  Map<String, Object> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'timestamp': timestamp.toIso8601String(),
    'accuracy': accuracy,
  };

  factory HikePoint.fromJson(Map<String, dynamic> json) => HikePoint(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    altitude: (json['altitude'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
  );
}

String gpxFileName(DateTime startedAt) {
  final timestamp = startedAt.toUtc().toIso8601String().replaceAll(':', '-');
  return 'trailoff-hike-$timestamp.gpx';
}

String toGpx(SavedHike hike, {String name = 'TrailOff hike'}) {
  final safeName = _escapeXml(name);
  final trackPoints = hike.points
      .map((point) {
        final latitude = point.latitude.toStringAsFixed(7);
        final longitude = point.longitude.toStringAsFixed(7);
        final elevation = point.altitude.toStringAsFixed(1);
        final timestamp = point.timestamp.toUtc().toIso8601String();
        return '    <trkpt lat="$latitude" lon="$longitude">'
            '<ele>$elevation</ele><time>$timestamp</time></trkpt>';
      })
      .join('\n');

  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TrailOff" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata><time>${hike.startedAt.toUtc().toIso8601String()}</time></metadata>
  <trk>
    <name>$safeName</name>
    <type>hiking</type>
    <trkseg>
$trackPoints
    </trkseg>
  </trk>
</gpx>''';
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

class SavedHike {
  const SavedHike({
    required this.startedAt,
    required this.finishedAt,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.points,
    this.plannedTrailId,
    this.plannedTrailName,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final List<HikePoint> points;

  /// The trail the hiker planned before setting off, when there was one.
  /// Hikes saved before planning existed simply have no trail.
  final String? plannedTrailId;
  final String? plannedTrailName;

  Map<String, Object> toJson() => {
    'plannedTrailId': ?plannedTrailId,
    'plannedTrailName': ?plannedTrailName,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
    'durationSeconds': durationSeconds,
    'distanceMeters': distanceMeters,
    'elevationGainMeters': elevationGainMeters,
    'points': points.map((point) => point.toJson()).toList(),
  };

  factory SavedHike.fromJson(Map<String, dynamic> json) => SavedHike(
    startedAt: DateTime.parse(json['startedAt'] as String),
    finishedAt: DateTime.parse(json['finishedAt'] as String),
    durationSeconds: json['durationSeconds'] as int,
    distanceMeters: (json['distanceMeters'] as num).toDouble(),
    elevationGainMeters: (json['elevationGainMeters'] as num).toDouble(),
    points: (json['points'] as List<dynamic>)
        .map((point) => HikePoint.fromJson(point as Map<String, dynamic>))
        .toList(),
    plannedTrailId: json['plannedTrailId'] as String?,
    plannedTrailName: json['plannedTrailName'] as String?,
  );
}

abstract interface class HikeLocationSource {
  Future<void> prepare();
  Stream<HikePoint> get positions;
}

class GeolocatorHikeLocationSource implements HikeLocationSource {
  @override
  Future<void> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const HikeLocationException(
        'Turn on location services to record a hike.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const HikeLocationException(
        'Location permission is needed to record your route.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const HikeLocationException(
        'Location access is blocked. Enable it in your device settings.',
      );
    }
  }

  @override
  Stream<HikePoint> get positions => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).map(HikePoint.fromPosition);
}

class HikeLocationException implements Exception {
  const HikeLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class HikeHistoryStore {
  Future<List<SavedHike>> load();
  Future<void> save(SavedHike hike);
}

class SharedPreferencesHikeHistoryStore implements HikeHistoryStore {
  static const _storageKey = 'trailoff.saved_hikes.v1';

  @override
  Future<List<SavedHike>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_storageKey) ?? const [];
    return stored
        .map(
          (entry) =>
              SavedHike.fromJson(jsonDecode(entry) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  @override
  Future<void> save(SavedHike hike) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_storageKey) ?? <String>[];
    stored.insert(0, jsonEncode(hike.toJson()));
    await preferences.setStringList(_storageKey, stored);
  }
}
