import 'package:flutter/material.dart';

void main() {
  runApp(const TrailOffApp());
}

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

class TrailOffApp extends StatelessWidget {
  const TrailOffApp({super.key});

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
      home: const HikeDashboard(),
    );
  }
}

class HikeDashboard extends StatefulWidget {
  const HikeDashboard({super.key});

  @override
  State<HikeDashboard> createState() => _HikeDashboardState();
}

class _HikeDashboardState extends State<HikeDashboard> {
  bool _mapSaved = false;

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

  void _showTrackingInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.my_location_rounded, color: _forest),
        title: const Text('Ready for your next hike?'),
        content: const Text(
          'Live GPS tracking and route recording are the next step for TrailOff. '
          'Your hike summary below is sample data for this preview.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
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
                  const _TrailMap(),
                  _OfflineMapButton(saved: _mapSaved, onPressed: _toggleOfflineMap),
                  const SizedBox(height: 12),
                  _HikeSummary(onRecordPressed: _showTrackingInfo),
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
          decoration: const BoxDecoration(color: _forest, shape: BoxShape.circle),
          child: const Icon(Icons.terrain_rounded, color: Colors.white, size: 19),
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
              Text('12°', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              SizedBox(width: 4),
              Text('Clear', style: TextStyle(color: Color(0xFF777E79), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrailMap extends StatelessWidget {
  const _TrailMap();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 338,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _TopoMapPainter()),
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
              child: _MapPin(color: Color(0xFFF2A83B), icon: Icons.home_rounded),
            ),
            const Positioned(
              right: 27,
              top: 20,
              child: _MapPin(color: Color(0xFF62B8E4), icon: Icons.water_rounded, small: true),
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
                  boxShadow: const [BoxShadow(color: Color(0x33808A83), blurRadius: 7)],
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.navigation_rounded, color: _forest, size: 14),
                    SizedBox(width: 5),
                    Text('North', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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
        boxShadow: const [BoxShadow(color: Color(0x33808080), blurRadius: 9, offset: Offset(0, 3))],
      ),
      child: Icon(icon, color: Colors.white, size: small ? 21 : 23),
    );
  }
}

class _TopoMapPainter extends CustomPainter {
  const _TopoMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      colors: [Color(0xFFE5E8D7), Color(0xFFDCE7D8), Color(0xFFEDEBDD)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(bounds));

    final water = Path()
      ..moveTo(size.width * 0.57, size.height * 0.62)
      ..cubicTo(size.width * 0.64, size.height * 0.54, size.width * 0.76, size.height * 0.56, size.width * 0.82, size.height * 0.47)
      ..cubicTo(size.width * 0.91, size.height * 0.39, size.width * 0.93, size.height * 0.51, size.width, size.height * 0.44)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.49, size.height)
      ..cubicTo(size.width * 0.52, size.height * 0.85, size.width * 0.47, size.height * 0.75, size.width * 0.57, size.height * 0.62)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFF78CDE6));
    canvas.drawPath(water, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF46A8C8).withValues(alpha: 0.8));

    final contours = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF78846B).withValues(alpha: 0.45);
    for (var i = 0; i < 15; i++) {
      final y = size.height * (i / 15);
      final offset = (i % 3 - 1) * 13.0;
      final contour = Path()
        ..moveTo(-12, y + offset)
        ..cubicTo(size.width * 0.24, y - 31 + offset, size.width * 0.34, y + 38 - offset, size.width * 0.60, y + 7)
        ..cubicTo(size.width * 0.74, y - 18, size.width * 0.82, y + 30, size.width + 12, y - 8 + offset);
      canvas.drawPath(contour, contours);
    }

    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD2AC3D).withValues(alpha: 0.9);
    final paths = [
      Path()..moveTo(-5, size.height * 0.83)..cubicTo(size.width * 0.22, size.height * 0.75, size.width * 0.21, size.height * 0.64, size.width * 0.47, size.height * 0.58)..cubicTo(size.width * 0.72, size.height * 0.48, size.width * 0.8, size.height * 0.33, size.width, size.height * 0.29),
      Path()..moveTo(size.width * 0.05, size.height * 0.35)..cubicTo(size.width * 0.25, size.height * 0.31, size.width * 0.31, size.height * 0.42, size.width * 0.42, size.height * 0.36)..cubicTo(size.width * 0.61, size.height * 0.26, size.width * 0.74, size.height * 0.34, size.width * 0.91, size.height * 0.18),
    ];
    for (final path in paths) {
      canvas.drawPath(path, road);
    }

    final route = Path()
      ..moveTo(size.width * 0.02, size.height * 0.37)
      ..cubicTo(size.width * 0.16, size.height * 0.34, size.width * 0.13, size.height * 0.54, size.width * 0.28, size.height * 0.51)
      ..cubicTo(size.width * 0.39, size.height * 0.48, size.width * 0.34, size.height * 0.68, size.width * 0.44, size.height * 0.68)
      ..cubicTo(size.width * 0.51, size.height * 0.68, size.width * 0.49, size.height * 0.58, size.width * 0.57, size.height * 0.62);
    canvas.drawPath(route, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.86));
    canvas.drawPath(route, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFC66D39));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Icon(saved ? Icons.check_circle_outline_rounded : Icons.wifi_off_rounded,
                  color: Colors.white, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _HikeSummary extends StatelessWidget {
  const _HikeSummary({required this.onRecordPressed});

  final VoidCallback onRecordPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 17, 15, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x0B24352C), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                Text('YOUR HIKE', style: TextStyle(color: _forest, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                Spacer(),
                Icon(Icons.verified_rounded, size: 15, color: _forest),
                SizedBox(width: 4),
                Text('Trail summary', style: TextStyle(color: Color(0xFF7A817C), fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _MetricTile(icon: Icons.timer_outlined, label: 'Duration', value: '54 min'),
              _MetricTile(icon: Icons.route_rounded, label: 'Distance', value: '4.2 km'),
              _MetricTile(icon: Icons.speed_rounded, label: 'Avg speed', value: '4.5 km/h'),
              _MetricTile(icon: Icons.north_east_rounded, label: 'Altitude', value: '1,430 m'),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Elevation', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const _ElevationChart(),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onRecordPressed,
              icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
              label: const Text('Record a hike', style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: _forest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.icon, required this.label, required this.value});

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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: _forest, size: 23),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF858B86), fontSize: 11)),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
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
  const _ElevationChart();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1,680 m', style: TextStyle(color: Color(0xFF969D98), fontSize: 10)),
              Text('+402 m', style: TextStyle(color: _forest, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(child: CustomPaint(painter: const _ElevationPainter(), child: const SizedBox.expand())),
          const SizedBox(height: 5),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1,278 m', style: TextStyle(color: Color(0xFF969D98), fontSize: 10)),
              Text('4.2 km', style: TextStyle(color: Color(0xFF858B86), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  const _ElevationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE9ECE8)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (i + 1) / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final profile = Path()
      ..moveTo(0, size.height * 0.86)
      ..lineTo(size.width * 0.09, size.height * 0.80)
      ..cubicTo(size.width * 0.16, size.height * 0.77, size.width * 0.17, size.height * 0.87, size.width * 0.23, size.height * 0.74)
      ..cubicTo(size.width * 0.29, size.height * 0.52, size.width * 0.27, size.height * 0.10, size.width * 0.39, size.height * 0.15)
      ..cubicTo(size.width * 0.48, size.height * 0.16, size.width * 0.49, size.height * 0.34, size.width * 0.58, size.height * 0.27)
      ..cubicTo(size.width * 0.68, size.height * 0.20, size.width * 0.69, size.height * 0.36, size.width * 0.77, size.height * 0.34)
      ..cubicTo(size.width * 0.86, size.height * 0.33, size.width * 0.90, size.height * 0.48, size.width, size.height * 0.62)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(profile, Paint()..color = const Color(0xFFE2A06D));
    final end = Offset(size.width, size.height * 0.62);
    canvas.drawCircle(end, 6, Paint()..color = Colors.white);
    canvas.drawCircle(end, 4, Paint()..color = const Color(0xFF0878F9));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
