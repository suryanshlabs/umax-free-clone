import 'calibration.dart';
import 'feedback_engine.dart';
import 'metrics.dart';
import 'report.dart';

/// Thrown when the measurements handed to the scoring engine are not finite or
/// a denominator is effectively zero. Carries a message that is safe to show
/// directly in the UI; it always beats a NaN reaching the screen.
class ScoringException implements Exception {
  const ScoringException(this.message);

  final String message;

  @override
  String toString() => 'ScoringException: $message';
}

/// Converts [RawFaceMetrics] into 0-100 agreement values and attaches neutral
/// notes.
///
/// Agreement is always "distance from a stated reference", never a rating of a
/// person:
///
/// * **Symmetry** — `100 - penalty * max(0, residual - tolerance)`, where the
///   residual is the mean mirrored-pair distance from the face's own midline.
/// * **Chin angle** — linear from [AnalysisCalibration.jawAngleBestDegrees]
///   (100) down to [AnalysisCalibration.jawAngleWorstDegrees] (0).
/// * **Facial thirds** — `100 - penalty * max(0, deviation - freeBand)`
///   against an even 1 : 1 : 1 split.
///
/// The combined value is the weighted mean of those three. It is deliberately
/// not called a score or a rating: there is no projection, no "potential", no
/// grade and no claim that a higher number is a better-looking face. Two photos
/// of the same face differ by more than most of these bands.
class ScoringEngine {
  const ScoringEngine({
    this.calibration = const AnalysisCalibration(),
    this.feedback = const FeedbackEngine(),
  });

  final AnalysisCalibration calibration;
  final FeedbackEngine feedback;

  AnalysisReport build(
    RawFaceMetrics metrics, {
    String? imagePath,
    DateTime? createdAt,
  }) {
    _requireFinite(metrics);

    final double symmetryScore = _symmetryScore(metrics);
    final double jawScore = _jawScore(metrics);
    final double thirdsScore = _thirdsScore(metrics);

    final double totalWeight =
        calibration.symmetryWeight +
        calibration.jawlineWeight +
        calibration.thirdsWeight;
    final double overall = totalWeight <= 0.001
        ? 0
        : (symmetryScore * calibration.symmetryWeight +
                  jawScore * calibration.jawlineWeight +
                  thirdsScore * calibration.thirdsWeight) /
              totalWeight;

    final List<MetricResult> results = <MetricResult>[
      MetricResult(
        id: MetricId.eyeSymmetry,
        title: 'Eye symmetry',
        measurementLabel: 'Asymmetry',
        rawValue: '${metrics.eyeAsymmetryPercent.toStringAsFixed(1)}%',
        score: symmetryScore,
        summary:
            'How far four mirrored landmark pairs (eye corners, mouth '
            'corners, cheek edges) sit from the face\'s own midline, averaged '
            'and scaled to the distance between the eyes.',
        advice: feedback.forEyeSymmetry(metrics, symmetryScore),
      ),
      MetricResult(
        id: MetricId.jawline,
        title: 'Chin angle',
        measurementLabel: 'Angle at the chin',
        rawValue: '${metrics.jawAngleDegrees.toStringAsFixed(0)}\u00B0',
        score: jawScore,
        summary:
            'The angle the two jaw-contour landmarks make at the chin. It is a '
            'frontal measurement of the lower-face contour, not a clinical '
            'gonial angle, which needs a side view.',
        advice: feedback.forJawline(metrics, jawScore),
      ),
      MetricResult(
        id: MetricId.facialThirds,
        title: 'Facial thirds',
        measurementLabel: 'Proportion',
        rawValue:
            '${metrics.upperToMiddleRatio.toStringAsFixed(2)} : 1.00 : '
            '${metrics.lowerToMiddleRatio.toStringAsFixed(2)}',
        score: thirdsScore,
        summary:
            'Hairline-to-brow, brow-to-nose-base and nose-base-to-chin as '
            'shares of face height, compared with an even 1 : 1 : 1 split.',
        advice: feedback.forFacialThirds(metrics, thirdsScore),
      ),
    ];

    return AnalysisReport(
      overallScore: overall,
      metrics: results,
      coreWeakness: feedback.coreWeakness(results),
      raw: metrics,
      qualityWarnings: _qualityWarnings(metrics),
      safetyNote: _safetyNote(metrics),
      createdAt: createdAt ?? DateTime.now(),
      imagePath: imagePath,
    );
  }

  /// Rejects NaN/Infinity before a single value is computed. A collapsed mesh
  /// that slipped past the geometry guards would otherwise produce NaN, which
  /// the UI would render as a blank or frozen results screen.
  void _requireFinite(RawFaceMetrics metrics) {
    final List<double> values = <double>[
      metrics.eyeAsymmetryPercent,
      metrics.eyeDistanceRatio,
      metrics.jawAngleDegrees,
      metrics.upperThirdFraction,
      metrics.middleThirdFraction,
      metrics.lowerThirdFraction,
      metrics.interocularDistance,
      metrics.yawIndex,
      metrics.rollDegrees,
    ];
    for (final double value in values) {
      if (!value.isFinite) {
        throw const ScoringException(
          'The measurement came back with an invalid number '
          '(not a real value). Retake the photo with your whole face in frame.',
        );
      }
    }
  }

  /// Mirrored faces lose nothing; every percentage point of residual past the
  /// noise tolerance costs [AnalysisCalibration.symmetryPenaltyPerPercent].
  double _symmetryScore(RawFaceMetrics metrics) {
    final double excess =
        metrics.eyeAsymmetryPercent - calibration.symmetryTolerancePercent;
    if (excess <= 0) {
      return 100;
    }
    return (100 - excess * calibration.symmetryPenaltyPerPercent).clamp(
      0.0,
      100.0,
    );
  }

  /// 100 at or below the best angle, 0 at or above the worst angle, linear
  /// between the two.
  double _jawScore(RawFaceMetrics metrics) {
    final double span =
        calibration.jawAngleWorstDegrees - calibration.jawAngleBestDegrees;
    if (span <= 0.001) {
      return 0;
    }
    final double t =
        (calibration.jawAngleWorstDegrees - metrics.jawAngleDegrees) / span;
    return (t * 100).clamp(0.0, 100.0);
  }

  /// Full agreement inside the free band, linear penalty past it.
  double _thirdsScore(RawFaceMetrics metrics) {
    final double excess =
        metrics.thirdsDeviation - calibration.thirdsFreeDeviation;
    if (excess <= 0) {
      return 100;
    }
    return (100 - excess * calibration.thirdsPenaltyPerDeviation).clamp(
      0.0,
      100.0,
    );
  }

  /// Conditions under which the numbers should not be trusted, in the order a
  /// user can act on them.
  List<String> _qualityWarnings(RawFaceMetrics metrics) {
    final List<String> warnings = <String>[];
    if (metrics.landmarkCount != calibration.landmarkCount) {
      warnings.add(
        'The detector returned ${metrics.landmarkCount} landmarks instead of '
        '${calibration.landmarkCount}. The measurement still ran, but a partial '
        'mesh is less reliable. Retake the photo with the whole face in frame.',
      );
    }
    final double spreadRatio = metrics.meshSpread / metrics.interocularDistance;
    if (spreadRatio.isFinite &&
        (spreadRatio < calibration.minMeshSpreadRatio ||
            spreadRatio > calibration.maxMeshSpreadRatio)) {
      warnings.add(
        'Face proportions look distorted in this mesh (height/eye span '
        '${spreadRatio.toStringAsFixed(2)}). This usually means the photo was '
        'taken at a steep angle or part of the face was covered.',
      );
    }
    if (metrics.yawIndex < calibration.frontalYawThreshold) {
      warnings.add(
        'Your head was turned during the scan (frontal index '
        '${metrics.yawIndex.toStringAsFixed(2)}, needs '
        '${calibration.frontalYawThreshold.toStringAsFixed(2)}). Turned heads '
        'compress one side of the face and distort both symmetry and thirds.',
      );
    }
    if (metrics.rollDegrees.abs() > calibration.maxRollDegrees) {
      warnings.add(
        'Your head was tilted ${metrics.rollDegrees.abs().toStringAsFixed(0)}'
        '\u00B0. Level your eyes with the guide before capturing; tilt shifts '
        'the vertical thirds more than anything else.',
      );
    }
    return warnings;
  }

  String? _safetyNote(RawFaceMetrics metrics) {
    if (metrics.eyeAsymmetryPercent < calibration.noticeableAsymmetryPercent) {
      return null;
    }
    return 'This reading is ${metrics.eyeAsymmetryPercent.toStringAsFixed(1)}% '
        'from mirrored, which is higher than the range this app expects from '
        'capture noise. Most people are mildly asymmetric and it is nothing to '
        'worry about. But if a difference like this appeared suddenly, or comes '
        'with drooping, numbness, weakness or a change in how you speak, see a '
        'doctor promptly \u2014 new one-sided facial change is a medical matter, '
        'not a cosmetic one.';
  }
}
