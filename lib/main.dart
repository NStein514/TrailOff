import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:share_plus/share_plus.dart';

import 'hike_navigation.dart';
import 'hike_recording.dart';
import 'constellation.dart';
import 'offline_map.dart';
import 'packing_checklist.dart';
import 'route_recommendations.dart';
import 'route_tracking.dart';
import 'trail_answers.dart';
import 'trail_catalogue.dart';
import 'trail_catalogue_page.dart';
import 'trail_discovery.dart';
import 'trail_fit_badge.dart';
import 'trail_geometry.dart';
import 'trail_guide.dart';
import 'trail_plan.dart';
import 'trip_album_page.dart';
import 'trip_photos.dart';

void main() {
  runApp(const TrailOffApp());
}

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

class TrailOffApp extends StatelessWidget {
  const TrailOffApp({
    super.key,
    this.locationSource,
    this.historyStore,
    this.offlineMapRepository,
    this.offlineMapSupported,
    this.nativeMapSupported,
    this.trailGuideStore,
    this.trailPlanStore,
    this.tripPhotoStore,
    this.tripPhotoPicker,
    this.trailDiscoverySource,
    this.discoveredTrailStore,
    this.trailSearchLocation,
  });

  final HikeLocationSource? locationSource;
  final HikeHistoryStore? historyStore;
  final OfflineMapRepository? offlineMapRepository;
  final bool? offlineMapSupported;
  final bool? nativeMapSupported;
  final TrailGuideStore? trailGuideStore;
  final TrailPlanStore? trailPlanStore;
  final TripPhotoStore? tripPhotoStore;
  final TripPhotoPicker? tripPhotoPicker;
  final TrailDiscoverySource? trailDiscoverySource;
  final DiscoveredTrailStore? discoveredTrailStore;
  final TrailSearchLocation? trailSearchLocation;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrailOff',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(seedColor: _forest),
        fontFamily: 'Roboto',
      ),
      home: HikeDashboard(
        locationSource: locationSource,
        historyStore: historyStore,
        offlineMapRepository: offlineMapRepository,
        offlineMapSupported: offlineMapSupported,
        nativeMapSupported: nativeMapSupported,
        trailGuideStore: trailGuideStore,
        trailPlanStore: trailPlanStore,
        tripPhotoStore: tripPhotoStore,
        tripPhotoPicker: tripPhotoPicker,
        trailDiscoverySource: trailDiscoverySource,
        discoveredTrailStore: discoveredTrailStore,
        trailSearchLocation: trailSearchLocation,
      ),
    );
  }
}

class HikeDashboard extends StatefulWidget {
  const HikeDashboard({
    super.key,
    this.locationSource,
    this.historyStore,
    this.offlineMapRepository,
    this.offlineMapSupported,
    this.nativeMapSupported,
    this.trailGuideStore,
    this.trailPlanStore,
    this.tripPhotoStore,
    this.tripPhotoPicker,
    this.trailDiscoverySource,
    this.discoveredTrailStore,
    this.trailSearchLocation,
  });

  final HikeLocationSource? locationSource;
  final HikeHistoryStore? historyStore;
  final OfflineMapRepository? offlineMapRepository;
  final bool? offlineMapSupported;
  final bool? nativeMapSupported;
  final TrailGuideStore? trailGuideStore;
  final TrailPlanStore? trailPlanStore;
  final TripPhotoStore? tripPhotoStore;
  final TripPhotoPicker? tripPhotoPicker;
  final TrailDiscoverySource? trailDiscoverySource;
  final DiscoveredTrailStore? discoveredTrailStore;
  final TrailSearchLocation? trailSearchLocation;

  @override
  State<HikeDashboard> createState() => _HikeDashboardState();
}

class _HikeDashboardState extends State<HikeDashboard> {
  late final HikeLocationSource _locationSource;
  late final HikeHistoryStore _historyStore;
  StreamSubscription<HikePoint>? _locationSubscription;
  Timer? _elapsedTimer;
  final List<HikePoint> _recordedPoints = [];
  List<SavedHike> _savedHikes = [];
  DateTime? _startedAt;
  HikePoint? _latestPoint;
  int _elapsedSeconds = 0;
  double _distanceMeters = 0;
  double _elevationGainMeters = 0;
  bool _isRecording = false;
  bool _hasRecordedSession = false;
  bool _isLoadingHistory = true;
  HikingAbility _hikingAbility = HikingAbility.beginner;
  TrailConditions _trailConditions = TrailConditions.dry;
  bool _mapSaved = false;
  bool _mapDownloading = false;
  double _mapDownloadProgress = 0;
  int _mapDownloadedBytes = 0;
  int? _offlineRegionId;
  String? _plannedTrailId;
  bool _planLoaded = false;

  /// Distance from the planned line when the hiker is off route, otherwise
  /// null. Kept with hysteresis so the warning does not flicker.
  double? _offRouteMeters;
  bool get _offlineMapSupported =>
      widget.offlineMapSupported ?? _isMobileTarget;
  bool get _nativeMapSupported => widget.nativeMapSupported ?? _maplibreTarget;
  bool get _isMobileTarget =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The platforms where MapLibre draws the real map. Offline downloads stay
  /// mobile-only, but the map itself also runs in the web build; the painted
  /// fallback is only for platforms the plugin has no implementation for.
  bool get _maplibreTarget => kIsWeb || _isMobileTarget;

  late final OfflineMapRepository _offlineMapRepository;
  late final TrailPlanStore _planStore;
  late final TripPhotoStore _photoStore;
  late final TripPhotoPicker _photoPicker;
  late final DiscoveredTrailStore _discoveryStore;

  /// Photo totals per saved trip, keyed like the stored photos.
  Map<String, int> _photoCounts = const {};

  /// Trails found near the hiker, kept so a plan made from one still resolves
  /// after a restart.
  List<Trail> _discoveredTrails = const [];

  Trail? get _plannedTrail => plannedTrail([
    ...sampleTrailCatalogue,
    ..._discoveredTrails,
  ], _plannedTrailId);

  OfflineArea get _offlineArea {
    final trail = _plannedTrail;
    return trail == null ? defaultOfflineArea : OfflineArea.forTrail(trail);
  }

  @override
  void initState() {
    super.initState();
    _locationSource = widget.locationSource ?? GeolocatorHikeLocationSource();
    _historyStore = widget.historyStore ?? SharedPreferencesHikeHistoryStore();
    _offlineMapRepository =
        widget.offlineMapRepository ?? MapLibreOfflineMapRepository();
    _planStore = widget.trailPlanStore ?? SharedPreferencesTrailPlanStore();
    _photoStore = widget.tripPhotoStore ?? FileTripPhotoStore();
    _photoPicker = widget.tripPhotoPicker ?? ImagePickerTripPhotoPicker();
    _discoveryStore =
        widget.discoveredTrailStore ?? SharedPreferencesDiscoveredTrailStore();
    _loadHistory();
    _loadPlan();
    _loadPhotoCounts();
    _loadDiscoveredTrails();
  }

  Future<void> _loadDiscoveredTrails() async {
    List<Trail> trails;
    try {
      trails = await _discoveryStore.load();
    } catch (_) {
      trails = const [];
    }
    if (!mounted) return;
    setState(() => _discoveredTrails = trails);
    // A plan made from a found trail could not be resolved until the stored
    // trails arrived, so its saved map state is re-checked now.
    if (_planLoaded && _plannedTrailId != null) await _loadOfflineRegion();
  }

  Future<void> _loadPhotoCounts() async {
    Map<String, int> counts;
    try {
      final photos = await _photoStore.loadAll();
      counts = <String, int>{};
      for (final photo in photos) {
        counts[photo.tripKey] = (counts[photo.tripKey] ?? 0) + 1;
      }
    } catch (_) {
      counts = const {};
    }
    if (!mounted) return;
    setState(() => _photoCounts = counts);
  }

  /// Captures a photo into the trip currently being recorded. The trip key is
  /// the session's start time, which is exactly the key the saved hike will
  /// use, so the photo appears in its album as soon as the hike is saved.
  Future<void> _takeHikePhoto() async {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    final trail = _plannedTrail;
    try {
      final picked = await _photoPicker.pick(TripPhotoSource.camera);
      if (picked == null) return;
      await _photoStore.add(
        tripKey: tripKeyFor(startedAt),
        photo: picked,
        trailId: trail?.id,
        trailName: trail?.name,
      );
      await _loadPhotoCounts();
      if (!mounted) return;
      _showMessage('Photo saved with this hike.');
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'The photo could not be taken. Check camera access and try again.',
      );
    }
  }

  Future<void> _openAlbum(SavedHike hike) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TripAlbumPage(
          trip: hike,
          store: _photoStore,
          picker: widget.tripPhotoPicker,
        ),
      ),
    );
    if (!mounted) return;
    await _loadPhotoCounts();
  }

  Future<void> _loadPlan() async {
    String? id;
    try {
      id = await _planStore.loadPlannedTrailId();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Your planned trail could not be loaded.');
      return;
    }
    if (!mounted) return;
    final changed = !_planLoaded || id != _plannedTrailId;
    setState(() {
      _planLoaded = true;
      _plannedTrailId = id;
      if (changed) {
        _offRouteMeters = null;
        _offlineRegionId = null;
        _mapSaved = false;
        _mapDownloading = false;
        _mapDownloadProgress = 0;
        _mapDownloadedBytes = 0;
      }
    });
    if (changed) await _loadOfflineRegion();
  }

  Future<void> _clearPlan() async {
    try {
      await _planStore.clear();
    } catch (_) {
      if (!mounted) return;
      _showMessage('The planned trail could not be cleared.');
      return;
    }
    if (!mounted) return;
    _showMessage('Planned trail cleared.');
    await _loadPlan();
  }

  Future<void> _openCatalogue() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrailCataloguePage(
          ability: _hikingAbility,
          conditions: _trailConditions,
          planStore: _planStore,
          discoverySource: widget.trailDiscoverySource,
          discoveredTrailStore: _discoveryStore,
          searchLocation: widget.trailSearchLocation,
        ),
      ),
    );
    if (!mounted) return;
    // A route found near the hiker may be the one they planned, so the saved
    // trails are re-read before the plan is resolved.
    await _loadDiscoveredTrails();
    if (!mounted) return;
    _loadPlan();
  }

  Future<void> _loadOfflineRegion() async {
    if (!_offlineMapSupported) return;
    final area = _offlineArea;
    try {
      final region = await _offlineMapRepository.findRegion(area);
      if (!mounted || area.id != _offlineArea.id) return;
      setState(() {
        _offlineRegionId = region?.id;
        _mapSaved = region?.isComplete ?? false;
      });
    } catch (_) {
      // Keep the online map available if the native offline store is unavailable.
    }
  }

  Future<void> _downloadOfflineMap() async {
    if (!_offlineMapSupported) {
      _showMessage(
        'Offline map downloads are available in the Android and iOS apps.',
      );
      return;
    }
    final area = _offlineArea;
    setState(() {
      _mapDownloading = true;
      _mapDownloadProgress = 0;
      _mapDownloadedBytes = 0;
    });
    try {
      final regionId = await _offlineMapRepository.downloadRegion(
        area: area,
        onProgress: (progress, bytes) {
          if (!mounted || area.id != _offlineArea.id) return;
          setState(() {
            _mapDownloadProgress = progress.clamp(0.0, 1.0);
            _mapDownloadedBytes = bytes;
          });
        },
        onComplete: () {
          if (!mounted || area.id != _offlineArea.id) return;
          setState(() {
            _mapDownloading = false;
            _mapSaved = true;
          });
          _showMessage('${area.name} is ready for offline use.');
        },
        onError: (message) {
          if (!mounted || area.id != _offlineArea.id) return;
          setState(() => _mapDownloading = false);
          _showMessage('Map download failed: $message');
        },
      );
      if (!mounted || area.id != _offlineArea.id) return;
      setState(() => _offlineRegionId = regionId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _mapDownloading = false);
      _showMessage('Map download failed: $error');
    }
  }

  Future<void> _deleteOfflineMap() async {
    final regionId = _offlineRegionId;
    if (regionId == null) return;
    try {
      await _offlineMapRepository.deleteRegion(regionId);
      if (!mounted) return;
      setState(() {
        _offlineRegionId = null;
        _mapSaved = false;
        _mapDownloadProgress = 0;
      });
      _showMessage('Offline map removed from this device.');
    } catch (error) {
      _showMessage('The offline map could not be deleted: $error');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final hikes = await _historyStore.load();
      if (!mounted) return;
      setState(() {
        _savedHikes = hikes;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
      _showMessage('Your saved hikes could not be loaded.');
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

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _finishRecording();
      return;
    }

    try {
      await _locationSource.prepare();
      final startedAt = DateTime.now();
      setState(() {
        _recordedPoints.clear();
        _latestPoint = null;
        _distanceMeters = 0;
        _elevationGainMeters = 0;
        _elapsedSeconds = 0;
        _startedAt = startedAt;
        _isRecording = true;
        _hasRecordedSession = true;
        _offRouteMeters = null;
      });
      _locationSubscription = _locationSource.positions.listen(
        _onLocation,
        onError: (Object error) {
          if (mounted) _showMessage('GPS tracking stopped: $error');
          if (_isRecording) _finishRecording();
        },
      );
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final started = _startedAt;
        if (!mounted || started == null) return;
        setState(
          () => _elapsedSeconds = DateTime.now().difference(started).inSeconds,
        );
      });
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _onLocation(HikePoint point) {
    if (!mounted || !_isRecording || point.accuracy > 40) return;
    final previous = _recordedPoints.isEmpty ? null : _recordedPoints.last;
    final segment = previous == null
        ? 0.0
        : distanceBetweenPoints(previous, point);
    if (previous != null && segment < 3) return;

    final trail = _plannedTrail;
    final match = trail == null
        ? null
        : matchRoute(
            route: trail.route,
            latitude: point.latitude,
            longitude: point.longitude,
          );
    final offRoute = match == null
        ? null
        : offRouteDistanceAfter(
            distanceMeters: match.distanceMeters,
            previous: _offRouteMeters,
          );

    setState(() {
      if (previous != null) _distanceMeters += segment;
      if (previous != null) {
        final elevationChange = point.altitude - previous.altitude;
        if (elevationChange > 0) _elevationGainMeters += elevationChange;
      }
      _recordedPoints.add(point);
      _latestPoint = point;
      _offRouteMeters = offRoute;
    });
  }

  Future<void> _finishRecording() async {
    final startedAt = _startedAt;
    if (!_isRecording || startedAt == null) return;
    final finishedAt = DateTime.now();
    final recordedPoints = List<HikePoint>.unmodifiable(_recordedPoints);
    final trail = _plannedTrail;
    final distanceMeters = _distanceMeters;
    final elevationGainMeters = _elevationGainMeters;
    _elapsedTimer?.cancel();
    final locationSubscription = _locationSubscription;
    _locationSubscription = null;
    setState(() {
      _isRecording = false;
      _elapsedSeconds = finishedAt.difference(startedAt).inSeconds;
      _offRouteMeters = null;
    });
    if (locationSubscription != null) unawaited(locationSubscription.cancel());

    final sessionPhotoCount = _photoCounts[tripKeyFor(startedAt)] ?? 0;
    if (recordedPoints.isEmpty && sessionPhotoCount == 0) {
      _showMessage('No GPS points were received, so this hike was not saved.');
      return;
    }

    final hike = SavedHike(
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationSeconds: _elapsedSeconds,
      distanceMeters: distanceMeters,
      elevationGainMeters: elevationGainMeters,
      points: recordedPoints,
      plannedTrailId: trail?.id,
      plannedTrailName: trail?.name,
    );
    try {
      await _historyStore.save(hike);
      if (!mounted) return;
      setState(() => _savedHikes = [hike, ..._savedHikes]);
      _showMessage(
        recordedPoints.isEmpty
            ? 'No GPS points were received, so this hike was saved with its photos only.'
            : 'Hike saved with ${hike.points.length} GPS points.',
      );
    } catch (_) {
      _showMessage('This hike could not be saved on your device.');
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _Wordmark(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.travel_explore, size: 18),
                          label: const Text('Discover trails'),
                          onPressed: _openCatalogue,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Constellation'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ConstellationPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Track your progress\nand stay on trail',
                    style: TextStyle(
                      color: _ink,
                      fontFamily: 'Georgia',
                      fontSize: 35,
                      height: 1.08,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TrailMap(
                    points: _recordedPoints,
                    isRecording: _isRecording,
                    showNativeMap: _nativeMapSupported,
                    trail: _plannedTrail,
                  ),
                  _OfflineMapButton(
                    saved: _mapSaved,
                    downloading: _mapDownloading,
                    progress: _mapDownloadProgress,
                    downloadedBytes: _mapDownloadedBytes,
                    supported: _offlineMapSupported,
                    onPressed: _mapSaved
                        ? _deleteOfflineMap
                        : _downloadOfflineMap,
                  ),
                  const SizedBox(height: 12),
                  _HikeSummary(
                    onRecordPressed: _toggleRecording,
                    isRecording: _isRecording,
                    hasRecordedSession: _hasRecordedSession,
                    elapsedSeconds: _elapsedSeconds,
                    distanceMeters: _distanceMeters,
                    elevationGainMeters: _elevationGainMeters,
                    latestPoint: _latestPoint,
                    points: _recordedPoints,
                    trail: _plannedTrail,
                    offRouteMeters: _offRouteMeters,
                    photoCount: _startedAt == null
                        ? 0
                        : (_photoCounts[tripKeyFor(_startedAt!)] ?? 0),
                    onTakePhoto: _takeHikePhoto,
                  ),
                  const SizedBox(height: 12),
                  _PlannedTrail(
                    trail: _plannedTrail,
                    ability: _hikingAbility,
                    conditions: _trailConditions,
                    onBrowse: _openCatalogue,
                    onClear: _clearPlan,
                  ),
                  const SizedBox(height: 20),
                  _RouteAdvisor(
                    hikes: _savedHikes,
                    ability: _hikingAbility,
                    conditions: _trailConditions,
                    onAbilityChanged: (value) =>
                        setState(() => _hikingAbility = value),
                    onConditionsChanged: (value) =>
                        setState(() => _trailConditions = value),
                  ),
                  const SizedBox(height: 12),
                  PackingChecklist(
                    ability: _hikingAbility,
                    conditions: _trailConditions,
                    trail: _plannedTrail,
                  ),
                  const SizedBox(height: 12),
                  TrailAnswers(store: widget.trailGuideStore),
                  const SizedBox(height: 20),
                  _HikeHistory(
                    hikes: _savedHikes,
                    isLoading: _isLoadingHistory,
                    photoCounts: _photoCounts,
                    onOpenAlbum: _openAlbum,
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 29,
          height: 29,
          decoration: const BoxDecoration(
            color: _forest,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.terrain_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'TRAILOFF',
          style: TextStyle(
            color: _forest,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.1,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            children: [
              Icon(Icons.wb_sunny_outlined, color: _forest, size: 15),
              SizedBox(width: 5),
              Text(
                '12°',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              SizedBox(width: 4),
              Text(
                'Clear',
                style: TextStyle(color: Color(0xFF777E79), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrailMap extends StatelessWidget {
  const _TrailMap({
    required this.points,
    required this.isRecording,
    required this.showNativeMap,
    required this.trail,
  });

  final List<HikePoint> points;
  final bool isRecording;
  final bool showNativeMap;
  final Trail? trail;

  @override
  Widget build(BuildContext context) {
    final planned = trail;
    // The drawn labels and demo route describe the tour, so they are hidden
    // once a different trail is planned.
    final tour = planned == null || planned.id == defaultOfflineArea.id;
    final route = planned?.route ?? const <TrailPoint>[];
    final bounds = route.isEmpty ? null : trailBounds(route);
    final centerLatitude =
        bounds?.centerLatitude ?? planned?.trailheadLatitude ?? 42.695;
    final centerLongitude =
        bounds?.centerLongitude ?? planned?.trailheadLongitude ?? 0.515;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 338,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showNativeMap)
              _NativeTrailMap(
                points: List.unmodifiable(points),
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                route: route,
                showDemoRoute: tour,
              )
            else
              CustomPaint(
                painter: _TopoMapPainter(
                  points: List.unmodifiable(points),
                  route: route,
                  showDemoRoute: tour,
                ),
              ),
            if (isRecording)
              Positioned(
                left: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 7,
                        height: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFB5483E),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Recording GPS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (planned != null)
              Positioned(
                left: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flag_rounded, color: _forest, size: 14),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          planned.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // The place names and pins are painted-map decorations at fixed
            // pixels, so they only belong on the fallback drawing; over the
            // real map they would point at nothing.
            if (tour && !showNativeMap) ...[
              const Positioned(
                left: 20,
                top: 92,
                child: _MapLabel('2,650 m', size: 11),
              ),
              const Positioned(
                left: 42,
                bottom: 112,
                child: _MapLabel('de Montarqué', size: 11),
              ),
              const Positioned(
                right: 49,
                top: 153,
                child: _MapLabel('Refuge du Portillon', size: 11),
              ),
              Positioned(
                right: 30,
                bottom: 51,
                child: Transform.rotate(
                  angle: -0.22,
                  child: const Text(
                    'Lac du Portillon',
                    style: TextStyle(
                      color: Color(0xFF27799D),
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 25,
                top: 125,
                child: _MapPin(color: _forest, icon: Icons.terrain_rounded),
              ),
              const Positioned(
                right: 38,
                top: 91,
                child: _MapPin(
                  color: Color(0xFFF2A83B),
                  icon: Icons.home_rounded,
                ),
              ),
              const Positioned(
                right: 27,
                top: 20,
                child: _MapPin(
                  color: Color(0xFF62B8E4),
                  icon: Icons.water_rounded,
                  small: true,
                ),
              ),
            ],
            // The map draws its own compass, and the live position comes from
            // the GPS fixes rather than a dot pinned to the card.
            if (!showNativeMap)
              Positioned(
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.navigation_rounded, color: _forest, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'North',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel(this.text, {this.size = 12});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: const Color(0xFF596D55),
      fontSize: size,
      fontWeight: FontWeight.w600,
      shadows: const [Shadow(color: Colors.white, blurRadius: 5)],
    ),
  );
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.icon, this.small = false});

  final Color color;
  final IconData icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 38.0 : 43.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33808080),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: small ? 21 : 23),
    );
  }
}

class _TopoMapPainter extends CustomPainter {
  const _TopoMapPainter({
    required this.points,
    required this.route,
    required this.showDemoRoute,
  });

  final List<HikePoint> points;
  final List<TrailPoint> route;
  final bool showDemoRoute;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE5E8D7), Color(0xFFDCE7D8), Color(0xFFEDEBDD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );

    final water = Path()
      ..moveTo(size.width * 0.57, size.height * 0.62)
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.54,
        size.width * 0.76,
        size.height * 0.56,
        size.width * 0.82,
        size.height * 0.47,
      )
      ..cubicTo(
        size.width * 0.91,
        size.height * 0.39,
        size.width * 0.93,
        size.height * 0.51,
        size.width,
        size.height * 0.44,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.49, size.height)
      ..cubicTo(
        size.width * 0.52,
        size.height * 0.85,
        size.width * 0.47,
        size.height * 0.75,
        size.width * 0.57,
        size.height * 0.62,
      )
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFF78CDE6));
    canvas.drawPath(
      water,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF46A8C8).withValues(alpha: 0.8),
    );

    final contours = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF78846B).withValues(alpha: 0.45);
    for (var i = 0; i < 15; i++) {
      final y = size.height * (i / 15);
      final offset = (i % 3 - 1) * 13.0;
      final contour = Path()
        ..moveTo(-12, y + offset)
        ..cubicTo(
          size.width * 0.24,
          y - 31 + offset,
          size.width * 0.34,
          y + 38 - offset,
          size.width * 0.60,
          y + 7,
        )
        ..cubicTo(
          size.width * 0.74,
          y - 18,
          size.width * 0.82,
          y + 30,
          size.width + 12,
          y - 8 + offset,
        );
      canvas.drawPath(contour, contours);
    }

    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD2AC3D).withValues(alpha: 0.9);
    final paths = [
      Path()
        ..moveTo(-5, size.height * 0.83)
        ..cubicTo(
          size.width * 0.22,
          size.height * 0.75,
          size.width * 0.21,
          size.height * 0.64,
          size.width * 0.47,
          size.height * 0.58,
        )
        ..cubicTo(
          size.width * 0.72,
          size.height * 0.48,
          size.width * 0.8,
          size.height * 0.33,
          size.width,
          size.height * 0.29,
        ),
      Path()
        ..moveTo(size.width * 0.05, size.height * 0.35)
        ..cubicTo(
          size.width * 0.25,
          size.height * 0.31,
          size.width * 0.31,
          size.height * 0.42,
          size.width * 0.42,
          size.height * 0.36,
        )
        ..cubicTo(
          size.width * 0.61,
          size.height * 0.26,
          size.width * 0.74,
          size.height * 0.34,
          size.width * 0.91,
          size.height * 0.18,
        ),
    ];
    for (final path in paths) {
      canvas.drawPath(path, road);
    }

    if (points.isEmpty && route.isEmpty && showDemoRoute) {
      final route = Path()
        ..moveTo(size.width * 0.02, size.height * 0.37)
        ..cubicTo(
          size.width * 0.16,
          size.height * 0.34,
          size.width * 0.13,
          size.height * 0.54,
          size.width * 0.28,
          size.height * 0.51,
        )
        ..cubicTo(
          size.width * 0.39,
          size.height * 0.48,
          size.width * 0.34,
          size.height * 0.68,
          size.width * 0.44,
          size.height * 0.68,
        )
        ..cubicTo(
          size.width * 0.51,
          size.height * 0.68,
          size.width * 0.49,
          size.height * 0.58,
          size.width * 0.57,
          size.height * 0.62,
        );
      canvas.drawPath(
        route,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.86),
      );
      canvas.drawPath(
        route,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFC66D39),
      );
    }

    // The planned route and the live track share one projection, so a GPS track
    // sits in the same frame as the line it was meant to follow.
    final latitudes = [
      ...route.map((point) => point.latitude),
      ...points.map((point) => point.latitude),
    ];
    final longitudes = [
      ...route.map((point) => point.longitude),
      ...points.map((point) => point.longitude),
    ];
    if (latitudes.isNotEmpty) {
      final minLatitude = latitudes.reduce((a, b) => a < b ? a : b);
      final maxLatitude = latitudes.reduce((a, b) => a > b ? a : b);
      final minLongitude = longitudes.reduce((a, b) => a < b ? a : b);
      final maxLongitude = longitudes.reduce((a, b) => a > b ? a : b);
      final latitudeRange = maxLatitude - minLatitude;
      final longitudeRange = maxLongitude - minLongitude;
      Offset mapOffset(double latitude, double longitude) => Offset(
        size.width *
            (0.12 +
                0.76 *
                    (longitudeRange == 0
                        ? 0.5
                        : (longitude - minLongitude) / longitudeRange)),
        size.height *
            (0.12 +
                0.76 *
                    (latitudeRange == 0
                        ? 0.5
                        : 1 - (latitude - minLatitude) / latitudeRange)),
      );

      if (route.length > 1) {
        final routePath = Path();
        for (var i = 0; i < route.length; i++) {
          final offset = mapOffset(route[i].latitude, route[i].longitude);
          if (i == 0) {
            routePath.moveTo(offset.dx, offset.dy);
          } else {
            routePath.lineTo(offset.dx, offset.dy);
          }
        }
        canvas.drawPath(
          routePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white.withValues(alpha: 0.86),
        );
        canvas.drawPath(
          routePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFC66D39),
        );
        final start = mapOffset(route.first.latitude, route.first.longitude);
        canvas.drawCircle(start, 7, Paint()..color = Colors.white);
        canvas.drawCircle(start, 4.5, Paint()..color = const Color(0xFF2F5D45));
      }

      if (points.length > 1) {
        final track = Path();
        for (var i = 0; i < points.length; i++) {
          final offset = mapOffset(points[i].latitude, points[i].longitude);
          if (i == 0) {
            track.moveTo(offset.dx, offset.dy);
          } else {
            track.lineTo(offset.dx, offset.dy);
          }
        }
        canvas.drawPath(
          track,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF0878F9),
        );
        final current = mapOffset(points.last.latitude, points.last.longitude);
        canvas.drawCircle(current, 7, Paint()..color = Colors.white);
        canvas.drawCircle(current, 4, Paint()..color = const Color(0xFF0878F9));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TopoMapPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.route != route ||
      oldDelegate.showDemoRoute != showDemoRoute;
}

class _NativeTrailMap extends StatefulWidget {
  const _NativeTrailMap({
    required this.points,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.route,
    required this.showDemoRoute,
  });

  final List<HikePoint> points;
  final double centerLatitude;
  final double centerLongitude;
  final List<TrailPoint> route;
  final bool showDemoRoute;

  @override
  State<_NativeTrailMap> createState() => _NativeTrailMapState();
}

class _NativeTrailMapState extends State<_NativeTrailMap> {
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _routeLine;
  maplibre.Line? _trackLine;
  maplibre.Circle? _positionCircle;
  bool _styleLoaded = false;

  /// What is already on the map, so a rebuild that changed nothing on the
  /// ground does not tear the annotations down and add them back.
  List<TrailPoint>? _drawnRoute;
  bool? _drawnDemoRoute;
  int _drawnPointCount = 0;
  DateTime? _drawnPointTime;

  /// Annotation changes are awaited one at a time; two overlapping updates
  /// would remove a line that the other one is still adding.
  Future<void> _annotations = Future<void>.value();

  @override
  Widget build(BuildContext context) => maplibre.MapLibreMap(
    initialCameraPosition: maplibre.CameraPosition(
      target: maplibre.LatLng(widget.centerLatitude, widget.centerLongitude),
      zoom: _fitZoom(),
    ),
    styleString: tourOfflineMapStyle,
    compassEnabled: true,
    myLocationEnabled: false,
    logoEnabled: false,
    attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
    onMapCreated: (controller) {
      _controller = controller;
      // Whichever of the two callbacks arrives second does the drawing.
      _scheduleAnnotations();
    },
    onStyleLoadedCallback: _drawKnownTrail,
  );

  void _drawKnownTrail() {
    if (_styleLoaded) return;
    _styleLoaded = true;
    _scheduleAnnotations();
  }

  @override
  void didUpdateWidget(covariant _NativeTrailMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final centerMoved =
        oldWidget.centerLatitude != widget.centerLatitude ||
        oldWidget.centerLongitude != widget.centerLongitude;
    final routeChanged = !identical(oldWidget.route, widget.route);
    final trackStarted =
        oldWidget.points.isEmpty && widget.points.isNotEmpty;
    if (centerMoved || routeChanged) {
      _recenter();
    }
    // With no plan the map has no route to frame, so the first fix becomes the
    // frame instead of leaving the view over the demo area.
    if (trackStarted && widget.route.length < 2) {
      _recenterOnLatestPoint();
    }
    if (_styleLoaded &&
        (routeChanged ||
            oldWidget.showDemoRoute != widget.showDemoRoute ||
            _trackChanged(oldWidget.points, widget.points))) {
      _scheduleAnnotations();
    }
  }

  /// Points are appended and the parent rebuilds on every tick, so the length
  /// and the newest timestamp say whether the track really moved.
  bool _trackChanged(List<HikePoint> previous, List<HikePoint> current) {
    if (previous.length != current.length) return true;
    if (current.isEmpty) return false;
    return previous.last.timestamp != current.last.timestamp;
  }

  /// Each degree of a route needs roughly `320 / span` pixels, which is a zoom
  /// of log2 over the world width of 256 px per level.
  double _fitZoom() {
    if (widget.route.length < 2) return 12;
    final bounds = trailBounds(widget.route);
    final span = math.max(bounds.latitudeSpan, bounds.longitudeSpan);
    if (span <= 0) return 13;
    final zoom = math.log(360 * 320 / (256 * span)) / math.ln2;
    return zoom.clamp(9.0, 15.0);
  }

  Future<void> _recenter() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(widget.centerLatitude, widget.centerLongitude),
        _fitZoom(),
      ),
    );
  }

  Future<void> _recenterOnLatestPoint() async {
    final controller = _controller;
    if (controller == null || widget.points.isEmpty) return;
    final point = widget.points.last;
    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(point.latitude, point.longitude),
        15,
      ),
    );
  }

  void _scheduleAnnotations() {
    _annotations = _annotations.then((_) => _updateAnnotations()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      // A failed draw must not break the queue, or one bad frame would stop
      // every later route and track update from reaching the map.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'trailoff',
          context: ErrorDescription('while drawing the trail map'),
        ),
      );
    });
  }

  /// Draws the planned line and the live track as separate layers, and marks
  /// the latest fix. The track used to replace the route, so planning a trail
  /// and then recording lost the line it was meant to follow.
  Future<void> _updateAnnotations() async {
    final controller = _controller;
    if (controller == null || !_styleLoaded || !mounted) return;

    final points = widget.points;
    final demoRoute = widget.showDemoRoute && points.isEmpty;
    if (!identical(_drawnRoute, widget.route) || _drawnDemoRoute != demoRoute) {
      final previous = _routeLine;
      if (previous != null) await controller.removeLine(previous);
      _routeLine = null;
      final geometry = _routeGeometry(demoRoute);
      if (geometry.length > 1) {
        _routeLine = await controller.addLine(
          maplibre.LineOptions(
            geometry: geometry,
            lineColor: '#C66D39',
            lineWidth: 4,
            lineOpacity: 0.95,
            lineJoin: 'round',
          ),
        );
      }
      _drawnRoute = widget.route;
      _drawnDemoRoute = demoRoute;
    }

    final latest = points.isEmpty ? null : points.last;
    if (points.length == _drawnPointCount &&
        latest?.timestamp == _drawnPointTime) {
      return;
    }
    final previousTrack = _trackLine;
    if (previousTrack != null) await controller.removeLine(previousTrack);
    _trackLine = null;
    // A single fix is not a line: MapLibre rejects a one-position LineString.
    if (points.length > 1) {
      _trackLine = await controller.addLine(
        maplibre.LineOptions(
          geometry: [
            for (final point in points)
              maplibre.LatLng(point.latitude, point.longitude),
          ],
          lineColor: '#0878F9',
          lineWidth: 4,
          lineOpacity: 0.95,
          lineJoin: 'round',
        ),
      );
    }
    final previousCircle = _positionCircle;
    if (previousCircle != null) await controller.removeCircle(previousCircle);
    _positionCircle = null;
    if (latest != null) {
      _positionCircle = await controller.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(latest.latitude, latest.longitude),
          circleRadius: 6,
          circleColor: '#0878F9',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );
    }
    _drawnPointCount = points.length;
    _drawnPointTime = latest?.timestamp;
  }

  List<maplibre.LatLng> _routeGeometry(bool demoRoute) {
    final route = widget.route;
    if (route.length > 1) {
      return [
        for (final point in route)
          maplibre.LatLng(point.latitude, point.longitude),
      ];
    }
    if (!demoRoute) return const [];
    return const [
      maplibre.LatLng(42.686, 0.486),
      maplibre.LatLng(42.691, 0.497),
      maplibre.LatLng(42.688, 0.506),
      maplibre.LatLng(42.699, 0.512),
      maplibre.LatLng(42.703, 0.526),
    ];
  }
}

class _OfflineMapButton extends StatelessWidget {
  const _OfflineMapButton({
    required this.saved,
    required this.downloading,
    required this.progress,
    required this.downloadedBytes,
    required this.supported,
    required this.onPressed,
  });

  final bool saved;
  final bool downloading;
  final double progress;
  final int downloadedBytes;
  final bool supported;
  final VoidCallback onPressed;

  String get _downloadSize {
    if (downloadedBytes <= 0) return 'Preparing map…';
    if (downloadedBytes < 1024 * 1024) {
      return '${(downloadedBytes / 1024).round()} KB downloaded';
    }
    return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB downloaded';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _ink,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: InkWell(
        child: SizedBox(
          height: 64,
          child: downloading
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.downloading_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _downloadSize,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: progress == 0 ? null : progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: Colors.white24,
                        color: const Color(0xFF95D7B4),
                      ),
                    ],
                  ),
                )
              : InkWell(
                  onTap: onPressed,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        saved
                            ? 'Map saved · tap to remove'
                            : supported
                            ? 'Download map for offline use'
                            : 'Offline maps: mobile app only',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        saved
                            ? Icons.check_circle_outline_rounded
                            : supported
                            ? Icons.wifi_off_rounded
                            : Icons.info_outline_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PlannedTrail extends StatelessWidget {
  const _PlannedTrail({
    required this.trail,
    required this.ability,
    required this.conditions,
    required this.onBrowse,
    required this.onClear,
  });

  final Trail? trail;
  final HikingAbility ability;
  final TrailConditions conditions;
  final VoidCallback onBrowse;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final planned = trail;
    return Container(
      key: const Key('planned-trail'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B24352C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: _forest, size: 19),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Your plan',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              TextButton(
                key: const Key('browse-trails'),
                onPressed: onBrowse,
                style: TextButton.styleFrom(
                  foregroundColor: _forest,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(planned == null ? 'Find a route' : 'Change'),
              ),
            ],
          ),
          if (planned == null)
            const Text(
              'No trail planned yet. Pick a route from the catalogue and its '
              'fit stays here as your conditions change.',
              style: TextStyle(
                color: Color(0xFF68716B),
                fontSize: 12,
                height: 1.35,
              ),
            )
          else ...[
            Text(
              planned.name,
              style: const TextStyle(
                color: _ink,
                fontFamily: 'Georgia',
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              planned.area,
              style: const TextStyle(color: Color(0xFF777E79), fontSize: 11),
            ),
            const SizedBox(height: 7),
            Text(
              planned.elevationKnown
                  ? '${planned.distanceLabel} · ${planned.ascentLabel} ascent · '
                        '${planned.durationLabel}'
                  : '${planned.distanceLabel} · ascent unknown · '
                        '${planned.durationLabel}',
              style: const TextStyle(
                color: Color(0xFF5F6862),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TrailFitBadge(
                  fit: trailFit(
                    trail: planned,
                    ability: ability,
                    conditions: conditions,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${ability.label} · '
                    '${conditions.label.toLowerCase()} conditions',
                    style: const TextStyle(
                      color: Color(0xFF858B86),
                      fontSize: 10,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('clear-plan'),
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF777E79),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'Clear plan',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteAdvisor extends StatelessWidget {
  const _RouteAdvisor({
    required this.hikes,
    required this.ability,
    required this.conditions,
    required this.onAbilityChanged,
    required this.onConditionsChanged,
  });

  final List<SavedHike> hikes;
  final HikingAbility ability;
  final TrailConditions conditions;
  final ValueChanged<HikingAbility> onAbilityChanged;
  final ValueChanged<TrailConditions> onConditionsChanged;

  @override
  Widget build(BuildContext context) {
    final recommendation = recommendSavedRoute(
      hikes: hikes,
      ability: ability,
      conditions: conditions,
    );
    return Container(
      key: const Key('route-advisor'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B24352C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded, color: _forest, size: 19),
              SizedBox(width: 8),
              Text(
                'Route finder',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Match a route to your ability and today’s conditions.',
            style: TextStyle(color: Color(0xFF777E79), fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<HikingAbility>(
                  key: const Key('ability-selector'),
                  initialValue: ability,
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
                    if (value != null) onAbilityChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<TrailConditions>(
                  key: const Key('conditions-selector'),
                  initialValue: conditions,
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
                    if (value != null) onConditionsChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (recommendation == null)
            const _RecommendationMessage(
              icon: Icons.explore_outlined,
              text:
                  'No saved route fits these settings yet. Record another hike or adjust your choices.',
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SUGGESTED FROM YOUR HIKES',
                    style: TextStyle(
                      color: _forest,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_HikeHistory._monthName(recommendation.hike.startedAt.month)} ${recommendation.hike.startedAt.day}, ${recommendation.hike.startedAt.year}',
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${(recommendation.hike.distanceMeters / 1000).toStringAsFixed(1)} km · +${recommendation.hike.elevationGainMeters.round()} m ascent · ${(recommendation.hike.durationSeconds / 60).round()} min',
                    style: const TextStyle(
                      color: Color(0xFF5F6862),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${recommendation.reason} ${conditions.preparationTip}',
                    style: const TextStyle(
                      color: Color(0xFF68716B),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Uses your recorded hikes and self-reported conditions; not live weather or trail-closure data.',
            style: TextStyle(color: Color(0xFF858B86), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _RecommendationMessage extends StatelessWidget {
  const _RecommendationMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: _forest, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFF68716B), fontSize: 12),
        ),
      ),
    ],
  );
}

class _HikeHistory extends StatelessWidget {
  const _HikeHistory({
    required this.hikes,
    required this.isLoading,
    required this.photoCounts,
    required this.onOpenAlbum,
  });

  final List<SavedHike> hikes;
  final bool isLoading;
  final Map<String, int> photoCounts;
  final ValueChanged<SavedHike> onOpenAlbum;

  Future<void> _shareGpx(BuildContext context, SavedHike hike) async {
    final file = XFile.fromData(
      utf8.encode(toGpx(hike, name: hike.plannedTrailName ?? 'TrailOff hike')),
      name: gpxFileName(hike.startedAt),
      mimeType: 'application/gpx+xml',
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        subject: 'TrailOff hike',
        text: 'My hike recorded with TrailOff.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 3, bottom: 10),
          child: Text(
            'Past adventures',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (hikes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Row(
              children: [
                Icon(Icons.hiking_rounded, color: _forest, size: 21),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your recorded hikes will be saved here on this device.',
                    style: TextStyle(color: Color(0xFF6F7771), fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          ...hikes.map((hike) {
            final date = hike.startedAt;
            final durationMinutes = (hike.durationSeconds / 60).round();
            final photoCount = photoCounts[tripKeyFor(hike.startedAt)] ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.terrain_rounded,
                    color: _forest,
                    size: 22,
                  ),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_monthName(date.month)} ${date.day}, ${date.year}',
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (hike.plannedTrailName != null)
                      Text(
                        hike.plannedTrailName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _forest,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                isThreeLine: hike.plannedTrailName != null,
                subtitle: Text(
                  '${(hike.distanceMeters / 1000).toStringAsFixed(2)} km · $durationMinutes min · ${hike.points.length} GPS points',
                  style: const TextStyle(
                    color: Color(0xFF818883),
                    fontSize: 11,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+${hike.elevationGainMeters.round()} m',
                      style: const TextStyle(
                        color: _forest,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    IconButton(
                      tooltip: photoCount == 0
                          ? 'Trip album'
                          : 'Trip album · $photoCount photos',
                      onPressed: () => onOpenAlbum(hike),
                      icon: Badge.count(
                        count: photoCount,
                        isLabelVisible: photoCount > 0,
                        backgroundColor: _forest,
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                        child: const Icon(
                          Icons.photo_library_outlined,
                          color: _forest,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Share GPX',
                      onPressed: () => _shareGpx(context, hike),
                      icon: const Icon(Icons.ios_share_rounded, color: _forest),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  static String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

class _HikeSummary extends StatelessWidget {
  const _HikeSummary({
    required this.onRecordPressed,
    required this.isRecording,
    required this.hasRecordedSession,
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.latestPoint,
    required this.points,
    required this.photoCount,
    required this.onTakePhoto,
    this.trail,
    this.offRouteMeters,
  });

  final VoidCallback onRecordPressed;
  final bool isRecording;
  final bool hasRecordedSession;
  final int elapsedSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final HikePoint? latestPoint;
  final List<HikePoint> points;
  final Trail? trail;

  /// How far the latest fix is from the planned line while off route.
  final double? offRouteMeters;

  /// Photos already captured into the trip being recorded.
  final int photoCount;
  final VoidCallback onTakePhoto;

  String get _duration {
    final minutes = elapsedSeconds ~/ 60;
    final seconds = elapsedSeconds % 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60}h ${minutes % 60}m';
    }
    return minutes == 0
        ? '${seconds}s'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final plannedTrail = trail;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 17, 15, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B24352C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                Text(
                  'LIVE HIKE',
                  style: TextStyle(
                    color: _forest,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                Spacer(),
                Icon(Icons.gps_fixed_rounded, size: 14, color: _forest),
                SizedBox(width: 4),
                Text(
                  'GPS route',
                  style: TextStyle(color: Color(0xFF7A817C), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _MetricTile(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: _duration,
              ),
              _MetricTile(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: '${(distanceMeters / 1000).toStringAsFixed(2)} km',
              ),
              _MetricTile(
                icon: Icons.speed_rounded,
                label: 'Avg speed',
                value: elapsedSeconds == 0
                    ? '0.0 km/h'
                    : '${(distanceMeters / elapsedSeconds * 3.6).toStringAsFixed(1)} km/h',
              ),
              _MetricTile(
                icon: Icons.north_east_rounded,
                label: 'Altitude',
                value: latestPoint == null
                    ? '— m'
                    : '${latestPoint!.altitude.round()} m',
              ),
            ],
          ),
          if (offRouteMeters != null) ...[
            const SizedBox(height: 10),
            _OffRouteWarning(distanceMeters: offRouteMeters!),
          ],
          if (plannedTrail != null && (isRecording || latestPoint != null)) ...[
            const SizedBox(height: 10),
            _TrailheadReturn(trail: plannedTrail, latestPoint: latestPoint),
          ],
          const SizedBox(height: 20),
          const Text(
            'Elevation',
            style: TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _ElevationChart(points: points),
          const SizedBox(height: 8),
          Text(
            '${elevationGainMeters.round()} m climbed · ${latestPoint == null ? 'Waiting for GPS' : '${latestPoint!.accuracy.round()} m GPS accuracy'}',
            style: const TextStyle(color: Color(0xFF858B86), fontSize: 11),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onRecordPressed,
              icon: Icon(
                isRecording
                    ? Icons.stop_rounded
                    : Icons.fiber_manual_record_rounded,
                size: 17,
              ),
              label: Text(
                isRecording
                    ? 'Finish hike'
                    : hasRecordedSession
                    ? 'Record another hike'
                    : 'Record a hike',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isRecording
                    ? const Color(0xFFB5483E)
                    : _forest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          if (isRecording) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                key: const Key('take-hike-photo'),
                onPressed: onTakePhoto,
                icon: const Icon(Icons.photo_camera_rounded, size: 17),
                label: Text(
                  photoCount == 0
                      ? 'Take a photo'
                      : 'Take a photo · $photoCount kept',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _forest,
                  side: const BorderSide(color: Color(0x553E8967)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OffRouteWarning extends StatelessWidget {
  const _OffRouteWarning({required this.distanceMeters});

  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    // Rounded to 10 m so the figure does not jitter with every GPS fix.
    final rounded = (distanceMeters / 10).round() * 10;
    return Container(
      key: const Key('off-route-warning'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEDE8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEBC3B7)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wrong_location_rounded,
            color: Color(0xFFB5483E),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OFF THE PLANNED ROUTE',
                  style: TextStyle(
                    color: Color(0xFF8E3A31),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'About $rounded m from the line. Head back towards it.',
                  style: const TextStyle(
                    color: Color(0xFF6E3A32),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailheadReturn extends StatelessWidget {
  const _TrailheadReturn({required this.trail, required this.latestPoint});

  final Trail trail;
  final HikePoint? latestPoint;

  @override
  Widget build(BuildContext context) {
    final point = latestPoint;
    final bearing = point == null
        ? null
        : bearingToTrailhead(
            fromLatitude: point.latitude,
            fromLongitude: point.longitude,
            trailheadLatitude: trail.trailheadLatitude,
            trailheadLongitude: trail.trailheadLongitude,
          );
    final atTrailhead = bearing != null && bearing.distanceMeters < 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Transform.rotate(
            angle: (bearing?.bearingDegrees ?? 0) * math.pi / 180,
            child: const Icon(
              Icons.navigation_rounded,
              color: _forest,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Back to ${trail.name} trailhead',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _forest,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  point == null
                      ? 'Waiting for GPS'
                      : atTrailhead
                      ? 'You are at the trailhead'
                      : '${bearing!.summary} · straight line',
                  style: const TextStyle(color: _ink, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 48 - 30 - 9) / 2,
      child: Container(
        height: 75,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: _forest, size: 23),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF858B86),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElevationChart extends StatelessWidget {
  const _ElevationChart({required this.points});

  final List<HikePoint> points;

  @override
  Widget build(BuildContext context) {
    final elevations = points.map((point) => point.altitude).toList();
    final minimum = elevations.isEmpty
        ? null
        : elevations.reduce((a, b) => a < b ? a : b);
    final maximum = elevations.isEmpty
        ? null
        : elevations.reduce((a, b) => a > b ? a : b);
    return Container(
      height: 130,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Elevation profile',
                style: TextStyle(color: Color(0xFF969D98), fontSize: 10),
              ),
              Text(
                'LIVE GPS',
                style: TextStyle(
                  color: _forest,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: CustomPaint(
              painter: _ElevationPainter(points: List.unmodifiable(points)),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                minimum == null ? 'Waiting for GPS' : '${minimum.round()} m',
                style: TextStyle(color: Color(0xFF969D98), fontSize: 10),
              ),
              Text(
                maximum == null ? 'Route' : '${maximum.round()} m',
                style: TextStyle(color: Color(0xFF858B86), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  const _ElevationPainter({required this.points});

  final List<HikePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE9ECE8)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (i + 1) / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;
    final minimum = points
        .map((point) => point.altitude)
        .reduce((a, b) => a < b ? a : b);
    final maximum = points
        .map((point) => point.altitude)
        .reduce((a, b) => a > b ? a : b);
    final range = (maximum - minimum).abs();
    final profile = Path();
    Offset? lastPoint;
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final normalized = range < 1
          ? 0.5
          : (points[i].altitude - minimum) / range;
      final y = size.height * (0.88 - normalized * 0.72);
      lastPoint = Offset(x, y);
      if (i == 0) {
        profile.moveTo(x, y);
      } else {
        profile.lineTo(x, y);
      }
    }
    final fill = Path.from(profile)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0xFFE2A06D));
    canvas.drawPath(
      profile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFC66D39),
    );
    final end = lastPoint!;
    canvas.drawCircle(end, 6, Paint()..color = Colors.white);
    canvas.drawCircle(end, 4, Paint()..color = const Color(0xFF0878F9));
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) =>
      oldDelegate.points != points;
}
