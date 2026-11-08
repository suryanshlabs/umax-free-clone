import 'dart:math' as math;

/// Cross-profile measurements derived from front + side photos.
/// All values are estimates in degrees; 0 means "no reading".
class ProfileMetrics {
  const ProfileMetrics({
    this.gonialAngle = 0,
    this.nasolabialAngle = 0,
    this.noseDeviation = 0,
    this.jawWidth = 0,
  });

  final double gonialAngle;
  final double nasolabialAngle;
  final double noseDeviation;
  final double jawWidth;

  bool get hasReading => gonialAngle > 0 || nasolabialAngle > 0;
}

/// Interior angle (degrees) at vertex b between a-b and c-b.
/// Returns 0 when any point is degenerate.
double angleBetween(
  (double, double) a,
  (double, double) b,
  (double, double) c,
) {
  final double v1x = a.$1 - b.$1;
  final double v1y = a.$2 - b.$2;
  final double v2x = c.$1 - b.$1;
  final double v2y = c.$2 - b.$2;
  final double m1 = math.sqrt(v1x * v1x + v1y * v1y);
  final double m2 = math.sqrt(v2x * v2x + v2y * v2y);
  if (m1 == 0 || m2 == 0) return 0;
  double cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
  cos = cos.clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}
