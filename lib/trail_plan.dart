import 'package:shared_preferences/shared_preferences.dart';

import 'trail_catalogue.dart';

/// Remembers the trail the hiker is currently planning to walk.
abstract interface class TrailPlanStore {
  Future<String?> loadPlannedTrailId();
  Future<void> plan(String trailId);
  Future<void> clear();
}

class SharedPreferencesTrailPlanStore implements TrailPlanStore {
  static const _storageKey = 'trailoff.planned_trail.v1';

  @override
  Future<String?> loadPlannedTrailId() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    return stored == null || stored.isEmpty ? null : stored;
  }

  @override
  Future<void> plan(String trailId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, trailId);
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}

/// Looks a planned trail up in the catalogue, ignoring ids that no longer
/// exist so an outdated plan cannot break the dashboard.
Trail? plannedTrail(List<Trail> trails, String? id) {
  if (id == null) return null;
  for (final trail in trails) {
    if (trail.id == id) return trail;
  }
  return null;
}
