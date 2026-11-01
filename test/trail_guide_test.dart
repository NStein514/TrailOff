import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailoff/trail_guide.dart';

void main() {
  TrailAnswer? ask(String question) =>
      answerTrailQuestion(guide: tourTrailGuide, question: question);
  String? sectionFor(String question) => ask(question)?.section.id;

  test('answers quote the guide section that covers the question', () {
    expect(sectionFor('Is there drinking water on the way?'), 'water');
    expect(
      ask('Is there drinking water on the way?')!.quote,
      contains('litres'),
    );

    expect(sectionFor('Can I camp at the lake?'), 'camping');
    expect(ask('Can I camp at the lake?')!.quote, contains('single night'));

    expect(sectionFor('Where can I park the car?'), 'access');
    expect(sectionFor('Are dogs allowed?'), 'livestock');
    expect(sectionFor('What number do I call for rescue?'), 'emergency');
    expect(sectionFor('How long does the hike take?'), 'route');
    expect(sectionFor('Is it safe in snow?'), 'hazards');
  });

  test('questions the guide cannot ground are refused, not guessed', () {
    expect(ask('Are there bears on the mountain?'), isNull);
    expect(ask('Is there a shop for gas canisters?'), isNull);
    expect(ask('   '), isNull);
    expect(ask('?'), isNull);
  });

  test('an answer always names its guide section', () {
    final answer = ask('Can I light a fire?');
    expect(answer, isNotNull);
    expect(answer!.section.id, 'camping');
    expect(answer.attribution, 'Tour du Portillon · Camping & bivouac rules');
  });

  test('downloaded guides round-trip through local storage', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesTrailGuideStore();
    expect(await store.load(tourTrailGuide.id), isNull);

    await store.save(tourTrailGuide);
    final loaded = await store.load(tourTrailGuide.id);
    expect(loaded, isNotNull);
    expect(loaded!.name, 'Tour du Portillon');
    expect(loaded.sections, hasLength(tourTrailGuide.sections.length));
    expect(loaded.sections.first.body, tourTrailGuide.sections.first.body);
    expect(loaded.sections.last.title, 'Emergency & phone signal');
    expect(
      answerTrailQuestion(
        guide: loaded,
        question: 'Are dogs allowed?',
      )?.section.id,
      'livestock',
    );

    await store.remove(tourTrailGuide.id);
    expect(await store.load(tourTrailGuide.id), isNull);
  });
}
