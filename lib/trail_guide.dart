import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A short, self-contained note from a trail guide. Answers are quoted from
/// exactly one of these sections so every reply has a visible source.
class TrailGuideSection {
  const TrailGuideSection({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;

  Map<String, Object> toJson() => {'id': id, 'title': title, 'body': body};

  factory TrailGuideSection.fromJson(Map<String, dynamic> json) =>
      TrailGuideSection(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

class TrailGuide {
  const TrailGuide({
    required this.id,
    required this.name,
    required this.region,
    required this.sections,
  });

  final String id;
  final String name;
  final String region;
  final List<TrailGuideSection> sections;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'region': region,
    'sections': sections.map((section) => section.toJson()).toList(),
  };

  factory TrailGuide.fromJson(Map<String, dynamic> json) => TrailGuide(
    id: json['id'] as String,
    name: json['name'] as String,
    region: json['region'] as String,
    sections: (json['sections'] as List<dynamic>)
        .map(
          (section) =>
              TrailGuideSection.fromJson(section as Map<String, dynamic>),
        )
        .toList(),
  );
}

/// Sample guide bundled with the app so the offline question flow can be
/// exercised without a network. Real deployments should replace this with
/// downloaded guide data for the region.
const tourTrailGuide = TrailGuide(
  id: 'tour-du-portillon',
  name: 'Tour du Portillon',
  region: 'Luchon, Pyrenees',
  sections: [
    TrailGuideSection(
      id: 'access',
      title: 'Getting there & parking',
      body:
          'The trail starts at the Hospice de France car park, about 12 km '
          'from Luchon along a single mountain road. Parking is a gravel lot '
          'for roughly 40 cars and fills by 09:00 in summer; there is no '
          'overnight parking charge. A summer shuttle runs from Luchon, but '
          'outside July and August you need your own transport.',
    ),
    TrailGuideSection(
      id: 'route',
      title: 'Route & waymarks',
      body:
          'The loop is 12.4 km with about 1,120 m of ascent and takes most '
          'hikers 5 to 6 hours. Follow the red and white GR waymarks to the '
          'lake and return by the balcony path; the final hour is steep and '
          'loose. Allow more time if you are new to mountain walking or '
          'carrying a full pack.',
    ),
    TrailGuideSection(
      id: 'water',
      title: 'Water & refills',
      body:
          'There are no reliable taps above the trailhead. Streams cross the '
          'path at two points and the refuge sells bottled water when it is '
          'staffed, so carry at least 2 litres and refill at the refuge. '
          'Treat or filter any water taken from streams, especially above the '
          'lake where livestock graze.',
    ),
    TrailGuideSection(
      id: 'hazards',
      title: 'Terrain & hazards',
      body:
          'The upper section holds snowfields into June and the path crosses '
          'loose stone below the lake. Fog can erase the waymarks quickly, so '
          'carry the offline map and a charged phone. Do not cross the outlet '
          'stream after heavy rain.',
    ),
    TrailGuideSection(
      id: 'weather',
      title: 'Weather & seasons',
      body:
          'Afternoon thunderstorms build quickly here between June and '
          'September, so plan to be below the lake by 14:00. Winter and '
          'spring bring snow and ice, and the road to the trailhead can close '
          'after heavy snowfall. Check the forecast on the morning you leave.',
    ),
    TrailGuideSection(
      id: 'livestock',
      title: 'Wildlife & livestock',
      body:
          'Dogs must stay on a lead and give the sheep and cattle a wide '
          'berth; guard dogs protect the flock in summer. Do not approach or '
          'feed marmots or other wildlife, and close any gate you open.',
    ),
    TrailGuideSection(
      id: 'camping',
      title: 'Camping & bivouac rules',
      body:
          'Wild camping is only tolerated for a single night and never '
          'inside the lake basin or the nature reserve. Use an existing pitch '
          'below the treeline, carry out all waste, and cook on a stove '
          'instead of lighting a fire. The refuge has dormitory beds and '
          'should be booked ahead in summer.',
    ),
    TrailGuideSection(
      id: 'emergency',
      title: 'Emergency & phone signal',
      body:
          'Dial 112 for mountain rescue in France; the number reaches the '
          'emergency services even without a mobile plan, but you still need '
          'some signal. Coverage is patchy above the trailhead and often '
          'absent in the lake basin, so share your planned route before '
          'leaving. The refuge warden can relay messages when staffed.',
    ),
  ],
);

abstract interface class TrailGuideStore {
  Future<TrailGuide?> load(String id);
  Future<void> save(TrailGuide guide);
  Future<void> remove(String id);
}

class SharedPreferencesTrailGuideStore implements TrailGuideStore {
  static const _storageKey = 'trailoff.trail_guides.v1';

  Future<Map<String, dynamic>> _read() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    if (stored == null || stored.isEmpty) return {};
    return jsonDecode(stored) as Map<String, dynamic>;
  }

  Future<void> _write(Map<String, dynamic> guides) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(guides));
  }

  @override
  Future<TrailGuide?> load(String id) async {
    final guides = await _read();
    final stored = guides[id];
    if (stored is! Map<String, dynamic>) return null;
    return TrailGuide.fromJson(stored);
  }

  @override
  Future<void> save(TrailGuide guide) async {
    final guides = await _read();
    guides[guide.id] = guide.toJson();
    await _write(guides);
  }

  @override
  Future<void> remove(String id) async {
    final guides = await _read();
    if (guides.remove(id) == null) return;
    await _write(guides);
  }
}

class TrailAnswer {
  const TrailAnswer({
    required this.guide,
    required this.section,
    required this.quote,
  });

  final TrailGuide guide;
  final TrailGuideSection section;
  final String quote;

  String get attribution => '${guide.name} · ${section.title}';
}

/// Answers a question by finding the single guide section that best covers
/// every term the user asked about, then quoting the sentence in that section
/// with the most matching terms.
///
/// This is offline keyword matching over downloaded text, not a language
/// model: questions that mention anything the guide does not discuss return
/// `null` instead of a plausible-sounding guess.
TrailAnswer? answerTrailQuestion({
  required TrailGuide guide,
  required String question,
}) {
  final asked = _concepts(question);
  if (asked.isEmpty) return null;

  final sectionConcepts = {
    for (final section in guide.sections) section.id: _sectionConcepts(section),
  };
  final vocabulary = <String>{
    for (final concepts in sectionConcepts.values) ...concepts,
  };
  final grounded = asked.intersection(vocabulary);
  if (grounded.isEmpty || grounded.length != asked.length) return null;

  TrailGuideSection? best;
  var bestScore = 0.0;
  for (final section in guide.sections) {
    final concepts = sectionConcepts[section.id]!;
    final titleConcepts = _concepts(section.title);
    final matched = grounded.where(concepts.contains).toList();
    final coverage = matched.length / grounded.length;
    if (coverage < 0.5) continue;
    final titleHits = matched.where(titleConcepts.contains).length;
    final score = coverage * 10 + titleHits * 2 + matched.length;
    if (best == null || score > bestScore) {
      best = section;
      bestScore = score;
    }
  }
  if (best == null) return null;

  final quote = _quoteFor(best, grounded) ?? best.body;
  return TrailAnswer(guide: guide, section: best, quote: quote);
}

Set<String> _sectionConcepts(TrailGuideSection section) =>
    _concepts('${section.title} ${section.body}');

/// Maps the words of [text] onto guide concepts, so "stream", "tap" and
/// "drinking" all count as the same topic.
Set<String> _concepts(String text) =>
    _words(text).map(_conceptFor).whereType<String>().toSet();

String? _conceptFor(String word) {
  for (final candidate in [word, _stem(word), _stripSuffix(word)]) {
    if (candidate == null || candidate.isEmpty) continue;
    final concept = _termConcepts[candidate];
    if (concept != null) return concept;
  }
  return _stopWords.contains(word) ? null : _stem(word);
}

String _stem(String word) =>
    word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
    ? word.substring(0, word.length - 1)
    : word;

String? _stripSuffix(String word) {
  for (final suffix in const ['able', 'ing', 'ed']) {
    if (word.length > suffix.length + 3 && word.endsWith(suffix)) {
      return word.substring(0, word.length - suffix.length);
    }
  }
  return null;
}

Iterable<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.length > 2 && !_stopWords.contains(word));

String? _quoteFor(TrailGuideSection section, Set<String> asked) {
  final sentences = _sentences(section.body);
  if (sentences.isEmpty) return null;
  var best = sentences.first;
  var bestHits = -1;
  for (final sentence in sentences) {
    var hits = 0;
    for (final word in _words(sentence)) {
      final concept = _conceptFor(word);
      if (concept != null && asked.contains(concept)) hits++;
    }
    if (hits > bestHits) {
      best = sentence;
      bestHits = hits;
    }
  }
  return best;
}

Iterable<String> _sentences(String body) => RegExp(r'[^.!?]+[.!?]*')
    .allMatches(body)
    .map((match) => match.group(0)!.trim())
    .where((sentence) => sentence.isNotEmpty);

const _stopWords = {
  'the',
  'a',
  'an',
  'and',
  'any',
  'are',
  'as',
  'at',
  'be',
  'before',
  'bring',
  'but',
  'by',
  'can',
  'could',
  'do',
  'does',
  'for',
  'from',
  'have',
  'how',
  'i',
  'if',
  'in',
  'into',
  'is',
  'it',
  'like',
  'me',
  'much',
  'my',
  'need',
  'of',
  'on',
  'or',
  'our',
  'should',
  'so',
  'some',
  'that',
  'there',
  'this',
  'to',
  'was',
  'we',
  'what',
  'when',
  'where',
  'which',
  'who',
  'why',
  'will',
  'with',
  'would',
  'you',
  'your',
  'route',
  'trail',
  'hike',
  'hiking',
  'walk',
  'walking',
  'path',
  'way',
  'guide',
  'trip',
  'know',
  'tell',
  'about',
  'allow',
  'allowed',
  'also',
  'anything',
  'available',
  'away',
  'even',
  'get',
  'gets',
  'go',
  'goes',
  'going',
  'good',
  'just',
  'ok',
  'okay',
  'plan',
  'planning',
  'possible',
  'put',
  'really',
  'recommend',
  'still',
  'take',
  'taken',
  'takes',
  'want',
  'wear',
};

const _conceptsByTopic = <String, Set<String>>{
  'water': {
    'water',
    'stream',
    'spring',
    'fountain',
    'drink',
    'drinking',
    'drinkable',
    'refill',
    'hydrate',
    'hydration',
    'tap',
    'thirsty',
    'litre',
    'litres',
    'liter',
    'liters',
    'bottle',
    'bottled',
  },
  'parking': {
    'park',
    'parking',
    'car',
    'parked',
    'drive',
    'driving',
    'lot',
    'transport',
    'shuttle',
    'trailhead',
    'access',
    'road',
    'charge',
  },
  'camping': {
    'camp',
    'camping',
    'bivouac',
    'bivvy',
    'tent',
    'sleep',
    'night',
    'overnight',
    'pitch',
    'stove',
    'dormitory',
    'fire',
    'fires',
    'light',
    'lighting',
    'book',
    'booked',
    'booking',
    'warden',
  },
  'livestock': {
    'dog',
    'pet',
    'patou',
    'sheep',
    'cattle',
    'cow',
    'livestock',
    'gate',
    'marmot',
    'wildlife',
    'animal',
    'guard',
    'lead',
    'graze',
    'feeding',
  },
  'snow': {
    'snow',
    'snowy',
    'snowfield',
    'ice',
    'icy',
    'winter',
    'crampons',
    'traction',
    'snowfall',
  },
  'weather': {
    'weather',
    'storm',
    'thunder',
    'thunderstorm',
    'lightning',
    'rain',
    'forecast',
    'cloud',
    'fog',
    'wind',
    'season',
    'summer',
    'autumn',
    'month',
  },
  'emergency': {
    'emergency',
    'rescue',
    'help',
    'accident',
    'injury',
    'hurt',
    '112',
    'helicopter',
    'sos',
    'number',
    'call',
    'dial',
    'services',
  },
  'phone': {
    'phone',
    'mobile',
    'reception',
    'coverage',
    'network',
    'gps',
    'offline',
    'signal',
    'charged',
    'messages',
  },
  'effort': {
    'distance',
    'long',
    'far',
    'km',
    'ascent',
    'climb',
    'climbing',
    'elevation',
    'steep',
    'difficult',
    'hard',
    'time',
    'hour',
    'hours',
    'duration',
    'pack',
    'effort',
    'loop',
  },
  'lake': {'lake', 'lac', 'basin', 'outlet'},
  'safety': {
    'safe',
    'safety',
    'danger',
    'dangerous',
    'risk',
    'risky',
    'hazard',
    'hazards',
    'caution',
    'careful',
  },
  'refuge': {'refuge', 'hut', 'shelter', 'bed', 'beds', 'staffed'},
};

final _termConcepts = <String, String>{
  for (final entry in _conceptsByTopic.entries)
    for (final term in entry.value) term: entry.key,
};
