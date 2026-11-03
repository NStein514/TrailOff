import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the app shows distances and heights. Metric uses kilometres and
/// metres; imperial uses miles, feet and miles per hour.
enum MeasurementSystem {
  metric('Metric', 'km', 'm'),
  imperial('Imperial', 'mi', 'ft');

  const MeasurementSystem(this.label, this.shortDistance, this.shortHeight);

  final String label;
  final String shortDistance;
  final String shortHeight;
}

const _feetPerMeter = 3.280839895013123;
const _metersPerMile = 1609.344;
const _metersPerSecondToMph = 2.2369362920544;

/// Formats measurements for one system. Every figure the app shows goes
/// through here so a single setting changes distances, heights and speed
/// together instead of leaving a route in mixed units.
class Units {
  const Units([this.system = MeasurementSystem.metric]);

  static const metric = Units();
  static const imperial = Units(MeasurementSystem.imperial);

  final MeasurementSystem system;

  bool get isMetric => system == MeasurementSystem.metric;

  String get distanceUnit => system.shortDistance;

  String get heightUnit => system.shortHeight;

  String get speedUnit => isMetric ? 'km/h' : 'mph';

  MeasurementSystem get other =>
      isMetric ? MeasurementSystem.imperial : MeasurementSystem.metric;

  /// A route length, e.g. `3.2 km` or `2.0 mi`.
  String distance(double meters, {int decimals = 1}) {
    final value = isMetric ? meters / 1000 : meters / _metersPerMile;
    return '${value.toStringAsFixed(decimals)} $distanceUnit';
  }

  /// A short distance such as the walk to the trailhead: metres, feet or
  /// miles, whichever reads best.
  String shortDistance(double meters) {
    if (isMetric) {
      if (meters < 1000) return '${_roundTo(meters, 10)} m';
      return distance(meters);
    }
    final miles = meters / _metersPerMile;
    if (miles < 0.1) return '${(meters * _feetPerMeter).round()} ft';
    return distance(meters);
  }

  /// Climbing, e.g. `+380 m` or `+1,247 ft`.
  String ascent(double meters) =>
      '+${_heightValue(meters)} $heightUnit';

  /// A point height, e.g. `1,056 m` or `3,465 ft`.
  String height(num meters) => '${_heightValue(meters)} $heightUnit';

  /// Speed from metres per second.
  String speed(double metersPerSecond) {
    final value = isMetric
        ? metersPerSecond * 3.6
        : metersPerSecond * _metersPerSecondToMph;
    return '${value.toStringAsFixed(1)} $speedUnit';
  }

  /// GPS accuracy, kept in metres or feet because it is a small figure.
  String accuracy(double meters) => isMetric
      ? '${meters.round()} m'
      : '${(meters * _feetPerMeter).round()} ft';

  /// A search radius preset, e.g. `25 km` or `25 mi`.
  String radiusLabel(int value) => '$value $distanceUnit';

  /// The metres behind a radius preset in the current system.
  double radiusMeters(int value) =>
      value * (isMetric ? 1000 : _metersPerMile);

  String _heightValue(num meters) {
    if (isMetric) return _grouped(meters.round());
    return _grouped((meters * _feetPerMeter).round());
  }

  String _roundTo(double meters, int step) =>
      '${(meters / step).round() * step}';
}

String _grouped(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

/// Makes the chosen units available to every page and dialog, and lets any of
/// them offer the switch when the app provides a way to persist it.
class UnitsScope extends InheritedWidget {
  const UnitsScope({
    super.key,
    required this.units,
    this.onChanged,
    required super.child,
  });

  final Units units;

  /// Null in isolated tests and previews, where no setting is stored.
  final ValueChanged<MeasurementSystem>? onChanged;

  static Units of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UnitsScope>()?.units ??
      Units.metric;

  static ValueChanged<MeasurementSystem>? onChangedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UnitsScope>()?.onChanged;

  @override
  bool updateShouldNotify(UnitsScope oldWidget) =>
      oldWidget.units.system != units.system ||
      oldWidget.onChanged != onChanged;
}

/// Remembers the hiker's choice between launches.
abstract interface class UnitPreferenceStore {
  Future<MeasurementSystem> load();

  Future<void> save(MeasurementSystem system);
}

class SharedPreferencesUnitPreferenceStore implements UnitPreferenceStore {
  static const _storageKey = 'trailoff.units.v1';

  @override
  Future<MeasurementSystem> load() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_storageKey)) {
      'imperial' => MeasurementSystem.imperial,
      _ => MeasurementSystem.metric,
    };
  }

  @override
  Future<void> save(MeasurementSystem system) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      system == MeasurementSystem.imperial ? 'imperial' : 'metric',
    );
  }
}
