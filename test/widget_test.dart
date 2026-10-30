import 'package:flutter_test/flutter_test.dart';

import 'package:trailoff/main.dart';

void main() {
  testWidgets('shows the TrailOff hike dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const TrailOffApp());

    expect(find.text('Track your progress\nand stay on trail'), findsOneWidget);
    expect(find.text('Save map offline'), findsOneWidget);
    expect(find.text('Elevation'), findsOneWidget);
    expect(find.text('4.2 km'), findsNWidgets(2));

    await tester.tap(find.text('Save map offline'));
    await tester.pump();
    expect(find.text('Map saved offline'), findsOneWidget);
  });
}
