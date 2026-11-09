import 'dart:math' as math;

import 'calibration.dart';
import 'landmarks.dart';
import 'metrics.dart';
import 'vector.dart';

/// Thrown for anything the user can act on: no face, partial mesh, garbage
/// coordinates, an implausible pose. Carries a message that is safe to show
/// directly in the UI.
class FacialAnalysisException implements Exception {
  const FacialAnalysisException(this.message);

  final String message;

  @override
  String toString() => 'FacialAnalysisException: $message';
}

/// Turns 468 MediaPipe face-mesh landmarks into the three measurements the app
/// reports: symmetry residual, chin angle and facial thirds.
///
/// The class is intentionally pure: no Flutter imports, no I/O, no async. Given
/// the same points it always returns the same numbers, which is what makes the
/// maths unit-testable. All points must already be in one uniform coordinate
/// space (see [Vec2]); [FaceMeshReader] handles that conversion.
///
/// Every landmark index used here is documented in [FaceLandmarks] against the
/// canonical MediaPipe topology. The pipeline is O(1): a fixed set of landmark
/// lookups and a handful of square roots.
class FacialAnalysisService {
  const FacialAnalysisService({this.calibration = const AnalysisCalibration()});

  final AnalysisCalibration calibration;

  /// Smallest denominator worth dividing by. Every ratio below is measured in
  /// fractions of the image height, so a real face part is tens of times this
  /// large — anything at or below it is a collapsed mesh, not a measurement.
  static const double minScale = 0.001;

  /// Measures [points] and returns the raw geometry.
  ///
  /// Throws [FacialAnalysisException] when the mesh is incomplete, contains
  /// non-finite values, is degenerate (zero-length reference distance), is
  /// vertically impossible (upside-down or collapsed), or has a face-width to
  /// eye-span ratio no real face produces — all cases where a score would be
  /// meaningless or misleading.
  RawFaceMetrics measure(List<Vec2> points) {
    if (points.length < calibration.landmarkCount) {
      throw FacialAnalysisException(
        'Face mesh incomplete: expected ${calibration.landmarkCount} '
        'landmarks, received ${points.length}.',
      );
    }

    final Vec2 nasion = _point(points, FaceLandmarks.nasion);
    final Vec2 glabella = _point(points, FaceLandmarks.glabella);
    final Vec2 foreheadTop = _point(points, FaceLandmarks.foreheadTop);
    final Vec2 chin = _point(points, FaceLandmarks.chin);
    final Vec2 leftEyeOuter = _point(points, FaceLandmarks.leftEyeOuter);
    final Vec2 rightEyeOuter = _point(points, FaceLandmarks.rightEyeOuter);
    final Vec2 jawLeft = _point(points, FaceLandmarks.jawEdgeLeft);
    final Vec2 jawRight = _point(points, FaceLandmarks.jawEdgeRight);
    final Vec2 faceLeft = _point(points, FaceLandmarks.faceEdgeLeft);
    final Vec2 faceRight = _point(points, FaceLandmarks.faceEdgeRight);
    final Vec2 subnasale = _midpoint(
      _point(points, FaceLandmarks.noseWingLeft),
      _point(points, FaceLandmarks.noseWingRight),
    );

    // ---- Scale and plausibility ------------------------------------------
    final double interocular = leftEyeOuter.distanceTo(rightEyeOuter);
    if (interocular <= minScale || !interocular.isFinite) {
      throw const FacialAnalysisException(
        'The two eye corners are on top of each other, so the mesh cannot be '
        'scaled. Retake the photo with your whole face in frame.',
      );
    }

    final double faceWidth = faceLeft.distanceTo(faceRight);
    final double widthRatio = faceWidth / interocular;
    if (!widthRatio.isFinite ||
        widthRatio < calibration.minFaceWidthRatio ||
        widthRatio > calibration.maxFaceWidthRatio) {
      throw const FacialAnalysisException(
        'The face mesh came back distorted (the cheek edges are the wrong '
        'distance apart relative to the eyes). This is usually a partly '
        'occluded face or a photo taken at a steep angle. Retake it straight on.',
      );
    }

    // A real face has the hairline above the brow, the brow above the nose base
    // and the nose base above the chin. If those are inverted the mesh is
    // upside down (or the detector locked onto something that is not a face).
    final double faceHeight = nasion.distanceTo(chin);
    final double verticalSlack = faceHeight * 0.02;
    if (glabella.y > subnasale.y + verticalSlack ||
        subnasale.y > chin.y + verticalSlack) {
      throw const FacialAnalysisException(
        'The landmarks are not in a face-like order (chin above the nose). '
        'Retake the photo upright with your whole face in the guide.',
      );
    }

    // ---- 1. Symmetry residual --------------------------------------------
    // Perpendicular distance from each paired landmark to the midline through
    // the nasion and chin. Averaging four pairs (outer eyes, inner eyes, mouth
    // corners, cheek edges) is far less sensitive to one noisy landmark than
    // the single nose-bridge-to-eye measure this replaced.
    final Vec2 midlineDirection = chin - nasion;
    final List<double> pairResiduals = <double>[];
    double leftOuterDistance = 0;
    double rightOuterDistance = 0;
    for (final (int left, int right) in FaceLandmarks.symmetryPairs) {
      final Vec2 leftPoint = _point(points, left);
      final Vec2 rightPoint = _point(points, right);
      final double dLeft = _perpendicularDistance(
        leftPoint,
        nasion,
        midlineDirection,
      );
      final double dRight = _perpendicularDistance(
        rightPoint,
        nasion,
        midlineDirection,
      );
      pairResiduals.add((dLeft - dRight).abs() / interocular * 100);
      if (left == FaceLandmarks.leftEyeOuter) {
        leftOuterDistance = dLeft;
        rightOuterDistance = dRight;
      }
    }
    final double eyeAsymmetryPercent =
        pairResiduals.reduce((double a, double b) => a + b) /
        pairResiduals.length;

    // ---- 2. Chin angle ---------------------------------------------------
    final double jawAngleDegrees = (jawLeft - chin).angleTo(jawRight - chin);

    // ---- 3. Facial thirds ------------------------------------------------
    final double upper = (glabella.y - foreheadTop.y).abs();
    final double middle = (subnasale.y - glabella.y).abs();
    final double lower = (chin.y - subnasale.y).abs();
    final double totalHeight = upper + middle + lower;
    if (totalHeight <= minScale || !totalHeight.isFinite) {
      throw const FacialAnalysisException(
        'The forehead-to-chin span measured as zero. Retake the photo with the '
        'full face, hairline included, inside the guide.',
      );
    }

    // ---- Pose ------------------------------------------------------------
    final double leftHalf = nasion.distanceTo(faceLeft);
    final double rightHalf = nasion.distanceTo(faceRight);
    final double widerHalf = math.max(leftHalf, rightHalf);
    final double yawIndex = widerHalf <= minScale
        ? 1.0
        : math.min(leftHalf, rightHalf) / widerHalf;

    return RawFaceMetrics(
      eyeAsymmetryPercent: eyeAsymmetryPercent,
      eyeDistanceRatio: rightOuterDistance <= minScale
          ? 1.0
          : leftOuterDistance / rightOuterDistance,
      jawAngleDegrees: jawAngleDegrees,
      upperThirdFraction: upper / totalHeight,
      middleThirdFraction: middle / totalHeight,
      lowerThirdFraction: lower / totalHeight,
      interocularDistance: interocular,
      yawIndex: yawIndex.clamp(0.0, 1.0),
      rollDegrees: _normalisedRoll(leftEyeOuter, rightEyeOuter),
      landmarkCount: points.length,
      symmetryPairCount: pairResiduals.length,
      meshSpread: faceHeight,
    );
  }

  Vec2 _point(List<Vec2> points, int index) {
    if (index < 0 || index >= points.length) {
      throw FacialAnalysisException(
        'Landmark $index is outside the ${points.length}-point mesh.',
      );
    }
    final Vec2 point = points[index];
    if (!point.isFinite) {
      throw FacialAnalysisException(
        'Landmark $index is not a finite coordinate.',
      );
    }
    return point;
  }

  Vec2 _midpoint(Vec2 a, Vec2 b) => Vec2((a.x + b.x) / 2, (a.y + b.y) / 2);

  /// Absolute perpendicular distance from [point] to the line through [origin]
  /// with direction [direction]. An unsigned distance is right for this check:
  /// which side of the midline a landmark falls on is exactly what mirroring
  /// flips, and the pair difference below captures it.
  double _perpendicularDistance(Vec2 point, Vec2 origin, Vec2 direction) {
    final double length = direction.magnitude;
    if (length <= 1e-9) {
      return 0;
    }
    final Vec2 offset = point - origin;
    // |cross(direction, offset)| / |direction|
    final double cross = direction.x * offset.y - direction.y * offset.x;
    return (cross / length).abs();
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
