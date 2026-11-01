import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailoff/constellation.dart';
import 'constellation_lifecycle_test.dart' as fixtures;

SkyPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<SkyPainter>()
    .single;

void main() {
  testWidgets(
    'full-screen drag, night display and back preserve the chart session',
    (tester) async {
      final motion = StreamController<dynamic>.broadcast();
      var fixes = 0;
      await fixtures.showSky(
        tester,
        orientation: motion.stream,
        locate: () async {
          fixes++;
          return fixtures.position(40);
        },
      );
      await tester.tap(find.byTooltip('Full-screen sky'));
      await tester.pumpAndSettle();
      expect(find.text('Sky view'), findsOneWidget);
      expect(find.text('Satellite predictions are off.'), findsOneWidget);
      final before = List<double>.of(painter(tester).matrix);
      await tester.drag(
        find.byKey(const Key('sky-chart')),
        const Offset(80, -20),
      );
      await tester.pump();
      final dragged = List<double>.of(painter(tester).matrix);
      expect(dragged, isNot(equals(before)));
      await tester.tap(find.byTooltip('Turn on red night display'));
      await tester.pump();
      expect(painter(tester).nightDisplay, isTrue);
      expect(
        Theme.of(tester.element(find.byKey(const Key('sky-chart')))).brightness,
        Brightness.dark,
      );
      expect(painter(tester).matrix, dragged);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Constellation'), findsOneWidget);
      expect(find.text('Sky view'), findsNothing);
      expect(painter(tester).matrix, dragged);
      expect(painter(tester).nightDisplay, isTrue);
      expect(fixes, 1);
      await tester.tap(find.byTooltip('Turn off red night display'));
      await tester.pump();
      expect(painter(tester).nightDisplay, isFalse);
      expect(
        Theme.of(tester.element(find.byKey(const Key('sky-chart')))).brightness,
        Brightness.light,
      );
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
    },
  );

  testWidgets(
    'full-screen controls fit narrow portrait and landscape with large text',
    (tester) async {
      final motion = StreamController<dynamic>.broadcast();
      await fixtures.showSky(
        tester,
        orientation: motion.stream,
        locate: () async => fixtures.position(40),
      );
      await tester.tap(find.byTooltip('Full-screen sky'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 568), const Size(568, 320)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final chart = tester.getSize(find.byKey(const Key('sky-chart')));
        expect(chart.height, greaterThan(80));
        expect(chart.width, greaterThan(200));
        expect(find.byTooltip('Exit full screen'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Exit full screen'));
      await tester.pumpAndSettle();
      expect(find.text('Constellation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
    },
  );

  testWidgets(
    'full-screen location refresh shows progress and recovers on resume',
    (tester) async {
      final motion = StreamController<dynamic>.broadcast();
      final fix = Completer<dynamic>();
      var requests = 0;
      await fixtures.showSky(
        tester,
        orientation: motion.stream,
        locate: () async {
          if (requests++ == 0) return fixtures.position(40);
          return await fix.future;
        },
      );
      await tester.tap(find.byTooltip('Full-screen sky'));
      await tester.pumpAndSettle();
      await fixtures.suspend(tester);
      await fixtures.resume(tester);
      expect(find.text('Finding location…'), findsWidgets);
      expect(find.byKey(const Key('sky-chart')), findsNothing);
      fix.complete(fixtures.position(41));
      await tester.pumpAndSettle();
      expect(find.text('Sky view'), findsOneWidget);
      expect(find.byKey(const Key('sky-chart')), findsOneWidget);
      expect(painter(tester).location.latitude, 41);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      unawaited(motion.close());
      await tester.pump();
    },
  );
}
