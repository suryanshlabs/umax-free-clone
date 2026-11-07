import 'landmarks.dart';

/// Tunable thresholds that convert raw geometry into 0-100 scores.
///
/// These are **heuristics, not clinical norms**. There is no peer-reviewed,
/// universally accepted scale for "jawline angularity from a selfie", so every
/// band below is an explicit, documented choice rather than a hidden magic
/// number. They live in one place so you can recalibrate against reference
/// photos you trust and keep the rest of the pipeline untouched.
class AnalysisCalibration {
  const AnalysisCalibration({
    this.symmetryTolerancePercent = 0.3,
    this.symmetryPenaltyPerPercent = 12.0,
    this.jawAngleBestDegrees = 90.0,
    this.jawAngleWorstDegrees = 150.0,
    this.thirdsFreeDeviation = 0.12,
    this.thirdsPenaltyPerDeviation = 130.0,
    this.symmetryWeight = 0.38,
    this.jawlineWeight = 0.34,
    this.thirdsWeight = 0.28,
    this.frontalYawThreshold = 0.82,
    this.maxRollDegrees = 8.0,
    this.noticeableAsymmetryPercent = 6.0,
    this.landmarkCount = FaceLandmarks.requiredCount,
  }) : assert(symmetryTolerancePercent >= 0),
       assert(symmetryPenaltyPerPercent > 0),
       assert(jawAngleWorstDegrees > jawAngleBestDegrees),
       assert(thirdsPenaltyPerDeviation > 0),
       assert(symmetryWeight >= 0),
       assert(jawlineWeight >= 0),
       assert(thirdsWeight >= 0),
       assert(frontalYawThreshold > 0 && frontalYawThreshold <= 1);

  /// Asymmetry below this percentage is treated as landmark noise and is not
  /// penalised. MediaPipe's own landmark jitter is roughly ±0.3% on a still.
  final double symmetryTolerancePercent;

  /// Score points lost per percentage point of asymmetry beyond the tolerance.
  /// At 12 points per percent, a 3% difference scores ~68 and a 6% difference
  /// scores ~32 — wide enough to stay informative across most faces.
  final double symmetryPenaltyPerPercent;

  /// Jaw angle that earns a full 100. At or below this the lower face reads
  /// clearly tapered.
  ///
  /// Landmarks 172 and 397 sit roughly halfway along the jawline, so a typical
  /// frontal adult face measures in the 105–125° range here; 90° is a visibly
  /// tapered reference rather than an average.
  final double jawAngleBestDegrees;

  /// Jaw angle that earns 0. Above this the jaw edges are wide and obtuse.
  final double jawAngleWorstDegrees;

  /// Deviation from the 1 : 1 : 1 split that is ignored. Absorbs hairline
  /// placement and landmark noise.
  final double thirdsFreeDeviation;

  /// Score points lost per unit of deviation past [thirdsFreeDeviation].
  final double thirdsPenaltyPerDeviation;

  /// Weighting of each metric in the overall score. Must sum to ~1.
  final double symmetryWeight;
  final double jawlineWeight;
  final double thirdsWeight;

  /// Below this yaw index the head was turned enough that the measurements are
  /// reported with a warning.
  final double frontalYawThreshold;

  /// Head roll beyond this many degrees triggers a warning.
  final double maxRollDegrees;

  /// Asymmetry at or above this percentage adds a "get this looked at if it is
  /// new" note. It is deliberately generous: a few percent is extremely common.
  final double noticeableAsymmetryPercent;

  /// Landmarks required before analysis is attempted.
  final int landmarkCount;
}
