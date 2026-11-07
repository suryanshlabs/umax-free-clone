/// A synthetic 468-point MediaPipe mesh for tests.
///
/// Only the eleven landmarks the analysis reads carry meaningful positions; the
/// rest sit at the origin, exactly like a real mesh for a face that is perfectly
/// symmetric and perfectly flat. The default geometry is a plausible frontal
/// face in arbitrary units (roughly millimetres), and every value can be
/// overridden so a test can isolate one measurement.
library;

import 'package:facial_analysis/core/vector.dart';

/// The mediapipe indices used by the app, mirrored here so tests read clearly.
abstract final class TestLandmarks {
  static const int noseBridge = 1;
  static const int noseBase = 2;
  static const int glabella = 9;
  static const int foreheadTop = 10;
  static const int leftEye = 33;
  static const int chin = 152;
  static const int jawLeft = 172;
  static const int faceLeft = 234;
  static const int rightEye = 263;
  static const int jawRight = 397;
  static const int faceRight = 454;
}

/// Defaults describe a symmetric face: eye corners equidistant from the nose
/// bridge, jaw edges level, thirds split 30 / 15 / 75 across a 120-unit face.
List<Vec2> syntheticFace({
  Vec2 foreheadTop = const Vec2(0, 0),
  Vec2 glabella = const Vec2(0, 30),
  Vec2 noseBridge = const Vec2(0, 22),
  Vec2 noseBase = const Vec2(0, 45),
  Vec2 chin = const Vec2(0, 120),
  Vec2 leftEye = const Vec2(-25, 25),
  Vec2 rightEye = const Vec2(25, 25),
  Vec2 jawLeft = const Vec2(-40, 100),
  Vec2 jawRight = const Vec2(40, 100),
  Vec2 faceLeft = const Vec2(-50, 40),
  Vec2 faceRight = const Vec2(50, 40),
  int count = 468,
}) {
  final List<Vec2> points = List<Vec2>.filled(
    count,
    const Vec2(0, 0),
    growable: false,
  );
  points[TestLandmarks.noseBridge] = noseBridge;
  points[TestLandmarks.noseBase] = noseBase;
  points[TestLandmarks.glabella] = glabella;
  points[TestLandmarks.foreheadTop] = foreheadTop;
  points[TestLandmarks.leftEye] = leftEye;
  points[TestLandmarks.rightEye] = rightEye;
  points[TestLandmarks.chin] = chin;
  points[TestLandmarks.jawLeft] = jawLeft;
  points[TestLandmarks.jawRight] = jawRight;
  points[TestLandmarks.faceLeft] = faceLeft;
  points[TestLandmarks.faceRight] = faceRight;
  return points;
}

/// Scales every point about the origin. Angles and ratios must not change.
List<Vec2> scaledMesh(List<Vec2> points, double factor) {
  return points
      .map((Vec2 point) => Vec2(point.x * factor, point.y * factor))
      .toList(growable: false);
}
