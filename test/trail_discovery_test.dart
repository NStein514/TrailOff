import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailoff/main.dart';
import 'package:trailoff/route_recommendations.dart';
import 'package:trailoff/trail_catalogue.dart';
import 'package:trailoff/trail_catalogue_page.dart';
import 'package:trailoff/trail_discovery.dart';
import 'package:trailoff/trail_geometry.dart';
import 'package:trailoff/trail_plan.dart';

Trail _foundTrail({
  String id = 'osm-relation-1',
  double distanceMeters = 6200,
  double ascentMeters = 380,
  bool elevationKnown = true,
}) => Trail(
  id: id,
  name: 'Crêt du Midi loop',
  area: 'GR 5 · OpenStreetMap',
  distanceMeters: distanceMeters,
  ascentMeters: ascentMeters,
  durationMinutes: 130,
  highestPointMeters: 1420,
  elevationKnown: elevationKnown,
  summary: 'A balcony loop above the valley.',
  notes: const ['Mapped in OpenStreetMap.'],
  trailheadLatitude: 45.91,
  trailheadLongitude: 6.86,
  route: const [
    TrailPoint(45.91, 6.86),
    TrailPoint(45.92, 6.87),
    TrailPoint(45.915, 6.875),
    TrailPoint(45.91, 6.86),
  ],
);

Map<String, dynamic> _overpassResponse() => {
  'elements': [
    {
      'type': 'relation',
      'id': 1234,
      'bounds': {
        'minlat': 45.90,
        'minlon': 6.85,
        'maxlat': 45.93,
        'maxlon': 6.88,
      },
      'tags': {
        'route': 'hiking',
        'name': 'Crêt du Midi loop',
        'ref': 'GR 5',
        'sac_scale': 'mountain_hiking',
        'description': 'A balcony loop above the valley.',
      },
      'members': [
        {
          'type': 'way',
          'geometry': [
            {'lat': 45.910, 'lon': 6.860},
            {'lat': 45.920, 'lon': 6.870},
          ],
        },
        {
          'type': 'way',
          'geometry': [
            {'lat': 45.925, 'lon': 6.865},
            {'lat': 45.920, 'lon': 6.870},
          ],
        },
      ],
    },
    {
      'type': 'relation',
      'id': 2,
      'tags': {'route': 'hiking'},
      'members': [
        {
          'type': 'way',
          'geometry': [
            {'lat': 45.0, 'lon': 6.0},
            {'lat': 45.1, 'lon': 6.1},
          ],
        },
      ],
    },
    {
      'type': 'node',
      'id': 3,
      'tags': {'route': 'hiking', 'name': 'A node, not a route'},
    },
    {
      'type': 'relation',
      'id': 4,
      'tags': {'route': 'bus', 'name': 'Bus service'},
    },
    {
      'type': 'relation',
      'id': 5,
      'tags': {'route': 'hiking', 'name': 'A single point'},
      'members': [
        {
          'type': 'way',
          'geometry': [
            {'lat': 45.0, 'lon': 6.0},
          ],
        },
      ],
    },
  ],
};

Map<String, dynamic> _routeStub(int id, double latitude, double longitude) => {
  'type': 'relation',
  'id': id,
  'bounds': {
    'minlat': latitude - 0.01,
    'minlon': longitude - 0.01,
    'maxlat': latitude + 0.01,
    'maxlon': longitude + 0.01,
  },
  'tags': {'route': 'hiking', 'name': 'Route $id'},
};

Map<String, dynamic> _routeGeometry(
  int id,
  double latitude,
  double longitude,
) => {
  'type': 'relation',
  'id': id,
  'tags': {'route': 'hiking', 'name': 'Route $id'},
  'members': [
    {
      'type': 'way',
      'geometry': [
        {'lat': latitude, 'lon': longitude},
        {'lat': latitude + 0.005, 'lon': longitude + 0.005},
        {'lat': latitude + 0.010, 'lon': longitude + 0.008},
        {'lat': latitude, 'lon': longitude},
      ],
    },
  ],
};

class _MemoryPlanStore implements TrailPlanStore {
  String? id;

  @override
  Future<String?> loadPlannedTrailId() async => id;

  @override
  Future<void> plan(String trailId) async => id = trailId;

  @override
  Future<void> clear() async => id = null;
}

class _MemoryDiscoveredTrailStore implements DiscoveredTrailStore {
  final trails = <Trail>[];

  @override
  Future<List<Trail>> load() async => List.unmodifiable(trails);

  @override
  Future<void> remember(Iterable<Trail> found) async {
    trails
      ..clear()
      ..addAll(found);
  }
}

class _FakeDiscoverySource implements TrailDiscoverySource {
  _FakeDiscoverySource(this.matches);

  final List<TrailMatch> matches;
  double? lastRadiusMeters;
  double? lastLatitude;

  @override
  Future<List<TrailMatch>> findNearby({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    lastLatitude = latitude;
    lastRadiusMeters = radiusMeters;
    return matches;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the area search lists hiking relations without fetching geometry', () {
    final query = buildOverpassAreaQuery(
      latitude: 45.9,
      longitude: 6.85,
      radiusMeters: 25000,
    );

    expect(query, contains('relation(around:25000,45.90000,6.85000)'));
    expect(query, contains('hiking|foot'));
    expect(query, contains('out tags bb 60;'));
    expect(query, isNot(contains('geom')));

    expect(
      buildOverpassDetailsQuery([1234, 5678]),
      contains('relation(id:1234,5678);out geom;'),
    );
  });

  test('stub parsing keeps named routes and their bounding box centre', () {
    final stubs = parseRouteStubs(_overpassResponse());

    expect(stubs, hasLength(1));
    expect(stubs.single.id, 1234);
    expect(stubs.single.name, 'Crêt du Midi loop');
    expect(stubs.single.latitude, closeTo(45.915, 1e-9));
    expect(stubs.single.longitude, closeTo(6.865, 1e-9));
  });

  test('only named hiking relations with a drawable line survive', () {
    final routes = parseOverpassRoutes(_overpassResponse());

    expect(routes, hasLength(1));
    final route = routes.single;
    expect(route.osmId, 1234);
    expect(route.name, 'Crêt du Midi loop');
    expect(route.reference, 'GR 5');
    expect(route.sacScale, 'mountain_hiking');
    // The shared joint node is not repeated when ways are stitched.
    expect(route.points, hasLength(3));
    expect(route.lengthMeters, greaterThan(2000));
  });

  test('a way that runs backwards is reversed and joined once', () {
    final points = stitchWayMembers([
      {
        'type': 'way',
        'geometry': [
          {'lat': 45.0, 'lon': 6.0},
          {'lat': 45.01, 'lon': 6.0},
        ],
      },
      {
        'type': 'way',
        'geometry': [
          {'lat': 45.02, 'lon': 6.0},
          {'lat': 45.01, 'lon': 6.0},
        ],
      },
    ]);

    expect(points, hasLength(3));
    expect(points[1].latitude, 45.01);
    expect(points.last.latitude, 45.02);
  });

  test('elevation samples give ascent and high point, ignoring noise', () {
    final profile = elevationProfile([100, 130, 129, 160, 159]);

    expect(profile.ascent, closeTo(61, 0.001));
    expect(profile.highestPoint, 160);
    expect(elevationProfile(const []).ascent, 0);
  });

  test('walking time combines distance with climbing', () {
    expect(estimatedDurationMinutes(4000, 0), 60);
    expect(estimatedDurationMinutes(4000, 600), 120);
    expect(estimatedDurationMinutes(10, 0), 10);
  });

  test('a search rings outward, keeps the nearest routes and batches '
      'elevations', () async {
    final queries = <String>[];
    final elevationRequests = <Uri>[];
    final client = MockClient((request) async {
      if (request.url.host == 'api.open-meteo.com') {
        elevationRequests.add(request.url);
        final coordinates = Uri.splitQueryString(
          request.url.query,
        )['latitude']!.split(',').length;
        return http.Response(
          jsonEncode({
            'elevation': [
              for (var i = 0; i < coordinates; i++) 1000.0 + i * 10,
            ],
          }),
          200,
        );
      }
      final query = Uri.splitQueryString(request.body)['data']!;
      queries.add(query);
      if (query.contains('around:5000')) {
        return http.Response(
          jsonEncode({
            'elements': [_routeStub(1, 45.900, 6.860), _routeStub(2, 46.5, 7.5)],
          }),
          200,
        );
      }
      if (query.contains('around:15000')) {
        return http.Response(
          jsonEncode({
            'elements': [_routeStub(3, 45.910, 6.870)],
          }),
          200,
        );
      }
      if (query.contains('relation(id:')) {
        return http.Response(
          jsonEncode({
            'elements': [
              _routeGeometry(1, 45.900, 6.860),
              _routeGeometry(2, 46.5, 7.5),
              _routeGeometry(3, 45.910, 6.870),
            ],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'elements': []}), 200);
    });

    final matches = await OpenStreetMapTrailSource(
      client: client,
    ).findNearby(latitude: 45.9, longitude: 6.86, radiusMeters: 25000);

    // All three rings were asked for because the first two were thin.
    expect(queries.where((query) => query.contains('around:')), hasLength(3));
    expect(
      queries.where((query) => query.contains('relation(id:')),
      hasLength(1),
    );
    expect(matches, hasLength(3));
    // Nearest trailhead first, not the order the area query listed them.
    expect(matches.first.trail.id, 'osm-relation-1');
    expect(matches.last.trail.id, 'osm-relation-2');
    // Three routes fit in one elevation request, well under the service limit.
    expect(elevationRequests, hasLength(1));
    // Four geometry points per route, three routes in one request.
    expect(
      Uri.splitQueryString(
        elevationRequests.single.query,
      )['latitude']!.split(','),
      hasLength(12),
    );
    expect(matches.first.trail.elevationKnown, isTrue);
    expect(matches.first.trail.ascentMeters, closeTo(30, 1));
    expect(matches.first.trail.highestPointMeters, 1030);
  });

  test('a trail survives a round trip through the disk format', () {
    final trail = Trail.fromJson(
      jsonDecode(jsonEncode(_foundTrail(elevationKnown: false).toJson()))
          as Map<String, dynamic>,
    );

    expect(trail.id, 'osm-relation-1');
    expect(trail.name, 'Crêt du Midi loop');
    expect(trail.elevationKnown, isFalse);
    expect(trail.ascentLabel, '—');
    expect(trail.route, hasLength(4));
    expect(trail.route.first.latitude, 45.91);
    expect(trail.trailheadLongitude, 6.86);
  });

  test('found trails are remembered ahead of what was already stored', () async {
    final store = SharedPreferencesDiscoveredTrailStore();
    await store.remember([_foundTrail(id: 'osm-relation-1')]);
    await store.remember([
      _foundTrail(id: 'osm-relation-2'),
      _foundTrail(id: 'osm-relation-1'),
    ]);

    final trails = await store.load();
    expect(trails.map((trail) => trail.id), [
      'osm-relation-2',
      'osm-relation-1',
    ]);
  });

  test('an unknown ascent does not make a route look flat or fatal', () {
    const ability = HikingAbility.beginner;
    const conditions = TrailConditions.dry;
    final shortWithUnknownAscent = _foundTrail(
      distanceMeters: 4000,
      ascentMeters: 5000,
      elevationKnown: false,
    );
    final shortWithKnownAscent = _foundTrail(
      distanceMeters: 4000,
      ascentMeters: 5000,
    );

    expect(
      trailFit(
        trail: shortWithUnknownAscent,
        ability: ability,
        conditions: conditions,
      ),
      TrailFit.comfortable,
    );
    expect(
      trailFit(
        trail: shortWithKnownAscent,
        ability: ability,
        conditions: conditions,
      ),
      TrailFit.tooDemanding,
    );
  });

  testWidgets('discovery lists trails near the hiker and can plan one', (
    WidgetTester tester,
  ) async {
    final planStore = _MemoryPlanStore();
    final discoveredStore = _MemoryDiscoveredTrailStore();
    final source = _FakeDiscoverySource([
      TrailMatch(
        trail: _foundTrail(),
        distanceFromUserMeters: 2500,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: TrailCataloguePage(
          planStore: planStore,
          discoverySource: source,
          discoveredTrailStore: discoveredStore,
          searchLocation: const TrailSearchLocation(45.9, 6.85),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Routes near Luchon'), findsOneWidget);

    await tester.tap(find.byKey(const Key('find-trails-nearby')));
    await tester.pumpAndSettle();

    expect(source.lastLatitude, 45.9);
    expect(source.lastRadiusMeters, 25000);
    expect(find.text('Trails near you'), findsOneWidget);
    expect(find.textContaining('2.5 km away'), findsOneWidget);
    expect(
      find.text('1 route within 25 km, from OpenStreetMap.'),
      findsOneWidget,
    );
    expect(discoveredStore.trails.single.id, 'osm-relation-1');

    await tester.tap(find.byKey(const Key('trail-osm-relation-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-trail')));
    await tester.pumpAndSettle();

    expect(planStore.id, 'osm-relation-1');
    expect(find.text('PLANNED ROUTE'), findsOneWidget);
  });

  testWidgets('a plan made from a found trail resolves on the dashboard', (
    WidgetTester tester,
  ) async {
    final planStore = _MemoryPlanStore()..id = 'osm-relation-1';
    final discoveredStore = _MemoryDiscoveredTrailStore()
      ..trails.add(_foundTrail());

    await tester.pumpWidget(
      TrailOffApp(
        trailPlanStore: planStore,
        discoveredTrailStore: discoveredStore,
        offlineMapSupported: false,
        nativeMapSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crêt du Midi loop'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('GR 5 · OpenStreetMap'),
      200,
    );
    expect(find.text('GR 5 · OpenStreetMap'), findsOneWidget);
  });

  testWidgets('a trail found and planned from the dashboard survives the trip '
      'back', (WidgetTester tester) async {
    // The app uses its own stores here, as it does when running, so the test
    // sees whether the dashboard and the catalogue agree on where trails go.
    final planStore = _MemoryPlanStore();
    final source = _FakeDiscoverySource([
      TrailMatch(trail: _foundTrail(), distanceFromUserMeters: 2500),
    ]);

    await tester.pumpWidget(
      TrailOffApp(
        trailPlanStore: planStore,
        trailDiscoverySource: source,
        trailSearchLocation: const TrailSearchLocation(45.9, 6.85),
        offlineMapSupported: false,
        nativeMapSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discover trails'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('find-trails-nearby')));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('trailoff.discovered_trails.v1'),
      hasLength(1),
    );

    await tester.tap(find.byKey(const Key('trail-osm-relation-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-trail')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The dashboard reloads the found trails, so the plan made from one still
    // has a name, a fit and a line instead of vanishing.
    expect(planStore.id, 'osm-relation-1');
    await tester.scrollUntilVisible(find.text('GR 5 · OpenStreetMap'), 200);
    expect(find.text('Crêt du Midi loop'), findsWidgets);
  });

  testWidgets('a failed search says so and keeps the sample routes', (
    WidgetTester tester,
  ) async {
    final source = _FailingDiscoverySource();

    await tester.pumpWidget(
      MaterialApp(
        home: TrailCataloguePage(
          discoverySource: source,
          searchLocation: const TrailSearchLocation(48.85, 2.35),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('find-trails-nearby')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('could not reach OpenStreetMap'),
      findsOneWidget,
    );
    expect(find.text('Routes near Luchon'), findsOneWidget);
    expect(find.text('PLANNED ROUTE'), findsNothing);
  });
}

class _FailingDiscoverySource implements TrailDiscoverySource {
  @override
  Future<List<TrailMatch>> findNearby({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    throw const TrailDiscoveryException(
      'Trail search could not reach OpenStreetMap. Check your connection.',
    );
  }
}
