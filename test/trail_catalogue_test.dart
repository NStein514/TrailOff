import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/route_recommendations.dart';
import 'package:trailoff/trail_catalogue.dart';
import 'package:trailoff/trail_catalogue_page.dart';

Trail _trail(String id) =>
    sampleTrailCatalogue.firstWhere((trail) => trail.id == id);

void main() {
  test('fit compares distance and ascent with ability and conditions', () {
    final loop = _trail('portillon-loop');
    final forest = _trail('bois-pique');
    final falls = _trail('imperatrice-falls');

    expect(
      trailFit(
        trail: forest,
        ability: HikingAbility.beginner,
        conditions: TrailConditions.dry,
      ),
      TrailFit.comfortable,
    );
    expect(
      trailFit(
        trail: falls,
        ability: HikingAbility.beginner,
        conditions: TrailConditions.dry,
      ),
      TrailFit.comfortable,
    );
    expect(
      trailFit(
        trail: loop,
        ability: HikingAbility.beginner,
        conditions: TrailConditions.dry,
      ),
      TrailFit.tooDemanding,
    );
    expect(
      trailFit(
        trail: loop,
        ability: HikingAbility.advanced,
        conditions: TrailConditions.dry,
      ),
      TrailFit.comfortable,
    );
  });

  test('worse conditions tighten the same route', () {
    final forest = _trail('bois-pique');
    expect(
      trailFit(
        trail: forest,
        ability: HikingAbility.beginner,
        conditions: TrailConditions.snowy,
      ),
      TrailFit.stretch,
    );
    expect(
      trailLoad(
        trail: forest,
        ability: HikingAbility.beginner,
        conditions: TrailConditions.snowy,
      ),
      greaterThan(
        trailLoad(
          trail: forest,
          ability: HikingAbility.beginner,
          conditions: TrailConditions.dry,
        ),
      ),
    );
  });

  test('suggestions put suitable routes first and easiest first', () {
    final suggestions = suggestTrails(
      trails: sampleTrailCatalogue,
      ability: HikingAbility.beginner,
      conditions: TrailConditions.dry,
    );

    expect(suggestions, hasLength(sampleTrailCatalogue.length));
    expect(suggestions.first.trail.id, 'bois-pique');
    expect(suggestions.first.fit, TrailFit.comfortable);
    expect(suggestions[1].trail.id, 'imperatrice-falls');
    expect(suggestions.last.fit, TrailFit.tooDemanding);

    final fits = suggestions.map((suggestion) => suggestion.fit.index).toList();
    expect(fits, orderedEquals(List<int>.of(fits)..sort()));
  });

  testWidgets('catalogue re-ranks trails when ability changes', (
    WidgetTester tester,
  ) async {
    Finder badgeIn(String id, String label) => find.descendant(
      of: find.byKey(Key('trail-$id')),
      matching: find.text(label),
    );

    await tester.pumpWidget(const MaterialApp(home: TrailCataloguePage()));
    await tester.pumpAndSettle();

    expect(
      find.text('2 of 6 routes fit your level in dry conditions.'),
      findsOneWidget,
    );
    expect(badgeIn('bois-pique', 'Fits today'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('trail-portillon-loop')),
      240,
    );
    expect(badgeIn('portillon-loop', 'Too demanding today'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('catalogue-ability')),
      -240,
    );
    await tester.tap(find.byKey(const Key('catalogue-ability')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced').last);
    await tester.pumpAndSettle();

    expect(
      find.text('6 of 6 routes fit your level in dry conditions.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('trail-portillon-loop')),
      240,
    );
    expect(badgeIn('portillon-loop', 'Fits today'), findsOneWidget);
    expect(badgeIn('portillon-loop', 'Too demanding today'), findsNothing);
  });

  testWidgets('trail details explain the fit and show route notes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TrailCataloguePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trail-bois-pique')));
    await tester.pumpAndSettle();
    expect(find.text('GOOD TO KNOW'), findsOneWidget);
    expect(
      find.text('Well marked and easy to follow in any weather.'),
      findsOneWidget,
    );
    expect(find.text('1 h'), findsOneWidget);
    expect(
      find.text('Well inside your range for these conditions.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('GOOD TO KNOW'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('trail-portillon-loop')),
      240,
    );
    await tester.ensureVisible(find.byKey(const Key('trail-portillon-loop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trail-portillon-loop')));
    await tester.pumpAndSettle();
    expect(find.text('GOOD TO KNOW'), findsOneWidget);
    expect(find.text('Lac du Portillon loop'), findsNWidgets(2));
    expect(
      find.textContaining('Beyond your range for these conditions.'),
      findsOneWidget,
    );
    expect(
      find.text('Snowfields linger into June on the upper section.'),
      findsOneWidget,
    );
  });
}
