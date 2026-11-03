import 'dart:math' as math;

import 'route_recommendations.dart';
import 'trail_geometry.dart';

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
    required this.trailheadLatitude,
    required this.trailheadLongitude,
    required this.route,
    this.elevationKnown = true,
  });

  final String id;
  final String name;
  final String area;
  final double distanceMeters;
  final double ascentMeters;
  final int durationMinutes;
  final int highestPointMeters;

  /// Approximate trailhead, used to centre the map and choose the area to
  /// save for offline use.
  final double trailheadLatitude;
  final double trailheadLongitude;

  /// Sample geometry for drawing the route and sizing offline downloads. The
  /// distance and ascent figures above are the curated ones; this line is
  /// indicative and must be replaced with real track data.
  final List<TrailPoint> route;
  final String summary;
  final List<String> notes;

  /// False for routes found online whose ascent and high point could not be
  /// estimated, so the fit and the packing list do not pretend they are flat.
  final bool elevationKnown;

  String get distanceLabel =>
      '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  String get ascentLabel => elevationKnown ? '+${ascentMeters.round()} m' : '—';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'area': area,
    'distanceMeters': distanceMeters,
    'ascentMeters': ascentMeters,
    'durationMinutes': durationMinutes,
    'highestPointMeters': highestPointMeters,
    'elevationKnown': elevationKnown,
    'summary': summary,
    'notes': notes,
    'trailheadLatitude': trailheadLatitude,
    'trailheadLongitude': trailheadLongitude,
    'route': [
      for (final point in route) [point.latitude, point.longitude],
    ],
  };

  factory Trail.fromJson(Map<String, dynamic> json) => Trail(
    id: json['id'] as String,
    name: json['name'] as String,
    area: json['area'] as String? ?? '',
    distanceMeters: (json['distanceMeters'] as num).toDouble(),
    ascentMeters: (json['ascentMeters'] as num?)?.toDouble() ?? 0,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    highestPointMeters: (json['highestPointMeters'] as num?)?.toInt() ?? 0,
    elevationKnown: json['elevationKnown'] as bool? ?? true,
    summary: json['summary'] as String? ?? '',
    notes: [
      for (final note in json['notes'] as List<dynamic>? ?? const []) note as String,
    ],
    trailheadLatitude: (json['trailheadLatitude'] as num).toDouble(),
    trailheadLongitude: (json['trailheadLongitude'] as num).toDouble(),
    route: [
      for (final point in json['route'] as List<dynamic>? ?? const [])
        TrailPoint(
          ((point as List<dynamic>)[0] as num).toDouble(),
          (point[1] as num).toDouble(),
        ),
    ],
  );

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
  final ascentLoad = trail.elevationKnown
      ? trail.ascentMeters / ascentLimit
      : 0.0;
  return math.max(trail.distanceMeters / distanceLimit, ascentLoad);
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
    id: 'tour-du-portillon',
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
    trailheadLatitude: 42.686,
    trailheadLongitude: 0.5546,
    route: [
      TrailPoint(42.686, 0.5546),
      TrailPoint(42.6905, 0.5602),
      TrailPoint(42.6938, 0.5645),
      TrailPoint(42.6975, 0.5610),
      TrailPoint(42.7005, 0.5570),
      TrailPoint(42.6990, 0.5525),
      TrailPoint(42.6960, 0.5498),
      TrailPoint(42.6910, 0.5460),
      TrailPoint(42.6872, 0.5502),
      TrailPoint(42.686, 0.5546),
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
    trailheadLatitude: 42.789,
    trailheadLongitude: 0.596,
    route: [
      TrailPoint(42.789, 0.596),
      TrailPoint(42.7912, 0.5985),
      TrailPoint(42.7935, 0.5975),
      TrailPoint(42.7958, 0.5995),
      TrailPoint(42.7972, 0.6018),
      TrailPoint(42.7958, 0.5995),
      TrailPoint(42.7912, 0.5985),
      TrailPoint(42.789, 0.596),
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
    trailheadLatitude: 42.688,
    trailheadLongitude: 0.552,
    route: [
      TrailPoint(42.688, 0.552),
      TrailPoint(42.6905, 0.5485),
      TrailPoint(42.6932, 0.5455),
      TrailPoint(42.6960, 0.5435),
      TrailPoint(42.6990, 0.5448),
      TrailPoint(42.7002, 0.5478),
      TrailPoint(42.6968, 0.5502),
      TrailPoint(42.6925, 0.5525),
      TrailPoint(42.688, 0.552),
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
    trailheadLatitude: 42.728,
    trailheadLongitude: 0.49,
    route: [
      TrailPoint(42.728, 0.49),
      TrailPoint(42.7315, 0.4935),
      TrailPoint(42.7345, 0.4960),
      TrailPoint(42.7375, 0.4990),
      TrailPoint(42.7395, 0.5025),
      TrailPoint(42.7410, 0.5060),
      TrailPoint(42.7380, 0.5035),
      TrailPoint(42.7350, 0.5000),
      TrailPoint(42.7310, 0.4960),
      TrailPoint(42.728, 0.49),
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
    trailheadLatitude: 42.755,
    trailheadLongitude: 0.578,
    route: [
      TrailPoint(42.755, 0.578),
      TrailPoint(42.7585, 0.5740),
      TrailPoint(42.7610, 0.5700),
      TrailPoint(42.7640, 0.5665),
      TrailPoint(42.7675, 0.5625),
      TrailPoint(42.7705, 0.5585),
      TrailPoint(42.7660, 0.5560),
      TrailPoint(42.7620, 0.5590),
      TrailPoint(42.7575, 0.5650),
      TrailPoint(42.755, 0.578),
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
    trailheadLatitude: 42.79,
    trailheadLongitude: 0.594,
    route: [
      TrailPoint(42.79, 0.594),
      TrailPoint(42.7922, 0.5962),
      TrailPoint(42.7938, 0.5990),
      TrailPoint(42.7920, 0.6012),
      TrailPoint(42.7898, 0.5998),
      TrailPoint(42.7890, 0.5968),
      TrailPoint(42.79, 0.594),
    ],
  ),
];
