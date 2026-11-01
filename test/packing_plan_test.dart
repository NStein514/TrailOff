import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/packing_checklist.dart';
import 'package:trailoff/route_recommendations.dart';
import 'package:trailoff/trail_catalogue.dart';

Trail _trail(String id) =>
    sampleTrailCatalogue.firstWhere((trail) => trail.id == id);

Future<void> _pumpChecklist(
  WidgetTester tester, {
  required Trail? trail,
  HikingAbility ability = HikingAbility.advanced,
  TrailConditions conditions = TrailConditions.wet,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PackingChecklist(
            ability: ability,
            conditions: conditions,
            trail: trail,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _labels(List<PackingItem> items) =>
    items.map((item) => item.label).toList();

void main() {
  test('water scales with the route and the conditions', () {
    final tour = _trail('tour-du-portillon');
    expect(waterLitresFor(trail: tour, conditions: TrailConditions.wet), 3);
    expect(waterLitresFor(trail: tour, conditions: TrailConditions.hot), 4);
    expect(waterLitresFor(trail: tour, conditions: TrailConditions.snowy), 2.5);

    final short = _trail('bois-pique');
    expect(waterLitresFor(trail: short, conditions: TrailConditions.wet), 1);
  });

  test('a big mountain day adds food, poles and an insulating layer', () {
    final items = packingChecklistFor(
      ability: HikingAbility.advanced,
      conditions: TrailConditions.wet,
      trail: _trail('tour-du-portillon'),
    );
    expect(
      _labels(items),
      containsAll(<String>[
        'Extra food',
        'Trekking poles',
        'Insulating layer',
        'Waterproof shell',
      ]),
    );
    expect(items.first.reason, 'About 3 L for 5 h 30 on the trail');
    expect(
      items.firstWhere((item) => item.id == 'extra-food').reason,
      '12.4 km and +1120 m needs more than a snack',
    );
  });

  test('a short forest walk keeps the list lean', () {
    final items = packingChecklistFor(
      ability: HikingAbility.beginner,
      conditions: TrailConditions.dry,
      trail: _trail('bois-pique'),
    );
    expect(_labels(items), isNot(contains('Extra food')));
    expect(_labels(items), isNot(contains('Trekking poles')));
    expect(_labels(items), isNot(contains('Insulating layer')));
    expect(items.first.reason, 'About 1 L for 1 h on the trail');
  });

  test('without a plan the list falls back to ability and conditions', () {
    final items = packingChecklistFor(
      ability: HikingAbility.beginner,
      conditions: TrailConditions.hot,
    );
    expect(items.first.reason, 'At least 1.5 L for a shorter hike');
    expect(_labels(items), isNot(contains('Extra food')));
    expect(_labels(items), containsAll(['Extra water', 'Sun protection']));
  });

  testWidgets('the checklist names the route it was built for', (
    WidgetTester tester,
  ) async {
    await _pumpChecklist(tester, trail: _trail('tour-du-portillon'));

    expect(
      find.text('Tailored to Lac du Portillon loop · 12.4 km · +1120 m'),
      findsOneWidget,
    );
    expect(find.text('About 3 L for 5 h 30 on the trail'), findsOneWidget);
    expect(find.text('Extra food'), findsOneWidget);
    expect(find.text('Trekking poles'), findsOneWidget);
    expect(find.text('Insulating layer'), findsOneWidget);
    expect(find.text('0/8'), findsOneWidget);

    await tester.tap(find.byKey(const Key('packing-water')));
    await tester.pumpAndSettle();
    expect(find.text('1/8'), findsOneWidget);
  });

  testWidgets('switching the plan resets what is already packed', (
    WidgetTester tester,
  ) async {
    await _pumpChecklist(tester, trail: _trail('tour-du-portillon'));
    await tester.tap(find.byKey(const Key('packing-water')));
    await tester.pumpAndSettle();
    expect(find.text('1/8'), findsOneWidget);

    await _pumpChecklist(tester, trail: _trail('bois-pique'));
    expect(
      find.textContaining('Tailored to Bois de la Pique circuit'),
      findsOneWidget,
    );
    expect(find.text('0/5'), findsOneWidget);
    expect(find.text('About 1 L for 1 h on the trail'), findsOneWidget);
  });
}
