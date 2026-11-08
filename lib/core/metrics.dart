import 'landmarks.dart';

/// Every raw geometric measurement the app takes, in the units described on
/// each field. Nothing here is scored yet: this is the "fact" layer that the
/// scoring engine turns into 0-100 numbers, and keeping it separate means the
/// maths can be unit-tested without any UI or scoring assumptions.
class RawFaceMetrics {
  const RawFaceMetrics({
    required this.eyeAsymmetryPercent,
    required this.eyeDistanceRatio,
    required this.jawAngleDegrees,
    required this.upperThirdFraction,
    required this.middleThirdFraction,
    required this.lowerThirdFraction,
    required this.interocularDistance,
    required this.yawIndex,
    required this.rollDegrees,
    required this.landmarkCount,
  });

  /// Percentage difference between the two nose-bridge-to-eye-corner distances:
  ///
  ///     |d_left - d_right| / mean(d_left, d_right) * 100
  ///
  /// where `d_left` is the distance from landmark 1 (nose bridge) to landmark 33
  /// and `d_right` the distance from landmark 1 to landmark 263. 0% means the
  /// two halves are exactly mirrored.
  final double eyeAsymmetryPercent;

  /// `d_left / d_right`, signed-ish read of the same thing. 1.0 = mirrored.
  final double eyeDistanceRatio;

  /// Interior angle at the chin (landmark 152) between the two jaw-edge
  /// landmarks 172 and 397. A smaller angle means the jaw edges converge more
  /// sharply towards the chin (a tapered, more angular lower face); a larger,
  /// obtuse angle means the edges spread wider (a squarer, heavier jaw).
  final double jawAngleDegrees;

  /// Share of total forehead-to-chin height held by each third. The three
  /// fractions sum to 1.0.
  ///
  /// * upper:  landmark 10 (hairline) → 9 (between the eyebrows)
  /// * middle: landmark 9 → 2 (top of the nose bridge)
  /// * lower:  landmark 2 → 152 (chin)
  final double upperThirdFraction;
  final double middleThirdFraction;
  final double lowerThirdFraction;

  /// Distance between the two outer eye corners, used internally as the scale
  /// reference so every other distance is face-relative rather than pixel-based.
  final double interocularDistance;

  /// How square-on the head was. Computed as
  /// `min(d_left, d_right) / max(d_left, d_right)` using the nose bridge's
  /// distance to the left (234) and right (454) face edges.
  /// 1.0 = perfectly frontal; below ~0.82 the head was visibly turned.
  final double yawIndex;

  /// Signed tilt of the line between the eye corners, in degrees.
  /// Normalised to `(-90, 90]` so a head tilt always reads as a tilt.
  final double rollDegrees;

  /// Number of landmarks the detector returned (468 for a complete mesh).
  final int landmarkCount;

  /// Total absolute deviation of the three thirds from an ideal 1 : 1 : 1 split.
  ///
  /// Each fraction can deviate by at most a certain amount, so this value sits in
  /// `[0, 4/3]`: 0 is a perfect split, and anything above ~0.5 is visibly uneven.
  double get thirdsDeviation =>
      (upperThirdFraction - idealThirdFraction).abs() +
      (middleThirdFraction - idealThirdFraction).abs() +
      (lowerThirdFraction - idealThirdFraction).abs();

  /// Ratios re-expressed against the middle third, for display. A 1 : 1 : 1 face
  /// shows as `1.00 : 1.00 : 1.00`.
  double get upperToMiddleRatio =>
      middleThirdFraction.abs() <= 0.001
          ? 0
          : upperThirdFraction / middleThirdFraction;

  double get lowerToMiddleRatio =>
      middleThirdFraction.abs() <= 0.001
          ? 0
          : lowerThirdFraction / middleThirdFraction;

  /// Largest third, as a readable name.
  String get dominantThird {
    if (upperThirdFraction >= middleThirdFraction &&
        upperThirdFraction >= lowerThirdFraction) {
      return 'upper third';
    }
    if (lowerThirdFraction >= middleThirdFraction) {
      return 'lower third';
    }
    return 'middle third';
  }
}
