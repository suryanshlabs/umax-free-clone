import 'landmarks.dart';

/// Every raw geometric measurement the app takes, in the units described on
/// each field. Nothing here is scored yet: this is the "fact" layer that the
/// scoring engine turns into 0-100 agreement values, and keeping it separate
/// means the maths can be unit-tested without any UI or scoring assumptions.
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
    // Matches FaceLandmarks.symmetryPairs; a length is not a const expression.
    this.symmetryPairCount = 4,
    this.meshSpread = 0,
  });

  /// Symmetry residual, as a percentage of the interocular distance:
  ///
  ///     mean over paired landmarks of
  ///       |distance(left point → midline) - distance(right point → midline)|
  ///       / interocular distance * 100
  ///
  /// The midline is the line through the nasion ([FaceLandmarks.nasion]) and
  /// the chin ([FaceLandmarks.chin]); distances are perpendicular to it. 0%
  /// means every mirrored pair sits symmetrically about the face's own midline.
  ///
  /// Measuring against the face's own midline, instead of against one nose
  /// point, removes two errors the old version had: it no longer counts a
  /// large interpupillary distance as asymmetry, and a head that is turned
  /// moves both landmarks of a pair in the same direction, which cancels out
  /// instead of being read as a lopsided face.
  final double eyeAsymmetryPercent;

  /// `d_left / d_right`, mean distance from the midline to the outer eye
  /// corners. 1.0 = mirrored. Kept for display; [eyeAsymmetryPercent] is the
  /// scored value because it averages four pairs.
  final double eyeDistanceRatio;

  /// Angle at the chin (menton) between the two jaw-contour landmarks 172 and
  /// 397. A smaller angle means the jaw edges converge more sharply towards the
  /// chin; a larger, obtuse angle means they spread wider.
  ///
  /// This is a chin angle from a frontal photo, not a clinical gonial angle:
  /// a true gonial angle needs a lateral view and a cephalometric landmark set.
  final double jawAngleDegrees;

  /// Share of total face height held by each third. The three fractions sum to
  /// 1.0. Boundaries follow the standard facial-proportion definition:
  ///
  /// * upper:  hairline (10) → glabella (9)
  /// * middle: glabella (9) → subnasale (midpoint of the nostril wings 94/195)
  /// * lower:  subnasale → chin (152)
  ///
  /// The middle third used to end at landmark 2 (the radix, between the
  /// eyebrows), which made the middle third far too short and pushed the
  /// difference into the lower third. That was a measurement error, not a
  /// property of the face, and it is fixed here.
  final double upperThirdFraction;
  final double middleThirdFraction;
  final double lowerThirdFraction;

  /// Distance between the two outer eye corners, used as the scale reference so
  /// every other distance is face-relative rather than pixel-based.
  final double interocularDistance;

  /// How square-on the head was: the smaller of (nasion → left cheek edge,
  /// nasion → right cheek edge) divided by the larger. 1.0 = frontal; below
  /// ~0.82 the head was visibly turned.
  final double yawIndex;

  /// Signed tilt of the eye-corner line, in degrees, normalised to `(-90, 90]`.
  final double rollDegrees;

  /// Number of landmarks the detector returned (468 for a complete mesh).
  final int landmarkCount;

  /// How many mirrored pairs contributed to [eyeAsymmetryPercent].
  final int symmetryPairCount;

  /// Nasion-to-chin distance, in the same units as [interocularDistance].
  /// Used for plausibility checks: a mesh whose height is not a small multiple
  /// of its eye span is a detector failure, not a face.
  final double meshSpread;

  /// Total absolute deviation of the three thirds from an ideal 1 : 1 : 1 split.
  ///
  /// Each fraction can deviate by at most a certain amount, so this value sits
  /// in `[0, 4/3]`: 0 is an even split.
  double get thirdsDeviation =>
      (upperThirdFraction - idealThirdFraction).abs() +
      (middleThirdFraction - idealThirdFraction).abs() +
      (lowerThirdFraction - idealThirdFraction).abs();

  /// Ratios re-expressed against the middle third, for display. A 1 : 1 : 1
  /// face shows as `1.00 : 1.00 : 1.00`.
  double get upperToMiddleRatio => middleThirdFraction.abs() <= 0.001
      ? 0
      : upperThirdFraction / middleThirdFraction;

  double get lowerToMiddleRatio => middleThirdFraction.abs() <= 0.001
      ? 0
      : lowerThirdFraction / middleThirdFraction;

  /// Largest third, as a readable name. Neutral wording: a larger third is not
  /// better or worse, it is simply the largest.
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
