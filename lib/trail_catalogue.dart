import 'dart:math' as math;

import 'route_recommendations.dart';

/// How a catalogue route compares with the hiker's ability on a given day.
enum TrailFit {
  comfortable('Fits today'),
  stretch('A stretch'),
  tooDemanding('Too demanding today');

  const TrailFit(this.label);

  final String label;
}

class Trail {
  const Trail({
    required this.id,
    required this.name,
    required this.area,
    required this.distanceMeters,
    required this.ascentMeters,
    required this.durationMinutes,
    required this.highestPointMeters,
    required this.summary,
    required this.notes,
  });

  final String id;
  final String name;
  final String area;
  final double distanceMeters;
  final double ascentMeters;
  final int durationMinutes;
  final int highestPointMeters;
  final String summary;
  final List<String> notes;

  String get distanceLabel =>
      '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  String get ascentLabel => '+${ascentMeters.round()} m';

  String get durationLabel {
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours h';
    return '$hours h $minutes';
  }
}

class TrailSuggestion {
  const TrailSuggestion({
    required this.trail,
    required this.fit,
    required this.load,
  });

  final Trail trail;
  final TrailFit fit;

  /// Distance or ascent as a fraction of the day's capacity; 1.0 is the limit.
  final double load;
}

/// Distance and ascent relative to what the hiker can take on in these
/// conditions. The larger of the two decides how the route feels.
double trailLoad({
  required Trail trail,
  required HikingAbility ability,
  required TrailConditions conditions,
}) {
  final distanceLimit = ability.maxDistanceMeters * conditions.capacityFactor;
  final ascentLimit = ability.maxAscentMeters * conditions.capacityFactor;
  return math.max(
    trail.distanceMeters / distanceLimit,
    trail.ascentMeters / ascentLimit,
  );
}

TrailFit trailFit({
  required Trail trail,
  required HikingAbility ability,
  required TrailConditions conditions,
}) {
  final load = trailLoad(
    trail: trail,
    ability: ability,
    conditions: conditions,
  );
  if (load <= 0.75) return TrailFit.comfortable;
  if (load <= 1) return TrailFit.stretch;
  return TrailFit.tooDemanding;
}

/// Routes that suit the hiker first, then the shortest remaining options.
List<TrailSuggestion> suggestTrails({
  required List<Trail> trails,
  required HikingAbility ability,
  required TrailConditions conditions,
}) {
  final suggestions = [
    for (final trail in trails)
      TrailSuggestion(
        trail: trail,
        fit: trailFit(trail: trail, ability: ability, conditions: conditions),
        load: trailLoad(trail: trail, ability: ability, conditions: conditions),
      ),
  ];
  suggestions.sort((a, b) {
    final byFit = a.fit.index.compareTo(b.fit.index);
    return byFit != 0 ? byFit : a.load.compareTo(b.load);
  });
  return suggestions;
}

String trailFitReason(TrailFit fit) => switch (fit) {
  TrailFit.comfortable => 'Well inside your range for these conditions.',
  TrailFit.stretch =>
    'At the edge of your range for these conditions. Start early, keep the pace easy and turn back if the weather turns.',
  TrailFit.tooDemanding =>
    'Beyond your range for these conditions. Pick a shorter route or wait for better weather.',
};

/// Sample routes bundled with the app so discovery can be exercised offline.
/// Replace with downloaded catalogue data before relying on the numbers.
const sampleTrailCatalogue = <Trail>[
  Trail(
    id: 'portillon-loop',
    name: 'Lac du Portillon loop',
    area: 'Hospice de France',
    distanceMeters: 12400,
    ascentMeters: 1120,
    durationMinutes: 330,
    highestPointMeters: 2480,
    summary:
        'A big mountain day to a glacial lake below the Portillon pass, with '
        'the refuge as a halfway shelter.',
    notes: [
      'Snowfields linger into June on the upper section.',
      'The last hour is steep and loose underfoot.',
      'Streams at two points; treat any water you take.',
    ],
  ),
  Trail(
    id: 'imperatrice-falls',
    name: 'Cascade de l’Impératrice',
    area: 'Bois de la Pique',
    distanceMeters: 4800,
    ascentMeters: 260,
    durationMinutes: 90,
    highestPointMeters: 1300,
    summary:
        'A short forest climb to a waterfall, good for an evening leg '
        'stretch or a first mountain walk.',
    notes: [
      'Waymarked throughout; the path is rocky near the falls.',
      'Shaded most of the way, so it stays cooler on hot afternoons.',
      'Popular with families — expect company on summer weekends.',
    ],
  ),
  Trail(
    id: 'glere-refuge',
    name: 'Refuge de la Glère',
    area: 'Hospice de France',
    distanceMeters: 8600,
    ascentMeters: 620,
    durationMinutes: 195,
    highestPointMeters: 1900,
    summary:
        'A steady balcony climb to a staffed refuge, with grazing pastures '
        'and a long view back down the valley.',
    notes: [
      'Sheep and guard dogs are on the lower slopes in summer.',
      'The refuge serves simple meals when staffed.',
      'Crosses open ground — take a shell even on a bright morning.',
    ],
  ),
  Trail(
    id: 'oo-espingo',
    name: 'Lac d’Oô & Espingo',
    area: 'Oô valley',
    distanceMeters: 11200,
    ascentMeters: 780,
    durationMinutes: 300,
    highestPointMeters: 1970,
    summary:
        'Two lakes linked by a waterfall staircase, finishing at a small '
        'mountain hut below the pass.',
    notes: [
      'The waterfall section is slippery when wet.',
      'Swimming is cold year round and not patrolled.',
      'The hut is a good turnaround point if weather closes in.',
    ],
  ),
  Trail(
    id: 'pique-ridge',
    name: 'Pic de la Pique ridge',
    area: 'Superbagnères',
    distanceMeters: 14200,
    ascentMeters: 1250,
    durationMinutes: 390,
    highestPointMeters: 2400,
    summary:
        'An exposed ridge traverse with sustained climbing and no easy '
        'escape until the summit block.',
    notes: [
      'Exposed to wind and lightning for long stretches.',
      'Navigation is harder in cloud — carry the offline map.',
      'Best saved for a settled forecast and a long day.',
    ],
  ),
  Trail(
    id: 'bois-pique',
    name: 'Bois de la Pique circuit',
    area: 'Bagnères-de-Luchon',
    distanceMeters: 3200,
    ascentMeters: 120,
    durationMinutes: 60,
    highestPointMeters: 1100,
    summary:
        'A gentle forest loop from town, useful for a rest day or a short '
        'walk with a pack.',
    notes: [
      'Well marked and easy to follow in any weather.',
      'Benches along the way; no water source on the loop.',
      'A good choice when the high routes are closed.',
    ],
  ),
];
