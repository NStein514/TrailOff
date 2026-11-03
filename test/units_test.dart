import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailoff/main.dart';
import 'package:trailoff/trail_catalogue.dart';
import 'package:trailoff/trail_catalogue_page.dart';
import 'package:trailoff/trail_plan.dart';
import 'package:trailoff/units.dart';

class _MemoryUnitStore implements UnitPreferenceStore {
  MeasurementSystem system = MeasurementSystem.metric;
  int saves = 0;

  @override
  Future<MeasurementSystem> load() async => system;

  @override
  Future<void> save(MeasurementSystem system) async {
    this.system = system;
    saves++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('units format', () {
    test('distances follow the system', () {
      expect(Units.metric.distance(3200), '3.2 km');
      expect(Units.imperial.distance(3200), '2.0 mi');
      expect(Units.imperial.distance(1609.344, decimals: 2), '1.00 mi');
      expect(Units.metric.distance(12000, decimals: 2), '12.00 km');
    });

    test('short distances use metres, feet or miles', () {
      expect(Units.metric.shortDistance(482), '480 m');
      expect(Units.metric.shortDistance(2400), '2.4 km');
      expect(Units.imperial.shortDistance(482), '0.3 mi');
      expect(Units.imperial.shortDistance(82), '269 ft');
    });

    test('heights are grouped and converted', () {
      expect(Units.metric.ascent(1120), '+1,120 m');
      expect(Units.metric.height(1056), '1,056 m');
      expect(Units.imperial.ascent(1120), '+3,675 ft');
      expect(Units.imperial.height(1056), '3,465 ft');
      expect(Units.metric.ascent(380), '+380 m');
    });

    test('speed and accuracy follow the system', () {
      expect(Units.metric.speed(1), '3.6 km/h');
      expect(Units.imperial.speed(1), '2.2 mph');
      expect(Units.metric.accuracy(12), '12 m');
      expect(Units.imperial.accuracy(12), '39 ft');
    });

    test('radius presets are labelled and converted', () {
      expect(Units.metric.radiusLabel(25), '25 km');
      expect(Units.imperial.radiusLabel(25), '25 mi');
      expect(Units.metric.radiusMeters(25), 25000);
      expect(Units.imperial.radiusMeters(25), closeTo(40233.6, 0.1));
      expect(Units.imperial.radiusLabel(10), '10 mi');
      expect(Units.metric.radiusLabel(10), '10 km');
    });

    test('a trail reports its figures in the chosen units', () {
      const trail = Trail(
        id: 't',
        name: 'Test trail',
        area: 'Anywhere',
        distanceMeters: 6200,
        ascentMeters: 380,
        durationMinutes: 130,
        highestPointMeters: 1056,
        summary: '',
        notes: [],
        trailheadLatitude: 45,
        trailheadLongitude: 6,
        route: [],
      );

      expect(trail.distanceLabel(), '6.2 km');
      expect(trail.distanceLabel(Units.imperial), '3.9 mi');
      expect(trail.ascentLabel(Units.imperial), '+1,247 ft');
      expect(trail.highPointLabel(Units.imperial), '3,465 ft');
    });
  });

  group('unit preference', () {
    test('metric is the default and imperial survives a round trip', () async {
      final store = SharedPreferencesUnitPreferenceStore();
      expect(await store.load(), MeasurementSystem.metric);

      await store.save(MeasurementSystem.imperial);
      expect(await store.load(), MeasurementSystem.imperial);

      await store.save(MeasurementSystem.metric);
      expect(await store.load(), MeasurementSystem.metric);
    });

    test('a stored value that makes no sense falls back to metric', () async {
      SharedPreferences.setMockInitialValues({
        'trailoff.units.v1': 'furlongs',
      });
      expect(
        await SharedPreferencesUnitPreferenceStore().load(),
        MeasurementSystem.metric,
      );
    });
  });

  testWidgets('the dashboard switches every figure to miles and feet', (
    WidgetTester tester,
  ) async {
    final store = _MemoryUnitStore();
    await tester.pumpWidget(
      TrailOffApp(
        unitPreferenceStore: store,
        offlineMapSupported: false,
        nativeMapSupported: false,
        trailPlanStore: _MemoryPlanStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('units-toggle')), findsOneWidget);
    expect(find.text('km'), findsOneWidget);

    await tester.tap(find.byKey(const Key('units-toggle')));
    await tester.pumpAndSettle();

    expect(store.system, MeasurementSystem.imperial);
    expect(store.saves, 1);
    expect(find.text('mi'), findsOneWidget);

    // The catalogue page reads the same setting.
    await tester.tap(find.text('Discover trails'));
    await tester.pumpAndSettle();
    expect(find.text('Routes near Luchon'), findsOneWidget);
    expect(find.textContaining(' mi'), findsWidgets);
    expect(find.textContaining(' km'), findsNothing);
    expect(find.textContaining(' m '), findsNothing);
  });

  testWidgets('the catalogue uses the units it is given', (tester) async {
    await tester.pumpWidget(
      UnitsScope(
        units: Units.imperial,
        child: const MaterialApp(home: TrailCataloguePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('9.4 mi'), findsNothing);
    expect(find.textContaining(' mi'), findsWidgets);
    expect(find.text('2.0 mi · +394 ft ascent · 1 h'), findsOneWidget);
  });
}

class _MemoryPlanStore implements TrailPlanStore {
  String? id;

  @override
  Future<String?> loadPlannedTrailId() async => id;

  @override
  Future<void> plan(String trailId) async => id = trailId;

  @override
  Future<void> clear() async => id = null;
}
