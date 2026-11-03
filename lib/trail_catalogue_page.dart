import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'route_recommendations.dart';
import 'trail_catalogue.dart';
import 'trail_discovery.dart';
import 'trail_fit_badge.dart';
import 'trail_plan.dart';
import 'units.dart';

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

class TrailCataloguePage extends StatefulWidget {
  const TrailCataloguePage({
    super.key,
    this.ability = HikingAbility.beginner,
    this.conditions = TrailConditions.dry,
    this.trails = sampleTrailCatalogue,
    this.planStore,
    this.discoverySource,
    this.discoveredTrailStore,
    this.searchLocation,
    this.placeSearchSource,
  });

  final HikingAbility ability;
  final TrailConditions conditions;
  final List<Trail> trails;
  final TrailPlanStore? planStore;

  /// Source of routes around the hiker. Defaults to OpenStreetMap when the
  /// hiker asks for trails near them.
  final TrailDiscoverySource? discoverySource;

  /// Keeps trails found online so a plan made from them still resolves later.
  final DiscoveredTrailStore? discoveredTrailStore;

  /// Where to search from. Left null in the app, where the platform location
  /// plugin is used; tests pass a fixed point.
  final TrailSearchLocation? searchLocation;

  /// Looks up place names so trails can be found ahead of a trip.
  final PlaceSearchSource? placeSearchSource;

  @override
  State<TrailCataloguePage> createState() => _TrailCataloguePageState();
}

class _TrailCataloguePageState extends State<TrailCataloguePage> {
  late HikingAbility _ability = widget.ability;
  late TrailConditions _conditions = widget.conditions;
  late final TrailPlanStore _planStore;
  late final TrailDiscoverySource _discoverySource =
      widget.discoverySource ?? OpenStreetMapTrailSource();
  late final PlaceSearchSource _placeSource =
      widget.placeSearchSource ?? OpenStreetMapPlaceSource();
  final TextEditingController _placeController = TextEditingController();
  String? _plannedTrailId;

  /// The routes on screen: the bundled sample until the hiker searches, then
  /// whatever was found around them.
  late List<Trail> _trails = widget.trails;
  Map<String, TrailMatch> _matches = const {};
  bool _searching = false;
  String? _searchNote;

  /// The last search that was attempted, so a failed one can be retried
  /// without making the hiker pick their place again.
  TrailSearchLocation? _lastSearch;
  bool _searchFailed = false;

  /// The radius preset, counted in the units on screen (km or mi).
  int _radiusValue = 25;

  /// The place the current results belong to, when it is not the hiker's own
  /// position.
  String? _searchPlaceName;
  bool _searchingPlaces = false;
  String? _placeNote;
  List<PlaceMatch> _placeResults = const [];

  bool get _showingFoundTrails => _matches.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _planStore = widget.planStore ?? SharedPreferencesTrailPlanStore();
    _loadPlan();
  }

  @override
  void dispose() {
    _placeController.dispose();
    super.dispose();
  }

  Future<void> _findNearby() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _searchNote = null;
      _placeNote = null;
      _placeResults = const [];
    });
    TrailSearchLocation location;
    try {
      // A location fix that never arrives must not leave the search spinning.
      location =
          widget.searchLocation ??
          await _currentLocation().timeout(const Duration(seconds: 30));
    } on LocationServiceDisabledException {
      _reportSearchFailure('Turn on location services to find trails near you.');
      return;
    } on TimeoutException {
      _reportSearchFailure(
        'Finding your location took too long. Try again somewhere with a '
        'clear view of the sky.',
      );
      return;
    } catch (_) {
      _reportSearchFailure(
        'Your location is not available. Turn on location services, or search '
        'for a place instead.',
      );
      return;
    }
    await _searchAt(location);
  }

  /// Looks up a place by name, so a hiker can find routes for a trip before
  /// they get there.
  Future<void> _searchPlaces() async {
    final query = _placeController.text.trim();
    if (query.length < 2 || _searchingPlaces) return;
    setState(() {
      _searchingPlaces = true;
      _placeNote = null;
      _placeResults = const [];
    });
    try {
      final places = await _placeSource.search(query);
      if (!mounted) return;
      setState(() {
        _searchingPlaces = false;
        _placeResults = places;
        _placeNote = places.isEmpty
            ? 'No place matched “$query”. Try a fuller name or add the country.'
            : null;
      });
    } on PlaceSearchException catch (error) {
      if (!mounted) return;
      setState(() {
        _searchingPlaces = false;
        _placeNote = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searchingPlaces = false;
        _placeNote = 'The place search failed: $error';
      });
    }
  }

  Future<void> _searchNearPlace(PlaceMatch place) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _placeResults = const [];
      _placeNote = null;
      _searching = true;
      _searchNote = null;
    });
    await _searchAt(
      TrailSearchLocation(
        place.latitude,
        place.longitude,
        name: place.name,
      ),
    );
  }

  Future<void> _searchAt(TrailSearchLocation location) async {
    final units = UnitsScope.of(context);
    final radiusLabel = units.radiusLabel(_radiusValue);
    final where = location.name ?? 'your location';
    setState(() {
      _lastSearch = location;
      _searchFailed = false;
    });
    try {
      final matches = await _discoverySource.findNearby(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: units.radiusMeters(_radiusValue),
      );
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() {
          _searching = false;
          _matches = const {};
          _trails = widget.trails;
          _searchPlaceName = null;
          _searchNote =
              'No named hiking routes within $radiusLabel of $where. '
              'Showing the bundled sample routes.';
        });
        return;
      }
      final trails = [for (final match in matches) match.trail];
      setState(() {
        _searching = false;
        _matches = {for (final match in matches) match.trail.id: match};
        _trails = trails;
        _searchPlaceName = location.name;
        _searchNote =
            '${trails.length} ${trails.length == 1 ? 'route' : 'routes'} '
            'within $radiusLabel of $where, from OpenStreetMap.';
      });
      await _remember(trails);
    } on TrailDiscoveryException catch (error) {
      _reportSearchFailure(error.message, where);
    } catch (error) {
      _reportSearchFailure('The trail search failed: $error', where);
    }
  }

  void _reportSearchFailure(String message, [String? where]) {
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchFailed = true;
      _matches = const {};
      _trails = widget.trails;
      _searchNote = where == null
          ? '$message Showing the bundled sample routes.'
          : '$message Showing the bundled sample routes instead of trails '
                'near $where.';
    });
  }

  /// Keeps found trails on the device, because a plan stores only their id.
  Future<void> _remember(List<Trail> trails) async {
    final store = widget.discoveredTrailStore;
    if (store == null) return;
    try {
      await store.remember(trails);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _searchNote =
            'Routes found, but they could not be saved for the next launch.',
      );
    }
  }

  Future<TrailSearchLocation> _currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const TrailDiscoveryException(
        'Turn on location services to find trails near you.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const TrailDiscoveryException(
        'Location permission is needed to find trails near you.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return TrailSearchLocation(position.latitude, position.longitude);
  }

  Future<void> _loadPlan() async {
    try {
      final id = await _planStore.loadPlannedTrailId();
      if (!mounted) return;
      setState(() => _plannedTrailId = id);
    } catch (_) {
      // Having no saved plan is a valid state; saving reports real failures.
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final units = UnitsScope.of(context);
    final onUnitsChanged = UnitsScope.onChangedOf(context);
    final suggestions = suggestTrails(
      trails: _trails,
      ability: _ability,
      conditions: _conditions,
    );
    final suitable = suggestions
        .where((suggestion) => suggestion.fit != TrailFit.tooDemanding)
        .length;
    final radiusLabel = units.radiusLabel(_radiusValue);
    final where = _searchPlaceName ?? 'your location';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover trails'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        titleTextStyle: const TextStyle(
          color: _ink,
          fontFamily: 'Georgia',
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        actions: [
          if (onUnitsChanged != null)
            Tooltip(
              message: units.isMetric
                  ? 'Switch to miles and feet'
                  : 'Switch to kilometres and metres',
              child: TextButton(
                key: const Key('catalogue-units-toggle'),
                onPressed: () => onUnitsChanged(units.other),
                child: Text(units.distanceUnit),
              ),
            ),
        ],
      ),
      body: ListView(
        key: const Key('catalogue-list'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            !_showingFoundTrails
                ? 'Routes near Luchon'
                : _searchPlaceName == null
                ? 'Trails near you'
                : 'Trails near ${_searchPlaceName!}',
            style: const TextStyle(
              color: _ink,
              fontFamily: 'Georgia',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _showingFoundTrails
                ? 'Within $radiusLabel of $where · '
                      '${_trails.length} routes from OpenStreetMap'
                : 'Sample catalogue · ${_trails.length} routes',
            style: const TextStyle(color: Color(0xFF777E79), fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('find-trails-nearby'),
                  onPressed: _searching ? null : _findNearby,
                  icon: _searching
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(
                    _searching ? 'Searching…' : 'Find trails near me',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _forest,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<int>(
                key: const Key('discovery-radius'),
                value: _radiusValue,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (final value in const [10, 25, 50])
                    DropdownMenuItem(
                      value: value,
                      child: Text(units.radiusLabel(value)),
                    ),
                ],
                onChanged: _searching
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _radiusValue = value);
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('place-search-field'),
                  controller: _placeController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchPlaces(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search a place for a trip',
                    prefixIcon: const Icon(Icons.place_outlined, size: 18),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('place-search-submit'),
                onPressed: _searchingPlaces ? null : _searchPlaces,
                tooltip: 'Search this place',
                icon: _searchingPlaces
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded, size: 20),
              ),
            ],
          ),
          if (_placeNote != null) ...[
            const SizedBox(height: 7),
            Text(
              _placeNote!,
              key: const Key('place-note'),
              style: const TextStyle(
                color: Color(0xFF68716B),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
          for (final (index, place) in _placeResults.indexed)
            ListTile(
              key: Key('place-result-$index'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.place_outlined,
                color: _forest,
                size: 20,
              ),
              title: Text(
                place.name,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: place.details.isEmpty
                  ? null
                  : Text(
                      place.details,
                      style: const TextStyle(
                        color: Color(0xFF777E79),
                        fontSize: 11,
                      ),
                    ),
              trailing: const Text(
                'Find trails',
                style: TextStyle(
                  color: _forest,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _searching ? null : () => _searchNearPlace(place),
            ),
          if (_searchNote != null) ...[
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_searchFailed) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 1, right: 5),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 14,
                      color: Color(0xFF9A4A2F),
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    _searchNote!,
                    key: const Key('discovery-note'),
                    style: TextStyle(
                      color: _searchFailed
                          ? const Color(0xFF9A4A2F)
                          : const Color(0xFF68716B),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
                if (_searchFailed && _lastSearch != null)
                  TextButton(
                    key: const Key('discovery-retry'),
                    onPressed: _searching
                        ? null
                        : () {
                            final again = _lastSearch!;
                            setState(() => _searching = true);
                            _searchAt(again);
                          },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Try again',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<HikingAbility>(
                  key: const Key('catalogue-ability'),
                  initialValue: _ability,
                  decoration: const InputDecoration(
                    labelText: 'Ability',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  items: HikingAbility.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _ability = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<TrailConditions>(
                  key: const Key('catalogue-conditions'),
                  initialValue: _conditions,
                  decoration: const InputDecoration(
                    labelText: 'Conditions',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  items: TrailConditions.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _conditions = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$suitable of ${_trails.length} routes fit your level in '
            '${_conditions.label.toLowerCase()} conditions.',
            style: const TextStyle(
              color: Color(0xFF68716B),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          for (final suggestion in suggestions)
            _TrailTile(
              suggestion: suggestion,
              planned: suggestion.trail.id == _plannedTrailId,
              distanceLabel: _matches[suggestion.trail.id]?.distanceLabel(
                units,
              ),
              onTap: () => _showDetails(suggestion),
            ),
          const SizedBox(height: 4),
          Text(
            _showingFoundTrails
                ? 'Routes from OpenStreetMap hiking relations. Distance, ascent '
                      'and walking time are estimates; check access, closures and '
                      'current conditions with local sources.'
                : 'Sample catalogue bundled with TrailOff. Distances, access and '
                      'current conditions must be checked with local sources '
                      'before you rely on them. To plan a trip elsewhere, search '
                      'for a place above.',
            style: const TextStyle(color: Color(0xFF858B86), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(TrailSuggestion suggestion) async {
    final planned = suggestion.trail.id == _plannedTrailId;
    final action = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFFFAFBF9),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _TrailDetails(
        suggestion: suggestion,
        conditions: _conditions,
        planned: planned,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action) {
        await _planStore.plan(suggestion.trail.id);
      } else {
        await _planStore.clear();
      }
      if (!mounted) return;
      setState(() => _plannedTrailId = action ? suggestion.trail.id : null);
      _showMessage(
        action
            ? '${suggestion.trail.name} is now your planned trail.'
            : 'Planned trail cleared.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Your plan could not be saved on this device.');
    }
  }
}

class _TrailTile extends StatelessWidget {
  const _TrailTile({
    required this.suggestion,
    required this.planned,
    required this.onTap,
    this.distanceLabel,
  });

  final TrailSuggestion suggestion;
  final bool planned;
  final VoidCallback onTap;

  /// How far the trailhead is from the hiker, for routes found on the day.
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final trail = suggestion.trail;
    final units = UnitsScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B24352C),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('trail-${trail.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trail.name,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            distanceLabel == null
                                ? trail.area
                                : '${trail.area} · $distanceLabel',
                            style: const TextStyle(
                              color: Color(0xFF777E79),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TrailFitBadge(fit: suggestion.fit),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  trail.elevationKnown
                      ? '${trail.distanceLabel(units)} · '
                            '${trail.ascentLabel(units)} ascent · '
                            '${trail.durationLabel}'
                      : '${trail.distanceLabel(units)} · ascent unknown · '
                            '${trail.durationLabel}',
                  style: const TextStyle(
                    color: Color(0xFF5F6862),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  trail.summary,
                  style: const TextStyle(
                    color: Color(0xFF68716B),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                if (planned) ...[
                  const SizedBox(height: 7),
                  const Text(
                    'PLANNED ROUTE',
                    style: TextStyle(
                      color: _forest,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailDetails extends StatelessWidget {
  const _TrailDetails({
    required this.suggestion,
    required this.conditions,
    required this.planned,
    required this.onClose,
  });

  final TrailSuggestion suggestion;
  final TrailConditions conditions;
  final bool planned;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final trail = suggestion.trail;
    final units = UnitsScope.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DEDA),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    trail.name,
                    style: const TextStyle(
                      color: _ink,
                      fontFamily: 'Georgia',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TrailFitBadge(fit: suggestion.fit),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              trail.area,
              style: const TextStyle(color: Color(0xFF777E79), fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text(
              trail.summary,
              style: const TextStyle(
                color: Color(0xFF3F4742),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _DetailStat(
                  label: 'Distance',
                  value: trail.distanceLabel(units),
                ),
                _DetailStat(
                  label: 'Ascent',
                  value: trail.elevationKnown
                      ? trail.ascentLabel(units)
                      : 'Unknown',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _DetailStat(label: 'Time', value: trail.durationLabel),
                _DetailStat(
                  label: 'High point',
                  value: trail.elevationKnown
                      ? trail.highPointLabel(units)
                      : 'Unknown',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              trailFitReason(suggestion.fit),
              key: const Key('trail-fit-reason'),
              style: const TextStyle(
                color: Color(0xFF5F6862),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'GOOD TO KNOW',
              style: TextStyle(
                color: _forest,
                fontWeight: FontWeight.w800,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            for (final note in trail.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: SizedBox(
                        width: 5,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _forest,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note,
                        style: const TextStyle(
                          color: Color(0xFF68716B),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Fit judged from your ability and ${conditions.label.toLowerCase()} '
              'conditions. The app does not know about closures or the weather '
              'on the day.',
              style: const TextStyle(color: Color(0xFF858B86), fontSize: 10),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: planned
                  ? OutlinedButton.icon(
                      key: const Key('unplan-trail'),
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Remove from plan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _forest,
                        side: const BorderSide(color: Color(0xFFCADCD1)),
                      ),
                    )
                  : FilledButton.icon(
                      key: const Key('plan-trail'),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.flag_rounded, size: 18),
                      label: const Text('Plan this trail'),
                      style: FilledButton.styleFrom(backgroundColor: _forest),
                    ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(foregroundColor: _forest),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF858B86),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
