import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'satellites.dart';
import 'sky_math.dart';

class ConstellationPage extends StatefulWidget {
  const ConstellationPage({
    super.key,
    this.locate,
    this.orientation,
    this.satellites,
    this.clock,
  });
  final Future<Position> Function()? locate;
  final Stream<dynamic>? orientation;
  final SatelliteRepository? satellites;
  final DateTime Function()? clock;
  @override
  State<ConstellationPage> createState() => _ConstellationPageState();
}

class _ConstellationPageState extends State<ConstellationPage>
    with WidgetsBindingObserver {
  static const _channel = EventChannel('trailoff/sky_orientation');
  late final SatelliteRepository _satellites;
  StreamSubscription<dynamic>? _motion;
  Future<void> _motionCancellation = Future<void>.value();
  int _motionGeneration = 0, _locationGeneration = 0;
  bool _locationRequested = false;
  Timer? _timer;
  Position? _location;
  late DateTime _now;
  DateTime _clock() => (widget.clock?.call() ?? DateTime.now()).toUtc();
  DateTime? _lastMotion, _fetchedAt, _attemptAt;
  List<double>? _matrix;
  List<SatelliteTrack> _tracks = [];
  String _locationStatus = 'Location is needed to calculate your sky.';
  String _satelliteStatus = 'Satellites are off.';
  bool _locating = false,
      _loading = false,
      _enabled = false,
      _manual = false,
      _active = true;
  int _generation = 0;
  double _azimuth = 0, _altitude = 45;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = _clock();
    _satellites = widget.satellites ?? SatelliteRepository();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_active) return;
      setState(() => _now = _clock());
      if (_enabled &&
          _location != null &&
          !_loading &&
          (_attemptAt == null ||
              _now.difference(_attemptAt!).inSeconds >= 240)) {
        _loadSatellites();
      }
    });
  }

  Future<Position> _locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on location services, then retry.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Allow location in system settings, then retry.');
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was denied. You can retry.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _start() async {
    if (_locating || !_active) return;
    _locationRequested = true;
    final request = ++_locationGeneration;
    _generation++;
    _stopMotion();
    setState(() {
      _locating = true;
      _location = null;
      _matrix = null;
      _tracks = [];
      _fetchedAt = null;
      _attemptAt = null;
      _locationStatus = 'Finding your location…';
    });
    try {
      final p = await (widget.locate ?? _locate)();
      if (!mounted || request != _locationGeneration) return;
      _generation++;
      setState(() {
        _location = p;
        _tracks = [];
        _fetchedAt = null;
        _attemptAt = null;
        _locationStatus =
            '${p.latitude.toStringAsFixed(3)}°, ${p.longitude.toStringAsFixed(3)}° · ±${p.accuracy.round()} m';
      });
      if (_active) _startMotion();
      if (_enabled && _active) _loadSatellites();
    } catch (error) {
      if (mounted && request == _locationGeneration) {
        setState(
          () => _locationStatus =
              'Location unavailable. Check permission and GPS, then retry.',
        );
      }
    } finally {
      if (mounted && request == _locationGeneration) {
        setState(() => _locating = false);
      }
    }
  }

  // Serialize native channel teardown before subscribing again. Pending callbacks
  // carry a generation so a cancelled session cannot realign the resumed chart.
  void _stopMotion() {
    _motionGeneration++;
    final subscription = _motion;
    _motion = null;
    if (subscription != null) _motionCancellation = subscription.cancel();
    _matrix = null;
    _lastMotion = null;
  }

  Future<void> _startMotion() async {
    _stopMotion();
    final generation = _motionGeneration;
    await _motionCancellation;
    if (!mounted ||
        !_active ||
        _location == null ||
        generation != _motionGeneration) {
      return;
    }
    _motion =
        (widget.orientation ??
                _channel.receiveBroadcastStream({
                  'latitude': _location!.latitude,
                  'longitude': _location!.longitude,
                  'altitude': _location!.altitude,
                }))
            .listen(
              (event) {
                if (!mounted || !_active || generation != _motionGeneration) {
                  return;
                }
                if (event is! List ||
                    event.length != 9 ||
                    event.any((v) => v is! num || !v.isFinite)) {
                  setState(() {
                    _matrix = null;
                    _lastMotion = null;
                  });
                  return;
                }
                final values = event.map((v) => (v as num).toDouble()).toList();
                setState(() {
                  _matrix = values;
                  _lastMotion = _clock();
                });
              },
              onError: (Object _) {
                if (mounted && generation == _motionGeneration) {
                  setState(() {
                    _matrix = null;
                    _lastMotion = null;
                  });
                }
              },
              onDone: () {
                if (mounted && generation == _motionGeneration) {
                  setState(() {
                    _matrix = null;
                    _lastMotion = null;
                  });
                }
              },
            );
  }

  Future<void> _loadSatellites() async {
    final p = _location;
    if (_loading || p == null || !_satellites.configured) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _attemptAt = _clock();
      _satelliteStatus = 'Updating N2YO predictions…';
    });
    try {
      final tracks = await _satellites.load(
        p.latitude,
        p.longitude,
        p.altitude,
      );
      if (!mounted || generation != _generation || !_active || !_enabled) {
        return;
      }
      setState(() {
        _tracks = tracks;
        _fetchedAt = _clock();
        _satelliteStatus = 'N2YO · ISS & Hubble only';
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _tracks = [];
          _fetchedAt = null;
          _satelliteStatus =
              'Satellite data unavailable (network, key or quota). Retrying in 4 minutes.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs can make the app inactive without backgrounding it.
    // Keep that request alive; invalidate it only when the app is hidden/paused.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _locating) {
      _locationGeneration++;
      _locating = false;
    }
    final active = state == AppLifecycleState.resumed;
    if (active == _active) return;
    _active = active;
    if (!_active) {
      _generation++;
      _stopMotion();
      _tracks = [];
      _fetchedAt = null;
    } else {
      _now = _clock();
      if (_locationRequested) _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopMotion();
    if (widget.satellites == null) _satellites.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clockNow = _clock();
    final sensorReady =
        _matrix != null &&
        _lastMotion != null &&
        !clockNow.isBefore(_lastMotion!) &&
        clockNow.difference(_lastMotion!).inMilliseconds < 3000;
    final manual = _manual || !sensorReady;
    final current =
        _enabled &&
        _fetchedAt != null &&
        !_now.isBefore(_fetchedAt!) &&
        _now.difference(_fetchedAt!).inSeconds < 300 &&
        _tracks.isNotEmpty &&
        _tracks.every((track) => track.positionAt(_now) != null);
    final visible = current
        ? _tracks
              .map((t) => t.visibleAt(_now))
              .whereType<SatelliteSample>()
              .toList()
        : <SatelliteSample>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Constellation')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Your campsite sky',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Point the back of your phone toward the sky. No camera is used. Stars are a calculated chart, including in daylight.',
            ),
            const SizedBox(height: 8),
            Text(_locationStatus),
            TextButton.icon(
              onPressed: _locating ? null : _start,
              icon: const Icon(Icons.my_location),
              label: Text(
                _locating
                    ? 'Finding location…'
                    : _location == null
                    ? 'Use my location'
                    : 'Refresh location',
              ),
            ),
            if (_location != null) ...[
              Text(
                '${_now.toIso8601String().substring(0, 19).replaceFirst('T', ' ')} UTC',
              ),
              Text(
                manual
                    ? 'Manual view · drag to explore (true north)'
                    : 'Sensor aligned · approximate true north',
              ),
              if (!sensorReady)
                const Text(
                  'Orientation unavailable or waiting. Manual view works without sensors.',
                ),
              const Text(
                'For alignment, move the phone in a figure eight away from magnets.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manual view'),
                value: _manual,
                onChanged: (value) => setState(() => _manual = value),
              ),
              Semantics(
                label:
                    'Sky chart. White dots are catalog stars. Amber diamonds are predicted visible satellites.',
                child: GestureDetector(
                  onPanUpdate: manual
                      ? (d) => setState(() {
                          _azimuth = (_azimuth - d.delta.dx * 0.25) % 360;
                          _altitude = (_altitude + d.delta.dy * 0.25).clamp(
                            0,
                            90,
                          );
                        })
                      : null,
                  child: SizedBox(
                    height: 360,
                    width: double.infinity,
                    child: ClipRect(
                      child: CustomPaint(
                        painter: SkyPainter(
                          location: _location!,
                          time: _now,
                          matrix: manual
                              ? manualView(_azimuth, _altitude)
                              : _matrix!,
                          satellites: visible,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (manual)
                Text(
                  'Center: ${_azimuth.round()}° azimuth · ${_altitude.round()}° altitude',
                ),
              const Text('White: bright stars · Amber: predicted satellite'),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Live satellite predictions'),
              subtitle: Text(
                _satellites.configured
                    ? 'Uses internet and sends your coordinates to N2YO.'
                    : 'Unavailable in this build: configure an N2YO API key. Stars still work offline.',
              ),
              value: _enabled,
              onChanged: _satellites.configured && _location != null
                  ? (value) {
                      setState(() {
                        _enabled = value;
                        _tracks = [];
                        _fetchedAt = null;
                        _attemptAt = null;
                        _generation++;
                      });
                      if (value) _loadSatellites();
                    }
                  : null,
            ),
            if (_enabled) ...[
              Text(_satelliteStatus),
              if (_fetchedAt != null)
                Text(
                  'Updated ${_fetchedAt!.toIso8601String().substring(11, 19)} UTC',
                ),
              if (current)
                Text(
                  visible.isEmpty
                      ? 'No full-visibility predictions for ISS or Hubble now.'
                      : '${visible.map((s) => s.name).join(', ')} predicted above the horizon; may be outside this view.',
                ),
              if (!current && !_loading)
                Text(
                  _fetchedAt == null
                      ? 'No current satellite positions to display.'
                      : 'Satellite positions do not cover the current time. Waiting for fresh predictions.',
                ),
            ],
            const SizedBox(height: 12),
            const Text(
              'A sky guide, not object recognition',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Sensors only align this chart. Labels do not identify a light you see. This first version includes 21 bright stars, ISS and Hubble, not all satellites, planets or constellation outlines. Clouds, terrain, light pollution and compass errors can hide or shift objects. Satellite visibility is predicted, never guaranteed. Partly visible passes with uncertain visibility timing are omitted.',
            ),
          ],
        ),
      ),
    );
  }
}

class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.location,
    required this.time,
    required this.matrix,
    required this.satellites,
  });
  final Position location;
  final DateTime time;
  final List<double> matrix;
  final List<SatelliteSample> satellites;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101B2D),
    );
    final grid = Paint()
      ..color = const Color(0xFF33465E)
      ..strokeWidth = 1;
    for (var altitude = 0; altitude <= 60; altitude += 30) {
      Offset? last;
      for (var az = 0; az <= 360; az += 2) {
        final point = projectSky(
          SkyVector.horizontal(az.toDouble(), altitude.toDouble()),
          matrix,
          size,
        );
        if (point != null &&
            last != null &&
            (point - last).distance < size.shortestSide / 2) {
          canvas.drawLine(last, point, grid);
        }
        last = point;
      }
    }
    for (final entry in const {0: 'N', 90: 'E', 180: 'S', 270: 'W'}.entries) {
      final p = projectSky(
        SkyVector.horizontal(entry.key.toDouble(), 2),
        matrix,
        size,
      );
      if (p != null) {
        _label(canvas, size, p, entry.value, Colors.blueGrey.shade200);
      }
    }
    for (final star in brightStars) {
      final p = projectSky(
        equatorialToLocal(
          star.ra,
          star.dec,
          location.latitude,
          location.longitude,
          time,
        ),
        matrix,
        size,
      );
      if (p == null) continue;
      canvas.drawCircle(
        p,
        (3 - star.magnitude * 0.5).clamp(1.5, 4),
        Paint()..color = Colors.white,
      );
      _label(canvas, size, p, star.name, Colors.white70);
    }
    for (final satellite in satellites) {
      final p = projectSky(satellite.direction, matrix, size);
      if (p == null) continue;
      final diamond = Path()
        ..moveTo(p.dx, p.dy - 6)
        ..lineTo(p.dx + 6, p.dy)
        ..lineTo(p.dx, p.dy + 6)
        ..lineTo(p.dx - 6, p.dy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = Colors.amber);
      _label(canvas, size, p, '${satellite.name} (predicted)', Colors.amber);
    }
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(
      center - const Offset(6, 0),
      center + const Offset(6, 0),
      grid,
    );
    canvas.drawLine(
      center - const Offset(0, 6),
      center + const Offset(0, 6),
      grid,
    );
  }

  void _label(
    Canvas canvas,
    Size size,
    Offset point,
    String text,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    painter.paint(
      canvas,
      Offset(
        (point.dx + 7).clamp(0, size.width - painter.width),
        (point.dy + 3).clamp(0, size.height - painter.height),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant SkyPainter oldDelegate) => true;
}
