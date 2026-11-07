import 'dart:math' as math;

import 'calibration.dart';
import 'landmarks.dart';
import 'metrics.dart';
import 'vector.dart';

/// Thrown for anything the user can act on: no face, partial mesh, garbage
/// coordinates. Carries a message that is safe to show directly in the UI.
class FacialAnalysisException implements Exception {
  const FacialAnalysisException(this.message);

  final String message;

  @override
  String toString() => 'FacialAnalysisException: $message';
}

/// Turns 468 MediaPipe face-mesh landmarks into the three measurements the app
/// scores: eye symmetry, jawline angularity and facial thirds.
///
/// The class is intentionally pure: no Flutter imports, no I/O, no async. Given
/// the same points it always returns the same numbers, which is what makes the
/// maths unit-testable. All points must already be in one uniform coordinate
/// space (see [Vec2]); [FaceMeshReader] handles that conversion.
///
/// Complexity is O(1) with respect to landmark count — exactly 11 landmark
/// lookups and a handful of square roots — so it is safe to call at camera
/// frame rate if you later move from still capture to live analysis.
class FacialAnalysisService {
  const FacialAnalysisService({this.calibration = const AnalysisCalibration()});

  final AnalysisCalibration calibration;

  /// Measures [points] and returns the raw geometry.
  ///
  /// Throws [FacialAnalysisException] when the mesh is incomplete, contains
  /// non-finite values, or is degenerate (a zero-length reference distance),
  /// because every downstream score would be meaningless.
  RawFaceMetrics measure(List<Vec2> points) {
    if (points.length < calibration.landmarkCount) {
      throw FacialAnalysisException(
        'Face mesh incomplete: expected ${calibration.landmarkCount} '
        'landmarks, received ${points.length}.',
      );
    }

    final Vec2 noseBridge = _point(points, FaceLandmarks.noseBridge);
    final Vec2 leftEye = _point(points, FaceLandmarks.leftEyeCorner);
    final Vec2 rightEye = _point(points, FaceLandmarks.rightEyeCorner);
    final Vec2 chin = _point(points, FaceLandmarks.chin);
    final Vec2 jawLeft = _point(points, FaceLandmarks.jawEdgeLeft);
    final Vec2 jawRight = _point(points, FaceLandmarks.jawEdgeRight);
    final Vec2 foreheadTop = _point(points, FaceLandmarks.foreheadTop);
    final Vec2 glabella = _point(points, FaceLandmarks.glabella);
    final Vec2 noseBase = _point(points, FaceLandmarks.noseBase);
    final Vec2 faceLeft = _point(points, FaceLandmarks.faceEdgeLeft);
    final Vec2 faceRight = _point(points, FaceLandmarks.faceEdgeRight);

    final double interocular = leftEye.distanceTo(rightEye);
    if (interocular <= 1e-9 || !interocular.isFinite) {
      throw const FacialAnalysisException(
        'The two eye corners are on top of each other, so the mesh cannot be '
        'scaled. Retake the photo with your whole face in frame.',
      );
    }

    // ---- 1. Eye symmetry -------------------------------------------------
    // Distance from the nose-bridge midline anchor to each outer eye corner.
    // Using the midline point rather than the eye-to-eye span means a face that
    // sits perfectly straight but has one eye slightly further from the centre
    // still registers, which is the asymmetry that is actually visible.
    final double dLeft = noseBridge.distanceTo(leftEye);
    final double dRight = noseBridge.distanceTo(rightEye);
    final double meanEyeDistance = (dLeft + dRight) / 2;
    final double eyeAsymmetryPercent = meanEyeDistance <= 1e-9
        ? 0.0
        : ((dLeft - dRight).abs() / meanEyeDistance) * 100;

    // ---- 2. Jawline angularity -------------------------------------------
    // Angle at the chin between the two jaw edges (law of cosines via
    // acos(dot / |a||b|)). Symmetric under mirroring, so it does not matter
    // which jaw edge is "left" on screen.
    final double jawAngleDegrees = (jawLeft - chin).angleTo(jawRight - chin);

    // ---- 3. Facial thirds -------------------------------------------------
    // Vertical (y) spans between the requested landmarks. Ratios of y-spans are
    // scale-free, so this metric survives any uniform zoom — but it does depend
    // on the head being level, hence the roll warning later.
    final double upper = (glabella.y - foreheadTop.y).abs();
    final double middle = (noseBase.y - glabella.y).abs();
    final double lower = (chin.y - noseBase.y).abs();
    final double totalHeight = upper + middle + lower;
    if (totalHeight <= 1e-9 || !totalHeight.isFinite) {
      throw const FacialAnalysisException(
        'The forehead-to-chin span measured as zero. Retake the photo with the '
        'full face, hairline included, inside the guide.',
      );
    }

    // ---- Pose sanity checks ----------------------------------------------
    final double leftHalf = noseBridge.distanceTo(faceLeft);
    final double rightHalf = noseBridge.distanceTo(faceRight);
    final double widerHalf = math.max(leftHalf, rightHalf);
    final double yawIndex = widerHalf <= 1e-9
        ? 1.0
        : math.min(leftHalf, rightHalf) / widerHalf;

    return RawFaceMetrics(
      eyeAsymmetryPercent: eyeAsymmetryPercent,
      eyeDistanceRatio: dRight <= 1e-9 ? 1.0 : dLeft / dRight,
      jawAngleDegrees: jawAngleDegrees,
      upperThirdFraction: upper / totalHeight,
      middleThirdFraction: middle / totalHeight,
      lowerThirdFraction: lower / totalHeight,
      interocularDistance: interocular,
      yawIndex: yawIndex.clamp(0.0, 1.0),
      rollDegrees: _normalisedRoll(leftEye, rightEye),
      landmarkCount: points.length,
    );
  }

  Vec2 _point(List<Vec2> points, int index) {
    final Vec2 point = points[index];
    if (!point.isFinite) {
      throw FacialAnalysisException(
        'Landmark $index is not a finite coordinate.',
      );
    }
    return point;
  }

  /// Tilt of the eye line relative to horizontal, folded into `(-90, 90]` so a
  /// left-right ordering flip cannot masquerade as a 180° rotation.
  double _normalisedRoll(Vec2 leftEye, Vec2 rightEye) {
    final Vec2 eyeVector = rightEye - leftEye;
    if (eyeVector.magnitude <= 1e-9) {
      return 0;
    }
    double degrees = math.atan2(eyeVector.y, eyeVector.x) * 180 / math.pi;
    if (degrees > 90) {
      degrees -= 180;
    } else if (degrees <= -90) {
      degrees += 180;
    }
    return degrees;
  }
}
