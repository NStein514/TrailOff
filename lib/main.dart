import 'dart:async';

import 'package:flutter/material.dart';

import 'hike_recording.dart';

void main() {
  runApp(const TrailOffApp());
}

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

class TrailOffApp extends StatelessWidget {
  const TrailOffApp({super.key, this.locationSource, this.historyStore});

  final HikeLocationSource? locationSource;
  final HikeHistoryStore? historyStore;

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
      ),
    );
  }
}

class HikeDashboard extends StatefulWidget {
  const HikeDashboard({super.key, this.locationSource, this.historyStore});

  final HikeLocationSource? locationSource;
  final HikeHistoryStore? historyStore;

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
  bool _mapSaved = false;

  @override
  void initState() {
    super.initState();
    _locationSource = widget.locationSource ?? GeolocatorHikeLocationSource();
    _historyStore = widget.historyStore ?? SharedPreferencesHikeHistoryStore();
    _loadHistory();
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

  void _toggleOfflineMap() {
    setState(() => _mapSaved = !_mapSaved);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _mapSaved
                ? 'Tour du Portillon added to your offline maps.'
                : 'Tour du Portillon removed from offline maps.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _ink,
        ),
      );
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
                  _TrailMap(points: _recordedPoints, isRecording: _isRecording),
                  _OfflineMapButton(
                    saved: _mapSaved,
                    onPressed: _toggleOfflineMap,
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
  const _TrailMap({required this.points, required this.isRecording});

  final List<HikePoint> points;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 338,
        child: Stack(
          fit: StackFit.expand,
          children: [
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

class _OfflineMapButton extends StatelessWidget {
  const _OfflineMapButton({required this.saved, required this.onPressed});

  final bool saved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _ink,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                saved ? 'Map saved offline' : 'Save map offline',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                saved
                    ? Icons.check_circle_outline_rounded
                    : Icons.wifi_off_rounded,
                color: Colors.white,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HikeHistory extends StatelessWidget {
  const _HikeHistory({required this.hikes, required this.isLoading});

  final List<SavedHike> hikes;
  final bool isLoading;

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
                trailing: Text(
                  '+${hike.elevationGainMeters.round()} m',
                  style: const TextStyle(
                    color: _forest,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
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
