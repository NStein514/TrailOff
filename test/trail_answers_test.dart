import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/trail_answers.dart';
import 'package:trailoff/trail_guide.dart';

class _MemoryTrailGuideStore implements TrailGuideStore {
  final guides = <String, TrailGuide>{};

  @override
  Future<TrailGuide?> load(String id) async => guides[id];

  @override
  Future<void> save(TrailGuide guide) async => guides[guide.id] = guide;

  @override
  Future<void> remove(String id) async => guides.remove(id);
}

Future<void> _pumpCard(WidgetTester tester, TrailGuideStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TrailAnswers(store: store)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _askFor(WidgetTester tester, String question) async {
  await tester.enterText(find.byKey(const Key('trail-question')), question);
  await tester.tap(find.byKey(const Key('trail-ask')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('downloads trail info, then answers with a cited quote', (
    WidgetTester tester,
  ) async {
    final store = _MemoryTrailGuideStore();
    await _pumpCard(tester, store);

    expect(find.text('Download trail info'), findsOneWidget);
    expect(find.byKey(const Key('trail-question')), findsNothing);

    await tester.tap(find.text('Download trail info'));
    await tester.pumpAndSettle();
    expect(store.guides.keys, [tourTrailGuide.id]);
    expect(find.textContaining('Saved offline'), findsOneWidget);
    expect(find.text('Download trail info'), findsNothing);

    await _askFor(tester, 'Can I camp at the lake?');
    expect(find.textContaining('single night'), findsOneWidget);
    expect(
      find.text('From Tour du Portillon · Camping & bivouac rules'),
      findsOneWidget,
    );

    await _askFor(tester, 'Are there bears?');
    expect(find.textContaining('does not cover that'), findsOneWidget);
    expect(find.textContaining('single night'), findsNothing);
  });

  testWidgets('saved trail info answers without downloading again', (
    WidgetTester tester,
  ) async {
    final store = _MemoryTrailGuideStore()
      ..guides[tourTrailGuide.id] = tourTrailGuide;
    await _pumpCard(tester, store);

    expect(find.text('Download trail info'), findsNothing);
    expect(find.textContaining('8 sections'), findsOneWidget);

    await _askFor(tester, 'Is there drinking water on the way?');
    expect(find.textContaining('refill at the refuge'), findsOneWidget);
    expect(find.textContaining('From Tour du Portillon'), findsOneWidget);
  });
}
