import 'landmarks.dart';

/// Tunable thresholds that convert raw geometry into 0-100 agreement values.
///
/// These are **heuristics, not clinical norms**. There is no peer-reviewed,
/// universally accepted scale for "symmetry from a selfie", so every band below
/// is an explicit, documented choice rather than a hidden magic number. They
/// live in one place so you can recalibrate against reference photos you trust
/// and keep the rest of the pipeline untouched.
///
/// Nothing here rewards attractiveness: each value says how close one
/// measurable geometric property is to a stated reference, and the reference is
/// a convention (mirror symmetry, 1 : 1 : 1 thirds, a tapered chin angle), not a
/// claim about how a face looks to other people.
class AnalysisCalibration {
  const AnalysisCalibration({
    this.symmetryTolerancePercent = 0.6,
    this.symmetryPenaltyPerPercent = 12.0,
    this.jawAngleBestDegrees = 95.0,
    this.jawAngleWorstDegrees = 150.0,
    this.thirdsFreeDeviation = 0.16,
    this.thirdsPenaltyPerDeviation = 130.0,
    this.symmetryWeight = 0.38,
    this.jawlineWeight = 0.34,
    this.thirdsWeight = 0.28,
    this.frontalYawThreshold = 0.82,
    this.maxRollDegrees = 8.0,
    this.noticeableAsymmetryPercent = 6.0,
    this.minFaceWidthRatio = 1.5,
    this.maxFaceWidthRatio = 4.2,
    this.minMeshSpreadRatio = 0.9,
    this.maxMeshSpreadRatio = 3.2,
    this.landmarkCount = FaceLandmarks.requiredCount,
  }) : assert(symmetryTolerancePercent >= 0),
       assert(symmetryPenaltyPerPercent > 0),
       assert(jawAngleWorstDegrees > jawAngleBestDegrees),
       assert(thirdsPenaltyPerDeviation > 0),
       assert(symmetryWeight >= 0),
       assert(jawlineWeight >= 0),
       assert(thirdsWeight >= 0),
       assert(frontalYawThreshold > 0 && frontalYawThreshold <= 1),
       assert(minFaceWidthRatio > 0 && maxFaceWidthRatio > minFaceWidthRatio),
       assert(
         minMeshSpreadRatio > 0 && maxMeshSpreadRatio > minMeshSpreadRatio,
       );

  /// Symmetry residual, as a percentage of the interocular distance, that is
  /// treated as landmark noise rather than as facial asymmetry.
  ///
  /// The residual now averages four mirrored pairs against the face's own
  /// midline, and that average picks up more landmark jitter than a single
  /// pair did, so the tolerance is a little wider than the old 0.3%. Below this
  /// the reading is not distinguishable from the detector's own variation
  /// between two photos of an unchanged face.
  final double symmetryTolerancePercent;

  /// Agreement points lost per percentage point of residual past the tolerance.
  final double symmetryPenaltyPerPercent;

  /// Chin angle that earns the full agreement value. Landmarks 172 and 397 sit
  /// part-way along the jaw contour, so a typical frontal adult face measures
  /// in the 105-125° range here; 95° is a visibly narrow reference rather than
  /// an average.
  final double jawAngleBestDegrees;

  /// Chin angle that earns zero agreement. Above this the jaw contour is wide
  /// and obtuse.
  final double jawAngleWorstDegrees;

  /// Deviation from a 1 : 1 : 1 split that is ignored. The subnasale is derived
  /// from two landmarks and the hairline is the least reliable point in the
  /// mesh, so a free band is necessary before any penalty applies.
  final double thirdsFreeDeviation;

  /// Agreement points lost per unit of deviation past [thirdsFreeDeviation].
  final double thirdsPenaltyPerDeviation;

  /// Weighting of each measurement in the combined index. Must sum to ~1.
  final double symmetryWeight;
  final double jawlineWeight;
  final double thirdsWeight;

  /// Below this yaw index the head was turned enough that the numbers are
  /// reported with a warning.
  final double frontalYawThreshold;

  /// Head roll beyond this many degrees triggers a warning.
  final double maxRollDegrees;

  /// Residual at or above this percentage adds a "if this is new, get it looked
  /// at" note. Deliberately generous: a few percent is extremely common.
  final double noticeableAsymmetryPercent;

  /// Plausible range for face width ÷ interocular distance. A real frontal face
  /// sits around 2.0-2.8; outside this range the mesh is distorted (occlusion,
  /// extreme angle, or a failed detection), so the measurement is refused.
  final double minFaceWidthRatio;
  final double maxFaceWidthRatio;

  /// Plausible range for nasion-to-chin height ÷ interocular distance. A real
  /// face sits around 1.3-2.0.
  final double minMeshSpreadRatio;
  final double maxMeshSpreadRatio;

  /// Landmarks required before analysis is attempted.
  final int landmarkCount;
}
