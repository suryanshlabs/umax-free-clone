import 'package:facial_analysis/core/metrics.dart';

/// A plausible frontal face for the scoring tests: perfectly mirrored unless
/// told otherwise, a typical 112 degree jaw angle, and an even third split.
RawFaceMetrics faceMetrics({
  double asymmetry = 0.9,
  double jawAngle = 112,
  double upper = 0.333,
  double middle = 0.334,
  double lower = 0.333,
  double yawIndex = 0.95,
  double rollDegrees = 0,
}) {
  return RawFaceMetrics(
    eyeAsymmetryPercent: asymmetry,
    eyeDistanceRatio: 1 + asymmetry / 100,
    jawAngleDegrees: jawAngle,
    upperThirdFraction: upper,
    middleThirdFraction: middle,
    lowerThirdFraction: lower,
    interocularDistance: 0.31,
    yawIndex: yawIndex,
    rollDegrees: rollDegrees,
    landmarkCount: 468,
  );
}
