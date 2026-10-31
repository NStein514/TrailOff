import 'dart:math' as math;
import 'dart:ui';

const radians = math.pi / 180;

/// East, north, up unit vector. Azimuth is clockwise from true north.
class SkyVector {
  const SkyVector(this.east, this.north, this.up);
  final double east, north, up;
  factory SkyVector.horizontal(double azimuth, double altitude) {
    final a = azimuth * radians;
    final h = altitude * radians;
    return SkyVector(
      math.cos(h) * math.sin(a),
      math.cos(h) * math.cos(a),
      math.sin(h),
    );
  }
}

/// Approximate J2000 catalog coordinates; precession/refraction are omitted.
/// Accuracy is appropriate for a phone finder, not telescope pointing.
SkyVector equatorialToLocal(
  double raHours,
  double declination,
  double latitude,
  double longitude,
  DateTime time,
) {
  final jd = time.toUtc().millisecondsSinceEpoch / 86400000 + 2440587.5;
  final d = jd - 2451545;
  final hourAngle =
      ((280.46061837 + 360.98564736629 * d + longitude) % 360 - raHours * 15) *
      radians;
  final dec = declination * radians;
  final lat = latitude * radians;
  return SkyVector(
    -math.cos(dec) * math.sin(hourAngle),
    math.sin(dec) * math.cos(lat) -
        math.cos(dec) * math.cos(hourAngle) * math.sin(lat),
    math.sin(dec) * math.sin(lat) +
        math.cos(dec) * math.cos(hourAngle) * math.cos(lat),
  );
}

/// Row-major world ENU -> screen device axes. View looks through phone back (-Z).
/// Native bridges remap axes to the current display orientation before delivery.
Offset? projectSky(SkyVector v, List<double> matrix, Size size) {
  if (v.up < 0 || matrix.length != 9) return null;
  final x = matrix[0] * v.east + matrix[1] * v.north + matrix[2] * v.up;
  final y = matrix[3] * v.east + matrix[4] * v.north + matrix[5] * v.up;
  final depth = -(matrix[6] * v.east + matrix[7] * v.north + matrix[8] * v.up);
  if (depth <= 0.01) return null;
  final focal = size.shortestSide / (2 * math.tan(35 * radians));
  final p = Offset(
    size.width / 2 + focal * x / depth,
    size.height / 2 - focal * y / depth,
  );
  return p.dx >= 0 && p.dy >= 0 && p.dx <= size.width && p.dy <= size.height
      ? p
      : null;
}

/// North-facing, 45 degrees above horizon; usable without motion sensors.
const manualSkyMatrix = <double>[
  1,
  0,
  0,
  0,
  -0.7071067812,
  0.7071067812,
  0,
  -0.7071067812,
  -0.7071067812,
];
List<double> manualView(double azimuth, double altitude) {
  final a = azimuth * radians, h = altitude * radians;
  return [
    math.cos(a),
    -math.sin(a),
    0,
    -math.sin(a) * math.sin(h),
    -math.cos(a) * math.sin(h),
    math.cos(h),
    -math.sin(a) * math.cos(h),
    -math.cos(a) * math.cos(h),
    -math.sin(h),
  ];
}

class CatalogStar {
  const CatalogStar(this.name, this.ra, this.dec, this.magnitude);
  final String name;
  final double ra, dec, magnitude;
}

// Small bright-star subset, rounded J2000 RA (hours), Dec (degrees), V magnitude.
const brightStars = <CatalogStar>[
  CatalogStar('Sirius', 6.7525, -16.7161, -1.46),
  CatalogStar('Canopus', 6.3992, -52.6957, -0.74),
  CatalogStar('Arcturus', 14.2610, 19.1824, -0.05),
  CatalogStar('Vega', 18.6156, 38.7837, 0.03),
  CatalogStar('Capella', 5.2782, 45.9980, 0.08),
  CatalogStar('Rigel', 5.2423, -8.2016, 0.13),
  CatalogStar('Procyon', 7.6550, 5.2250, 0.34),
  CatalogStar('Betelgeuse', 5.9195, 7.4071, 0.42),
  CatalogStar('Achernar', 1.6286, -57.2368, 0.46),
  CatalogStar('Hadar', 14.0637, -60.3730, 0.61),
  CatalogStar('Altair', 19.8464, 8.8683, 0.77),
  CatalogStar('Acrux', 12.4433, -63.0991, 0.76),
  CatalogStar('Aldebaran', 4.5987, 16.5093, 0.85),
  CatalogStar('Spica', 13.4199, -11.1613, 0.98),
  CatalogStar('Antares', 16.4901, -26.4320, 1.06),
  CatalogStar('Pollux', 7.7553, 28.0262, 1.14),
  CatalogStar('Fomalhaut', 22.9608, -29.6222, 1.16),
  CatalogStar('Deneb', 20.6905, 45.2803, 1.25),
  CatalogStar('Regulus', 10.1395, 11.9672, 1.35),
  CatalogStar('Alpha Centauri', 14.6601, -60.8339, -0.27),
  CatalogStar('Polaris', 2.5303, 89.2641, 1.98),
];
