import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:share_plus/share_plus.dart';

import 'hike_recording.dart';
import 'constellation.dart';
import 'offline_map.dart';
import 'packing_checklist.dart';
import 'route_recommendations.dart';

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
  });

  final HikeLocationSource? locationSource;
  final HikeHistoryStore? historyStore;
  final OfflineMapRepository? offlineMapRepository;
  final bool? offlineMapSupported;
  final bool? nativeMapSupported;

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
  });

  final HikeLocationSource? locationSource;
  final HikeHistoryStore? historyStore;
  final OfflineMapRepository? offlineMapRepository;
  final bool? offlineMapSupported;
  final bool? nativeMapSupported;

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
  bool get _offlineMapSupported =>
      widget.offlineMapSupported ?? _isMobileTarget;
  bool get _nativeMapSupported => widget.nativeMapSupported ?? _isMobileTarget;
  bool get _isMobileTarget =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  late final OfflineMapRepository _offlineMapRepository;

  @override
  void initState() {
    super.initState();
    _locationSource = widget.locationSource ?? GeolocatorHikeLocationSource();
    _historyStore = widget.historyStore ?? SharedPreferencesHikeHistoryStore();
    _offlineMapRepository =
        widget.offlineMapRepository ?? MapLibreOfflineMapRepository();
    _loadHistory();
    _loadOfflineRegion();
  }

  Future<void> _loadOfflineRegion() async {
    if (!_offlineMapSupported) return;
    try {
      final region = await _offlineMapRepository.findTourRegion();
      if (!mounted || region == null) return;
      setState(() {
        _offlineRegionId = region.id;
        _mapSaved = region.isComplete;
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
    setState(() {
      _mapDownloading = true;
      _mapDownloadProgress = 0;
      _mapDownloadedBytes = 0;
    });
    try {
      final regionId = await _offlineMapRepository.downloadTourRegion(
        onProgress: (progress, bytes) {
          if (!mounted) return;
          setState(() {
            _mapDownloadProgress = progress.clamp(0.0, 1.0);
            _mapDownloadedBytes = bytes;
          });
        },
        onComplete: () {
          if (!mounted) return;
          setState(() {
            _mapDownloading = false;
            _mapSaved = true;
          });
          _showMessage('Tour du Portillon is ready for offline use.');
        },
        onError: (message) {
          if (!mounted) return;
          setState(() => _mapDownloading = false);
          _showMessage('Map download failed: $message');
        },
      );
      if (!mounted) return;
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

    setState(() {
      if (previous != null) _distanceMeters += segment;
      if (previous != null) {
        final elevationChange = point.altitude - previous.altitude;
        if (elevationChange > 0) _elevationGainMeters += elevationChange;
      }
      _recordedPoints.add(point);
      _latestPoint = point;
    });
  }

  Future<void> _finishRecording() async {
    final startedAt = _startedAt;
    if (!_isRecording || startedAt == null) return;
    final finishedAt = DateTime.now();
    final recordedPoints = List<HikePoint>.unmodifiable(_recordedPoints);
    final distanceMeters = _distanceMeters;
    final elevationGainMeters = _elevationGainMeters;
    _elapsedTimer?.cancel();
    final locationSubscription = _locationSubscription;
    _locationSubscription = null;
    setState(() {
      _isRecording = false;
      _elapsedSeconds = finishedAt.difference(startedAt).inSeconds;
    });
    if (locationSubscription != null) unawaited(locationSubscription.cancel());

    if (recordedPoints.isEmpty) {
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
    );
    try {
      await _historyStore.save(hike);
      if (!mounted) return;
      setState(() => _savedHikes = [hike, ..._savedHikes]);
      _showMessage('Hike saved with ${hike.points.length} GPS points.');
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
                    child: TextButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Constellation'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ConstellationPage(),
                        ),
                      ),
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
                  ),
                  const SizedBox(height: 20),
                  _HikeHistory(
                    hikes: _savedHikes,
                    isLoading: _isLoadingHistory,
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
  });

  final List<HikePoint> points;
  final bool isRecording;
  final bool showNativeMap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 338,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showNativeMap)
              _NativeTrailMap(points: List.unmodifiable(points))
            else
              CustomPaint(
                painter: _TopoMapPainter(points: List.unmodifiable(points)),
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
            Positioned(
              left: MediaQuery.sizeOf(context).width * 0.43,
              top: 177,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF0878F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33808A83), blurRadius: 7),
                  ],
                ),
              ),
            ),
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
  const _TopoMapPainter({required this.points});

  final List<HikePoint> points;

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

    if (points.isEmpty) {
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

    if (points.length > 1) {
      final minLatitude = points
          .map((point) => point.latitude)
          .reduce((a, b) => a < b ? a : b);
      final maxLatitude = points
          .map((point) => point.latitude)
          .reduce((a, b) => a > b ? a : b);
      final minLongitude = points
          .map((point) => point.longitude)
          .reduce((a, b) => a < b ? a : b);
      final maxLongitude = points
          .map((point) => point.longitude)
          .reduce((a, b) => a > b ? a : b);
      final latitudeRange = maxLatitude - minLatitude;
      final longitudeRange = maxLongitude - minLongitude;
      Offset mapPoint(HikePoint point) => Offset(
        size.width *
            (0.15 +
                0.7 *
                    (longitudeRange == 0
                        ? 0.5
                        : (point.longitude - minLongitude) / longitudeRange)),
        size.height *
            (0.15 +
                0.7 *
                    (latitudeRange == 0
                        ? 0.5
                        : 1 - (point.latitude - minLatitude) / latitudeRange)),
      );
      final track = Path();
      for (var i = 0; i < points.length; i++) {
        final point = mapPoint(points[i]);
        final x = point.dx;
        final y = point.dy;
        if (i == 0) {
          track.moveTo(x, y);
        } else {
          track.lineTo(x, y);
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
      final current = mapPoint(points.last);
      canvas.drawCircle(current, 7, Paint()..color = Colors.white);
      canvas.drawCircle(current, 4, Paint()..color = const Color(0xFF0878F9));
    }
  }

  @override
  bool shouldRepaint(covariant _TopoMapPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _NativeTrailMap extends StatefulWidget {
  const _NativeTrailMap({required this.points});

  final List<HikePoint> points;

  @override
  State<_NativeTrailMap> createState() => _NativeTrailMapState();
}

class _NativeTrailMapState extends State<_NativeTrailMap> {
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _trailLine;
  bool _styleLoaded = false;

  @override
  Widget build(BuildContext context) => maplibre.MapLibreMap(
    initialCameraPosition: const maplibre.CameraPosition(
      target: maplibre.LatLng(42.695, 0.515),
      zoom: 12,
    ),
    styleString: tourOfflineMapStyle,
    compassEnabled: true,
    myLocationEnabled: false,
    logoEnabled: false,
    attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
    onMapCreated: (controller) => _controller = controller,
    onStyleLoadedCallback: _drawKnownTrail,
  );

  void _drawKnownTrail() {
    final controller = _controller;
    if (!_styleLoaded && controller != null) {
      _styleLoaded = true;
      _updateTrailLine();
    }
  }

  @override
  void didUpdateWidget(covariant _NativeTrailMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_styleLoaded && oldWidget.points != widget.points) {
      _updateTrailLine();
    }
  }

  Future<void> _updateTrailLine() async {
    final controller = _controller;
    if (controller == null || !_styleLoaded) return;
    final previousLine = _trailLine;
    if (previousLine != null) await controller.removeLine(previousLine);
    final geometry = widget.points.isEmpty
        ? const [
            maplibre.LatLng(42.686, 0.486),
            maplibre.LatLng(42.691, 0.497),
            maplibre.LatLng(42.688, 0.506),
            maplibre.LatLng(42.699, 0.512),
            maplibre.LatLng(42.703, 0.526),
          ]
        : widget.points
              .map((point) => maplibre.LatLng(point.latitude, point.longitude))
              .toList();
    _trailLine = await controller.addLine(
      maplibre.LineOptions(
        geometry: geometry,
        lineColor: widget.points.isEmpty ? '#C66D39' : '#0878F9',
        lineWidth: 4,
        lineOpacity: 0.95,
        lineJoin: 'round',
      ),
    );
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
  const _HikeHistory({required this.hikes, required this.isLoading});

  final List<SavedHike> hikes;
  final bool isLoading;

  Future<void> _shareGpx(BuildContext context, SavedHike hike) async {
    final file = XFile.fromData(
      utf8.encode(toGpx(hike)),
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
                title: Text(
                  '${_monthName(date.month)} ${date.day}, ${date.year}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
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
  });

  final VoidCallback onRecordPressed;
  final bool isRecording;
  final bool hasRecordedSession;
  final int elapsedSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final HikePoint? latestPoint;
  final List<HikePoint> points;

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
