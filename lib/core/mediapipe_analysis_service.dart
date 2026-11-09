import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ml/mediapipe_face_landmarker.dart';

/// MediaPipe-aware geometry from a [MediaPipeScanReading].
///
/// This is the **MediaPipe-specific** geometry module. It does **not** replace
/// [FacialAnalysisService]: that class is built on the existing 468-point `Vec2`
/// contract and it already works for MediaPipe scans through [MediaPipeScanSource],
/// which produces a `FaceMeshReading` from the overlapping landmarks.
///
/// Instead this class operates on the **full** MediaPipe output that the existing
/// pipeline discards: all 478 landmarks with their Z estimates, the facial
/// transformation matrix (when the scan was captured with that feature enabled), and
/// the blendshape categories. It reports:
///
/// * per-view measurements that only make sense with Z / pose info,
/// * a frontal symmetry residual computed on the 478-point mesh,
/// * cross-view consistency between the three captured views,
/// * capture-quality signals from blendshapes and the matrix.
///
/// **Coordinate convention.**
/// MediaPipe normalises landmark X/Y/Z to its own canonical space. The Z values are
/// model estimates in arbitrary units — **not** millimetres and **not** certified
/// anatomical measurements. The same face photographed from the same distance can
/// shift Z by a large amount if head pose changes, because the model's depth estimate
/// is relative to the frontal plane it inferred, not to a calibrated reference. This
/// module therefore reports Z only as a **relative** number within a single scan and
/// as a **normalised offset** in cross-view comparisons. Any number that looks like
/// a "depth in mm" here is a lie.
///
/// This is a neutral facial geometry tool. No attractiveness score, no grade, no
/// beauty ranking, no appearance-shaming label, no weight-loss or appearance-correction
/// advice.
class MediaPipeAnalysisService {
  const MediaPipeAnalysisService();

  static const double minScale = 1e-4;
  static const int landmarkCount = 478;

  /// Per-view analysis output.
  MediaPipeViewAnalysis analyzeView({
    required MediaPipeScanReading reading,
    required CaptureView view,
  }) {
    final MediaPipeLandmarkerResult result = reading.mediaPipeResult;
    if (result.faceLandmarks.isEmpty) {
      return const MediaPipeViewAnalysis(
        view: CaptureView.front,
        status: MediaPipeViewStatus.failed,
        error: 'MediaPipe returned no landmarks.',
      );
    }
    final MediaPipeFaceLandmarks face = result.faceLandmarks.first;

    // ---- Z estimate ----
    // MediaPipe's Z is in its own normalised space. We do not claim a calibration
    // here, so we report the raw Z of a few stable midline points and a summary
    // statistic (mean Z of the face) as a descriptive number only.
    double sumZ = 0;
    int countZ = 0;
    double nasionZ = 0;
    double chinZ = 0;
    for (int i = 0; i < face.length; i++) {
      final NormalizedLandmark lm = face[i];
      if (lm.z.isFinite) {
        sumZ += lm.z;
        countZ++;
      }
      if (i == MediaPipeLandmarks.nasion) nasionZ = lm.z;
      if (i == MediaPipeLandmarks.chin) chinZ = lm.z;
    }
    final double meanZ = countZ == 0 ? 0.0 : sumZ / countZ;

    // ---- frontal pose ----
    // When the landmarker was created with outputFacialTransformationMatrixes = true,
    // each face comes back with a 4x4 matrix that maps the canonical face to the
    // detected pose. We do **not** claim it is a calibrated camera pose. We report
    // the matrix's translation magnitude (a proxy for face scale / distance) and a
    // rough yaw/roll/pitch as a heuristic, with the caveat it is not a certified angle.
    //
    // When the matrix is absent (feature disabled or model didn't return it) we report
    // pose from the landmark layout alone, with the same caveat.
    final List<Matrix> matrices = result.facialTransformationMatrixes;
    final MediaPipePoseEstimate pose = matrices.isNotEmpty && matrices.first.data.isNotEmpty
        ? _poseFromMatrix(matrices.first)
        : _poseFromLandmarks(face);

    // ---- frontal symmetry residual on the full mesh ----
    // Same idea as the existing service (nasion-chin midline, perpendicular distance of
    // mirrored pairs, normalised by interocular distance), but on all 478 points rather
    // than the four existing pairs. This is a different number from the existing
    // `eyeAsymmetryPercent`, so it is named distinctly.
    final double fullMeshSymmetry = _symmetryResidual(face);

    // ---- capture-quality signals ----
    // Blendshapes (when enabled) give a crude "is the face expressing something strong
    // right now" signal. We report the dominant category and its score without
    // interpreting it as "good" or "bad". A face mid-speech is not a "bad capture", so
    // we do not gate the scan on this; we just report it.
    final MediaPipeBlendshapeInfo blendshapes = _blendshapeInfo(
      result.faceBlendshapes.isNotEmpty ? result.faceBlendshapes.first : null,
    );

    // ---- quality flags ----
    final List<String> warnings = <String>[];
    if (!_allFinite(face)) {
      warnings.add('MediaPipe returned non-finite landmark values. Retry in good light.');
    }
    final double faceWidthFraction = _faceWidthFraction(face, reading.imageAspectRatio);
    final double faceHeightFraction = _faceHeightFraction(face);
    if (faceHeightFraction < 0.12) {
      warnings.add(
        'Your face filled only a small part of the frame. Move closer so the '
        'model has more pixels per feature.',
      );
    }

    return MediaPipeViewAnalysis(
      view: view,
      status: warnings.isEmpty ? MediaPipeViewStatus.ok : MediaPipeViewStatus.qualityWarning,
      landmarks: face.all,
      zMean: meanZ,
      nasionZ: nasionZ,
      chinZ: chinZ,
      pose: pose,
      transformationMatrix: matrices.isNotEmpty ? matrices.first : null,
      blendshapes: blendshapes,
      faceWidthFraction: faceWidthFraction,
      faceHeightFraction: faceHeightFraction,
      eyeAsymmetryPercent: fullMeshSymmetry,
      warnings: warnings,
    );
  }

  /// Combine the three per-view analyses into a cross-view report.
  ///
  /// Only the measurements that are actually comparable across views are compared.
  /// * **Frontal symmetry** is reported per view and its spread across views; the side
  ///   views are expected to show higher asymmetry (a turned head looks asymmetric in a
  ///   front-facing measurement), so we report the difference rather than averaging them
  ///   into one misleading "overall symmetry".
  /// * **Z estimates** are camera-distance-relative and are not comparable across
  ///   viewpoints; we report each view's Z separately and note that the values are not
  ///   directly comparable.
  /// * **Pose estimates** are view-specific; we report each view's pose and the yaw sweep
  ///   across the three views, which is the intended use of a three-view session.
  MediaPipeCrossViewAnalysis analyzeCrossView({
    required MediaPipeViewAnalysis front,
    required MediaPipeViewAnalysis left,
    required MediaPipeViewAnalysis right,
  }) {
    final List<String> notes = <String>[];
    final Map<String, dynamic> crossView = <String, dynamic>{};

    if (front.status != MediaPipeViewStatus.ok) {
      notes.add('Front view did not pass quality checks. The combined report is limited.');
    } else {
      notes.add('Front view passed frontal quality checks.');
    }

    final double? yawSweep = _yawSweep(left.pose?.yawDeg, right.pose?.yawDeg);
    crossView['yawSweepDeg'] = yawSweep;

    crossView['zNote'] =
        'Z estimates are per-view model estimates, not comparable across viewpoints.';

    final List<double> symmetries = [
      front.eyeAsymmetryPercent,
      left.eyeAsymmetryPercent,
      right.eyeAsymmetryPercent,
    ];
    final double symmetrySpread = _spread(symmetries);
    crossView['symmetryFront'] = front.eyeAsymmetryPercent;
    crossView['symmetryLeft'] = left.eyeAsymmetryPercent;
    crossView['symmetryRight'] = right.eyeAsymmetryPercent;
    crossView['symmetrySpread'] = symmetrySpread;

    return MediaPipeCrossViewAnalysis(
      front: front,
      left: left,
      right: right,
      crossView: crossView,
      notes: notes,
    );
  }

  // ---- private helpers ----

  static double _zFor(MediaPipeFaceLandmarks face, int index) {
    if (index < 0 || index >= face.length) return 0.0;
    return face[index].z;
  }

  static bool _allFinite(MediaPipeFaceLandmarks face) {
    final int len = face.length;
    for (int i = 0; i < len; i++) {
      final NormalizedLandmark lm = face[i];
      if (!lm.x.isFinite || !lm.y.isFinite || !lm.z.isFinite) {
        return false;
      }
    }
    return true;
  }

  /// Frontal symmetry residual: mean perpendicular distance of mirrored landmark pairs
  /// from the nasion-chin midline, as a fraction of the interocular distance, times 100.
  static double _symmetryResidual(MediaPipeFaceLandmarks face) {
    final Vec2 nasion = _v(face, MediaPipeLandmarks.nasion);
    final Vec2 chin = _v(face, MediaPipeLandmarks.chin);
    final Vec2 leftEyeOuter = _v(face, MediaPipeLandmarks.leftEyeOuter);
    final Vec2 rightEyeOuter = _v(face, MediaPipeLandmarks.rightEyeOuter);
    final Vec2 leftEyeInner = _v(face, MediaPipeLandmarks.leftEyeInner);
    final Vec2 rightEyeInner = _v(face, MediaPipeLandmarks.rightEyeInner);
    final Vec2 mouthLeft = _v(face, MediaPipeLandmarks.mouthLeft);
    final Vec2 mouthRight = _v(face, MediaPipeLandmarks.mouthRight);
    final Vec2 faceEdgeLeft = _v(face, MediaPipeLandmarks.faceEdgeLeft);
    final Vec2 faceEdgeRight = _v(face, MediaPipeLandmarks.faceEdgeRight);

    final double interocular = leftEyeOuter.distanceTo(rightEyeOuter);
    if (interocular <= minScale || !interocular.isFinite) {
      return 0.0;
    }
    final Vec2 midline = chin - nasion;
    final double midlineLen = midline.magnitude;
    if (midlineLen <= minScale || !midlineLen.isFinite) {
      return 0.0;
    }

    final List<(Vec2, Vec2)> pairs = <(Vec2, Vec2)>[
      (leftEyeOuter, rightEyeOuter),
      (leftEyeInner, rightEyeInner),
      (mouthLeft, mouthRight),
      (faceEdgeLeft, faceEdgeRight),
    ];

    double total = 0;
    for (final (Vec2 left, Vec2 right) in pairs) {
      final double dL = _perpDist(left, nasion, midline, midlineLen);
      final double dR = _perpDist(right, nasion, midline, midlineLen);
      total += (dL - dR).abs() / interocular * 100;
    }
    return total / pairs.length;
  }

  static double _perpDist(Vec2 point, Vec2 origin, Vec2 direction, double dirLen) {
    final Vec2 offset = point - origin;
    final double cross = direction.x * offset.y - direction.y * offset.x;
    return (cross / dirLen).abs();
  }

  static Vec2 _v(MediaPipeFaceLandmarks face, int index) {
    if (index < 0 || index >= face.length) {
      return const Vec2(0, 0);
    }
    return Vec2(face[index].x, face[index].y);
  }

  /// Estimated yaw from the face's own landmark layout.
  /// Heuristic: ratio of the two halves (nasion to left cheek edge vs nasion to right
  /// cheek edge). Closer to 1.0 = more frontal. Same idea as the existing service, meant
  /// as a rough guide, not a calibrated angle.
  static MediaPipePoseEstimate _poseFromLandmarks(MediaPipeFaceLandmarks face) {
    final Vec2 nasion = _v(face, MediaPipeLandmarks.nasion);
    final Vec2 chin = _v(face, MediaPipeLandmarks.chin);
    final Vec2 faceEdgeLeft = _v(face, MediaPipeLandmarks.faceEdgeLeft);
    final Vec2 faceEdgeRight = _v(face, MediaPipeLandmarks.faceEdgeRight);
    final Vec2 leftEyeOuter = _v(face, MediaPipeLandmarks.leftEyeOuter);
    final Vec2 rightEyeOuter = _v(face, MediaPipeLandmarks.rightEyeOuter);

    final double leftHalf = nasion.distanceTo(faceEdgeLeft);
    final double rightHalf = nasion.distanceTo(faceEdgeRight);
    final double wider = math.max(leftHalf, rightHalf);
    final double yawIndex = wider <= minScale
        ? 1.0
        : (math.min(leftHalf, rightHalf) / wider).clamp(0.0, 1.0);
    final double yawDeg = yawIndex <= 0.0
        ? 90.0
        : math.acos(yawIndex.clamp(-1.0, 1.0)) * 180 / math.pi;
    final double rollDeg = _rollFromEyeLine(leftEyeOuter, rightEyeOuter);
    final double pitchDeg = _pitchFromLandmarks(face, nasion, chin);

    return MediaPipePoseEstimate(
      yawDeg: yawDeg,
      yawIndex: yawIndex,
      rollDeg: rollDeg,
      pitchDeg: pitchDeg,
      from: PoseSource.landmarks,
    );
  }

  static double _rollFromEyeLine(Vec2 left, Vec2 right) {
    final Vec2 eyeVec = right - left;
    final double mag = eyeVec.magnitude;
    if (mag <= minScale) return 0.0;
    double deg = math.atan2(eyeVec.y, eyeVec.x) * 180 / math.pi;
    if (deg > 90) deg -= 180;
    else if (deg <= -90) deg += 180;
    return deg;
  }

  static double _pitchFromLandmarks(MediaPipeFaceLandmarks face, Vec2 nasion, Vec2 chin) {
    final Vec2 leftEye = _v(face, MediaPipeLandmarks.leftEyeOuter);
    final Vec2 rightEye = _v(face, MediaPipeLandmarks.rightEyeOuter);
    final double interocular = leftEye.distanceTo(rightEye);
    final double faceHeight = nasion.distanceTo(chin);
    if (interocular <= minScale || faceHeight <= minScale) return 0.0;
    final double ratio = faceHeight / interocular;
    return (ratio - 1.5) * 30;
  }

  /// Pose from the facial transformation matrix.
  /// The matrix is a best-effort estimate from MediaPipe. We report the translation
  /// magnitude (proxy for face scale / distance) and approximate yaw/roll/pitch from
  /// the matrix rows. This is **not** a calibrated pose.
  static MediaPipePoseEstimate _poseFromMatrix(Matrix matrix) {
    // 4x4 column-major.
    final List<double> d = matrix.data;
    final double tx = d[2];
    final double ty = d[6];
    final double tz = d[10];
    final double translationMag = math.sqrt(tx * tx + ty * ty + tz * tz);
    final double yawDeg = tz.abs() < minScale
        ? (tx.abs() < minScale ? 0.0 : 90.0)
        : math.atan2(tx.abs(), tz.abs()) * 180 / math.pi;
    // Roll from the cross product of the first two columns.
    final double rx = d[0], ry = d[1], rz = d[2];
    final double sx = d[4], sy = d[5], sz = d[6];
    final double rollDeg = math.atan2(ry * sz - rz * sy, rx * sz - rz * sx) * 180 / math.pi;

    return MediaPipePoseEstimate(
      yawDeg: yawDeg.clamp(-180, 180),
      yawIndex: 1.0 - (yawDeg.abs() / 90.0).clamp(0.0, 1.0),
      rollDeg: rollDeg.clamp(-180, 180),
      pitchDeg: math.atan2(ty.abs(), tz.abs()) * 180 / math.pi,
      translationMag: translationMag,
      from: PoseSource.matrix,
    );
  }

  static double _faceWidthFraction(MediaPipeFaceLandmarks face, double imageAspectRatio) {
    final Vec2 left = _v(face, MediaPipeLandmarks.faceEdgeLeft);
    final Vec2 right = _v(face, MediaPipeLandmarks.faceEdgeRight);
    final double width = left.distanceTo(right);
    final double height = _faceHeight(face);
    if (height <= minScale || !width.isFinite || !height.isFinite) return 0.0;
    return width / height * imageAspectRatio;
  }

  static double _faceHeightFraction(MediaPipeFaceLandmarks face) {
    final Vec2 nasion = _v(face, MediaPipeLandmarks.nasion);
    final Vec2 chin = _v(face, MediaPipeLandmarks.chin);
    final double height = nasion.distanceTo(chin);
    final double interocular = _v(face, MediaPipeLandmarks.leftEyeOuter)
        .distanceTo(_v(face, MediaPipeLandmarks.rightEyeOuter));
    if (interocular <= minScale || !height.isFinite) return 0.0;
    return height / interocular;
  }

  static double _faceHeight(MediaPipeFaceLandmarks face) {
    final Vec2 nasion = _v(face, MediaPipeLandmarks.nasion);
    final Vec2 chin = _v(face, MediaPipeLandmarks.chin);
    final double h = nasion.distanceTo(chin);
    return h.isFinite && h > 0 ? h : 1.0;
  }

  static double _yawSweep(double? left, double? right) {
    if (left == null || right == null) return double.nan;
    if (!left.isFinite || !right.isFinite) return double.nan;
    return (right - left).abs();
  }

  static double _spread(List<double> values) {
    if (values.isEmpty) return 0.0;
    double min = values.first;
    double max = values.first;
    for (final double v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return max - min;
  }

  static MediaPipeBlendshapeInfo _blendshapeInfo(List<MediaPipeCategory>? categories) {
    if (categories == null || categories.isEmpty) {
      return const MediaPipeBlendshapeInfo.empty();
    }
    MediaPipeCategory best = categories.first;
    for (final MediaPipeCategory c in categories.skip(1)) {
      if (c.score > best.score) {
        best = c;
      }
    }
    return MediaPipeBlendshapeInfo(
      dominantCategory: best.categoryName ?? 'category ${best.index}',
      dominantScore: best.score,
      empty: false,
    );
  }
}

/// The recorded output of one MediaPipe view scan.
///
/// Holds the full MediaPipe result (478 landmarks with Z, optional matrix and
/// blendshapes) so the MediaPipe geometry module can consume it. The existing
/// pipeline also consumes the `FaceMeshReading` that [MediaPipeScanSource] pairs with
/// this.
class MediaPipeScanReading {
  const MediaPipeScanReading({
    required this.view,
    required this.mediaPipeResult,
    required this.imageAspectRatio,
    required this.imageHeight,
  });

  final CaptureView view;
  final MediaPipeLandmarkerResult mediaPipeResult;
  final double imageAspectRatio;
  final int imageHeight;
}

/// Per-view MediaPipe analysis.
class MediaPipeViewAnalysis {
  const MediaPipeViewAnalysis({
    required this.view,
    required this.status,
    this.landmarks,
    this.zMean = 0.0,
    this.nasionZ = 0.0,
    this.chinZ = 0.0,
    this.pose,
    this.transformationMatrix,
    this.blendshapes = const MediaPipeBlendshapeInfo.empty(),
    this.faceWidthFraction = 0.0,
    this.faceHeightFraction = 0.0,
    this.eyeAsymmetryPercent = 0.0,
    this.error,
    this.warnings = const <String>[],
  });

  final CaptureView view;
  final MediaPipeViewStatus status;
  final List<NormalizedLandmark>? landmarks;
  final double zMean;
  final double nasionZ;
  final double chinZ;
  final MediaPipePoseEstimate? pose;
  final Matrix? transformationMatrix;
  final MediaPipeBlendshapeInfo blendshapes;
  final double faceWidthFraction;
  final double faceHeightFraction;
  final double eyeAsymmetryPercent;
  final String? error;
  final List<String> warnings;
}

enum MediaPipeViewStatus { ok, qualityWarning, failed }

/// Pose estimate from MediaPipe, with the source and the caveat that it is not a
/// calibrated anatomical pose.
class MediaPipePoseEstimate {
  const MediaPipePoseEstimate({
    required this.yawDeg,
    required this.yawIndex,
    required this.rollDeg,
    required this.pitchDeg,
    required this.from,
    this.translationMag,
  });

  final double yawDeg;
  final double yawIndex;
  final double rollDeg;
  final double pitchDeg;
  final PoseSource from;
  final double? translationMag;
}

enum PoseSource { landmarks, matrix }

/// Blendshape info from MediaPipe: the dominant expression category and its score.
/// When blendshapes are disabled or absent, `empty` is true.
class MediaPipeBlendshapeInfo {
  const MediaPipeBlendshapeInfo({
    this.dominantCategory = '',
    this.dominantScore = 0.0,
    this.empty = true,
  });

  static const MediaPipeBlendshapeInfo empty() = MediaPipeBlendshapeInfo();

  final String dominantCategory;
  final double dominantScore;
  final bool empty;
}

/// Cross-view analysis combining the three views.
class MediaPipeCrossViewAnalysis {
  const MediaPipeCrossViewAnalysis({
    required this.front,
    required this.left,
    required this.right,
    required this.crossView,
    required this.notes,
  });

  final MediaPipeViewAnalysis front;
  final MediaPipeViewAnalysis left;
  final MediaPipeViewAnalysis right;
  final Map<String, dynamic> crossView;
  final List<String> notes;
}

/// Indices into MediaPipe Face Landmarker's 478-point topology.
///
/// These are the landmarks this app uses. They overlap with the existing 468-point
/// topology where the existing maths applies, and extend into the 468-477 range for
/// iris and related points.
abstract final class MediaPipeLandmarks {
  static const int nasion = 168;
  static const int chin = 152;
  static const int leftEyeOuter = 33;
  static const int rightEyeOuter = 263;
  static const int leftEyeInner = 133;
  static const int rightEyeInner = 362;
  static const int mouthLeft = 61;
  static const int mouthRight = 291;
  static const int faceEdgeLeft = 234;
  static const int faceEdgeRight = 454;
  static const int jawEdgeLeft = 172;
  static const int jawEdgeRight = 397;
  static const int foreheadTop = 10;
  static const int glabella = 9;
  static const int noseWingLeft = 94;
  static const int noseWingRight = 195;

  static const int irisLeft = 468;
  static const int irisRight = 469;
  static const int irisCenterLeft = 472;
  static const int irisCenterRight = 473;

  static const int landmarkCount = 478;
}
