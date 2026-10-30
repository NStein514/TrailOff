import 'hike_recording.dart';

enum HikingAbility {
  beginner('Beginner', 8000, 400),
  intermediate('Intermediate', 16000, 900),
  advanced('Advanced', 32000, 1800);

  const HikingAbility(this.label, this.maxDistanceMeters, this.maxAscentMeters);

  final String label;
  final double maxDistanceMeters;
  final double maxAscentMeters;
}

enum TrailConditions {
  dry('Dry', 1),
  wet('Wet', 0.75),
  snowy('Snow / ice', 0.5),
  hot('Hot', 0.7);

  const TrailConditions(this.label, this.capacityFactor);

  final String label;
  final double capacityFactor;

  String get preparationTip => switch (this) {
    TrailConditions.dry =>
      'Bring water and check the forecast before setting out.',
    TrailConditions.wet =>
      'Pack a waterproof shell; wet rocks and roots can be slippery.',
    TrailConditions.snowy =>
      'Check snow and ice reports; carry traction and warm layers.',
    TrailConditions.hot =>
      'Start early, carry extra water, and plan shaded breaks.',
  };
}

class RouteRecommendation {
  const RouteRecommendation({required this.hike, required this.reason});

  final SavedHike hike;
  final String reason;
}

RouteRecommendation? recommendSavedRoute({
  required List<SavedHike> hikes,
  required HikingAbility ability,
  required TrailConditions conditions,
}) {
  final distanceLimit = ability.maxDistanceMeters * conditions.capacityFactor;
  final ascentLimit = ability.maxAscentMeters * conditions.capacityFactor;
  final candidates = hikes.where((hike) {
    return hike.points.length >= 2 &&
        hike.distanceMeters > 0 &&
        hike.distanceMeters <= distanceLimit &&
        hike.elevationGainMeters <= ascentLimit;
  }).toList();
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final aScore = _routeScore(a, distanceLimit, ascentLimit);
    final bScore = _routeScore(b, distanceLimit, ascentLimit);
    return aScore.compareTo(bScore);
  });
  final route = candidates.first;
  return RouteRecommendation(
    hike: route,
    reason:
        'A route you have completed before, within your ${ability.label.toLowerCase()} range for ${conditions.label.toLowerCase()} conditions.',
  );
}

double _routeScore(SavedHike hike, double distanceLimit, double ascentLimit) {
  final distanceRatio = hike.distanceMeters / distanceLimit;
  final ascentRatio = hike.elevationGainMeters / ascentLimit;
  return (distanceRatio - 0.7).abs() + (ascentRatio - 0.65).abs();
}
