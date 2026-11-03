import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'hike_navigation.dart';
import 'trail_catalogue.dart';
import 'trail_geometry.dart';

/// Where the hiker is standing when they ask for nearby routes. The app reads
/// it from the platform location plugin; tests pass a fixed point.
class TrailSearchLocation {
  const TrailSearchLocation(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// A route found near the hiker, with how far its trailhead is from them.
class TrailMatch {
  const TrailMatch({
    required this.trail,
    required this.distanceFromUserMeters,
  });

  final Trail trail;
  final double distanceFromUserMeters;

  String get distanceLabel {
    if (distanceFromUserMeters < 1000) {
      return '${distanceFromUserMeters.round()} m away';
    }
    return '${(distanceFromUserMeters / 1000).toStringAsFixed(1)} km away';
  }
}

class TrailDiscoveryException implements Exception {
  const TrailDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Finds hiking routes around a point. The live implementation reads
/// OpenStreetMap, so discovery is not tied to the bundled sample region.
abstract interface class TrailDiscoverySource {
  Future<List<TrailMatch>> findNearby({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  });
}

/// Remembers trails found online, because a plan stores only a trail id and the
/// dashboard has to resolve it again after a restart.
abstract interface class DiscoveredTrailStore {
  Future<List<Trail>> load();
  Future<void> remember(Iterable<Trail> trails);
}

class SharedPreferencesDiscoveredTrailStore implements DiscoveredTrailStore {
  static const _storageKey = 'trailoff.discovered_trails.v1';
  static const _maxTrails = 200;

  @override
  Future<List<Trail>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_storageKey) ?? const [];
    final trails = <Trail>[];
    for (final entry in stored) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          trails.add(Trail.fromJson(decoded));
        }
      } catch (_) {
        // One unreadable entry must not hide the other saved trails.
      }
    }
    return trails;
  }

  @override
  Future<void> remember(Iterable<Trail> trails) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_storageKey) ?? <String>[];
    final seen = <String>{};
    final merged = <String>[];
    for (final trail in trails) {
      if (seen.add(trail.id)) merged.add(jsonEncode(trail.toJson()));
    }
    for (final entry in stored) {
      try {
        final decoded = jsonDecode(entry);
        final id = decoded is Map<String, dynamic> ? decoded['id'] : null;
        if (id is! String || !seen.add(id)) continue;
        merged.add(entry);
      } catch (_) {
        // Skip entries that no longer parse.
      }
    }
    await preferences.setStringList(
      _storageKey,
      merged.take(_maxTrails).toList(),
    );
  }
}

/// A route a search found, with just enough information to pick the nearest
/// ones before their geometry is requested.
class OsmRouteStub {
  const OsmRouteStub({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final int id;
  final String name;

  /// Centre of the route's bounding box, used only to choose what to fetch.
  final double latitude;
  final double longitude;
}

/// A hiking route relation read from OpenStreetMap, before elevation is added.
class ParsedHikingRoute {
  const ParsedHikingRoute({
    required this.osmId,
    required this.name,
    required this.lengthMeters,
    required this.points,
    this.reference,
    this.description,
    this.sacScale,
  });

  final int osmId;
  final String name;
  final double lengthMeters;
  final List<TrailPoint> points;
  final String? reference;
  final String? description;
  final String? sacScale;
}

/// Finds named hiking routes near a point through the OpenStreetMap Overpass
/// API, then estimates their ascent from a sampled elevation model.
class OpenStreetMapTrailSource implements TrailDiscoverySource {
  OpenStreetMapTrailSource({http.Client? client})
    : _client = client ?? http.Client();

  /// Public Overpass instances, tried in order. The busiest one rejects
  /// queries outright when its queue is full, so a second chance keeps
  /// discovery working.
  static const overpassEndpoints = [
    'https://overpass.openstreetmap.fr/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  static const elevationEndpoint = 'https://api.open-meteo.com/v1/elevation';

  /// Identifies the app to the shared Overpass instance, as its usage policy
  /// asks. A production build should query its own cached copy instead.
  static const _userAgent = 'TrailOff/1.0 (Flutter hiking app)';
  static const _maxRoutes = 12;

  /// Samples per route, and routes per elevation request. The elevation service
  /// accepts up to 100 coordinates per call and rate-limits rapid bursts, so
  /// grouping routes keeps a search to a handful of requests.
  static const _elevationSamples = 30;
  static const _routesPerElevationRequest = 3;

  final http.Client _client;

  @override
  Future<List<TrailMatch>> findNearby({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final stubs = await _search(latitude, longitude, radiusMeters);
    if (stubs.isEmpty) return const [];

    // The area search is ordered by id, so the nearest routes are chosen here
    // and only those have their geometry and elevation requested.
    final nearest = stubs
        .map(
          (stub) => (
            stub: stub,
            distance: distanceMetersBetween(
              latitude,
              longitude,
              stub.latitude,
              stub.longitude,
            ),
          ),
        )
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));

    final routes = await _routeDetails([
      for (final entry in nearest.take(_maxRoutes)) entry.stub.id,
    ]);
    final profiles = await _elevationProfiles(routes);

    final matches = <TrailMatch>[];
    for (final route in routes) {
      matches.add(
        TrailMatch(
          trail: _trailFrom(route, profiles[route.osmId]),
          distanceFromUserMeters: distanceMetersBetween(
            latitude,
            longitude,
            route.points.first.latitude,
            route.points.first.longitude,
          ),
        ),
      );
    }
    matches.sort(
      (a, b) => a.distanceFromUserMeters.compareTo(b.distanceFromUserMeters),
    );
    return matches;
  }

  /// Searches in expanding rings and stops as soon as there are enough
  /// candidates, so the routes offered are the ones around the hiker rather
  /// than whatever a single wide query happened to list first.
  Future<List<OsmRouteStub>> _search(
    double latitude,
    double longitude,
    double radiusMeters,
  ) async {
    final steps = <double>{
      math.min(radiusMeters, 5000),
      math.min(radiusMeters, 15000),
      radiusMeters,
    }.toList()..sort();
    final stubs = <int, OsmRouteStub>{};
    for (final step in steps) {
      final json = await _query(
        buildOverpassAreaQuery(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: step,
        ),
      );
      for (final stub in parseRouteStubs(json)) {
        stubs[stub.id] = stub;
      }
      if (stubs.length >= _maxRoutes) break;
    }
    return stubs.values.toList();
  }

  Future<List<ParsedHikingRoute>> _routeDetails(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final json = await _query(buildOverpassDetailsQuery(ids));
    return parseOverpassRoutes(json);
  }

  /// Runs one Overpass query, trying each public instance until one answers.
  Future<Map<String, dynamic>> _query(String query) async {
    http.Response? response;
    var reachedServer = false;
    for (final endpoint in overpassEndpoints) {
      try {
        final attempt = await _client
            .post(
              Uri.parse(endpoint),
              headers: {
                'User-Agent': _userAgent,
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 25));
        reachedServer = true;
        if (attempt.statusCode == 200) {
          response = attempt;
          break;
        }
      } catch (_) {
        // Try the next instance: a full queue answers at once, an overloaded
        // one just times out.
      }
    }
    if (response == null) {
      throw TrailDiscoveryException(
        reachedServer
            ? 'OpenStreetMap is busy right now. Try again in a few minutes.'
            : 'Trail search could not reach OpenStreetMap. Check your connection.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const TrailDiscoveryException(
        'OpenStreetMap returned data this app could not read.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TrailDiscoveryException(
        'OpenStreetMap returned data this app could not read.',
      );
    }
    return decoded;
  }

  /// Elevation is optional: when the elevation service is unavailable the route
  /// is still useful, but the app says its ascent is unknown instead of
  /// claiming the route is flat. Routes are grouped so one request covers a
  /// few of them, which keeps a search well under the service's burst limit.
  Future<Map<int, ({double ascent, int highestPoint})>> _elevationProfiles(
    List<ParsedHikingRoute> routes,
  ) async {
    final profiles = <int, ({double ascent, int highestPoint})>{};
    for (
      var start = 0;
      start < routes.length;
      start += _routesPerElevationRequest
    ) {
      final group = routes
          .skip(start)
          .take(_routesPerElevationRequest)
          .toList();
      final samples = [
        for (final route in group) _sample(route.points, _elevationSamples),
      ];
      final latitudes = [
        for (final routeSamples in samples)
          for (final point in routeSamples)
            point.latitude.toStringAsFixed(5),
      ];
      final longitudes = [
        for (final routeSamples in samples)
          for (final point in routeSamples)
            point.longitude.toStringAsFixed(5),
      ];
      final elevations = await _elevations(latitudes, longitudes);
      if (elevations == null) continue;
      var offset = 0;
      for (var i = 0; i < group.length; i++) {
        final count = samples[i].length;
        if (count < 2 || offset + count > elevations.length) {
          offset += count;
          continue;
        }
        profiles[group[i].osmId] = elevationProfile(
          elevations.sublist(offset, offset + count),
        );
        offset += count;
      }
    }
    return profiles;
  }

  Future<List<double>?> _elevations(
    List<String> latitudes,
    List<String> longitudes,
  ) async {
    if (latitudes.isEmpty) return null;
    final uri = Uri.parse(elevationEndpoint).replace(
      queryParameters: {
        'latitude': latitudes.join(','),
        'longitude': longitudes.join(','),
      },
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) return null;
          final values = decoded['elevation'];
          if (values is! List || values.length != latitudes.length) {
            return null;
          }
          return [
            for (final value in values)
              if (value is num) value.toDouble(),
          ];
        }
        if (response.statusCode != 429) return null;
        // Rate limited: wait out the burst and try once more.
        await Future<void>.delayed(const Duration(seconds: 2));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Trail _trailFrom(
    ParsedHikingRoute route,
    ({double ascent, int highestPoint})? profile,
  ) {
    final points = decimateRoute(route.points);
    final ascent = profile?.ascent ?? 0;
    final description = route.description?.trim() ?? '';
    final reference = route.reference?.trim() ?? '';
    return Trail(
      id: 'osm-relation-${route.osmId}',
      name: route.name,
      area: reference.isEmpty ? 'OpenStreetMap' : '$reference · OpenStreetMap',
      distanceMeters: route.lengthMeters,
      ascentMeters: ascent,
      durationMinutes: estimatedDurationMinutes(route.lengthMeters, ascent),
      highestPointMeters: profile?.highestPoint ?? 0,
      elevationKnown: profile != null,
      summary: description.isEmpty
          ? 'A hiking route mapped in OpenStreetMap.'
          : description,
      notes: [
        'Mapped in OpenStreetMap: the line, distance and figures are estimates, '
            'not a surveyed track.',
        if (route.sacScale != null)
          'Hiking difficulty (OSM sac_scale): ${_sacScaleLabel(route.sacScale!)}.',
        if (profile == null)
          'Ascent and high point could not be estimated, so the fit uses '
              'distance only.',
      ],
      trailheadLatitude: points.first.latitude,
      trailheadLongitude: points.first.longitude,
      route: points,
    );
  }
}

/// Overpass query that lists named hiking relations around a point. It asks for
/// tags and bounding boxes only, so a wide radius stays cheap; geometry is
/// fetched afterwards for the nearest routes.
String buildOverpassAreaQuery({
  required double latitude,
  required double longitude,
  required double radiusMeters,
  int maxRoutes = 60,
}) {
  final radius = radiusMeters.round();
  final lat = latitude.toStringAsFixed(5);
  final lon = longitude.toStringAsFixed(5);
  return '[out:json][timeout:25];'
      'relation(around:$radius,$lat,$lon)["route"~"^(hiking|foot)\$"];'
      'out tags bb $maxRoutes;';
}

/// Overpass query returning the tags and member geometry of the chosen routes.
String buildOverpassDetailsQuery(List<int> ids) =>
    '[out:json][timeout:25];relation(id:${ids.join(',')});out geom;';

/// Turns the area response into stubs, skipping anything that is not a named
/// hiking relation with a bounding box.
List<OsmRouteStub> parseRouteStubs(Map<String, dynamic> json) {
  final elements = json['elements'];
  if (elements is! List) return const [];
  final stubs = <OsmRouteStub>[];
  for (final element in elements) {
    if (element is! Map) continue;
    if (element['type'] != 'relation') continue;
    final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final category = tags['route'];
    if (category != 'hiking' && category != 'foot') continue;
    final name = (tags['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    final id = (element['id'] as num?)?.toInt();
    final bounds = (element['bounds'] as Map?)?.cast<String, dynamic>();
    if (id == null || bounds == null) continue;
    final south = (bounds['minlat'] as num?)?.toDouble();
    final north = (bounds['maxlat'] as num?)?.toDouble();
    final west = (bounds['minlon'] as num?)?.toDouble();
    final east = (bounds['maxlon'] as num?)?.toDouble();
    if (south == null || north == null || west == null || east == null) {
      continue;
    }
    stubs.add(
      OsmRouteStub(
        id: id,
        name: name,
        latitude: (south + north) / 2,
        longitude: (west + east) / 2,
      ),
    );
  }
  return stubs;
}

/// Turns a geometry response into routes, skipping anything that is not a named
/// hiking relation with enough geometry to draw.
List<ParsedHikingRoute> parseOverpassRoutes(Map<String, dynamic> json) {
  final elements = json['elements'];
  if (elements is! List) return const [];
  final routes = <ParsedHikingRoute>[];
  for (final element in elements) {
    if (element is! Map) continue;
    if (element['type'] != 'relation') continue;
    final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final category = tags['route'];
    if (category != 'hiking' && category != 'foot') continue;
    final name = (tags['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    final osmId = (element['id'] as num?)?.toInt();
    if (osmId == null) continue;
    final points = stitchWayMembers(element['members']);
    final length = trailLengthMeters(points);
    // Very short relations are fragments of a path, not a walk worth listing.
    if (points.length < 2 || length < 400) continue;
    routes.add(
      ParsedHikingRoute(
        osmId: osmId,
        name: name,
        lengthMeters: length,
        points: points,
        reference: tags['ref'] as String?,
        description: tags['description'] as String?,
        sacScale: tags['sac_scale'] as String?,
      ),
    );
  }
  return routes;
}

/// Concatenates a relation's way members into one line, reversing ways that run
/// against the direction so far and dropping the shared joint node.
List<TrailPoint> stitchWayMembers(Object? members) {
  if (members is! List) return const [];
  final points = <TrailPoint>[];
  for (final member in members) {
    if (member is! Map || member['type'] != 'way') continue;
    final geometry = member['geometry'];
    if (geometry is! List) continue;
    final way = <TrailPoint>[
      for (final node in geometry)
        if (node is Map && node['lat'] is num && node['lon'] is num)
          TrailPoint(
            (node['lat'] as num).toDouble(),
            (node['lon'] as num).toDouble(),
          ),
    ];
    if (way.isEmpty) continue;
    if (points.isEmpty) {
      points.addAll(way);
      continue;
    }
    if (_sameNode(points.last, way.first)) {
      points.addAll(way.skip(1));
    } else if (_sameNode(points.last, way.last)) {
      points.addAll(way.reversed.skip(1));
    } else {
      // A disconnected member: keep it, the line will show the gap.
      points.addAll(way);
    }
  }
  return points;
}

bool _sameNode(TrailPoint a, TrailPoint b) =>
    (a.latitude - b.latitude).abs() < 1e-7 &&
    (a.longitude - b.longitude).abs() < 1e-7;

/// Ascent and high point from sampled elevations. Rises under two metres are
/// treated as sampling noise, so a flat line does not report a climb.
({double ascent, int highestPoint}) elevationProfile(List<double> elevations) {
  if (elevations.isEmpty) return (ascent: 0, highestPoint: 0);
  var ascent = 0.0;
  var highest = elevations.first;
  for (var i = 1; i < elevations.length; i++) {
    final rise = elevations[i] - elevations[i - 1];
    if (rise > 2) ascent += rise;
    if (elevations[i] > highest) highest = elevations[i];
  }
  return (ascent: ascent, highestPoint: highest.round());
}

/// Walking time at 4 km/h plus a minute for every 10 m of climbing (a Naismith
/// style rule of thumb), never less than ten minutes.
int estimatedDurationMinutes(double distanceMeters, double ascentMeters) {
  final total = distanceMeters / 4000 * 60 + ascentMeters / 10;
  return math.max(10, total.round());
}

/// Evenly spaced sample of a route, always keeping the first and last point.
List<TrailPoint> _sample(List<TrailPoint> points, int maximum) {
  if (points.length <= maximum) return points;
  final step = (points.length - 1) / (maximum - 1);
  return [
    for (var i = 0; i < maximum; i++) points[(i * step).round()],
  ];
}

/// Keeps a drawable line without storing thousands of vertices per planned
/// trail. First and last points are always kept so the trailhead is exact.
List<TrailPoint> decimateRoute(List<TrailPoint> points, {int maximum = 400}) =>
    _sample(points, maximum);

String _sacScaleLabel(String value) {
  final words = value.replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Unknown';
  return words[0].toUpperCase() + words.substring(1);
}
