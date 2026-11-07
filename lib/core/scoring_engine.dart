import 'calibration.dart';
import 'feedback_engine.dart';
import 'metrics.dart';
import 'report.dart';

/// Normalises [RawFaceMetrics] into 0-100 scores and attaches feedback.
///
/// Score definitions (all clamped to `[0, 100]`):
///
/// * **Eye symmetry** — `100 - penalty * max(0, asymmetry - tolerance)`.
///   Mirrored faces score 100; the penalty is linear in the percentage
///   difference so the number stays readable across the whole range.
/// * **Jawline angularity** — linear from
///   [AnalysisCalibration.jawAngleBestDegrees] (100 points) down to
///   [AnalysisCalibration.jawAngleWorstDegrees] (0 points). A smaller chin angle
///   means the jaw edges converge more sharply, which is the geometry people
///   read as a tapered, angular jaw.
/// * **Facial thirds** — `100 - penalty * max(0, deviation - freeBand)`, where
///   deviation is the total absolute distance from a 1 : 1 : 1 split.
///
/// The overall score is the weighted mean. Weights, bands and penalties all live
/// in [AnalysisCalibration]; nothing is hard-coded here.
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
    final double symmetryScore = _symmetryScore(metrics);
    final double jawScore = _jawScore(metrics);
    final double thirdsScore = _thirdsScore(metrics);

    final double totalWeight =
        calibration.symmetryWeight +
        calibration.jawlineWeight +
        calibration.thirdsWeight;
    final double overall = totalWeight <= 0
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
            'Distance from each outer eye corner to the nose-bridge '
            'midline, compared side to side. Lower is more mirrored.',
        advice: feedback.forEyeSymmetry(metrics, symmetryScore),
      ),
      MetricResult(
        id: MetricId.jawline,
        title: 'Jawline angularity',
        measurementLabel: 'Chin angle',
        rawValue: '${metrics.jawAngleDegrees.toStringAsFixed(0)}\u00B0',
        score: jawScore,
        summary:
            'The angle the two jaw edges make at the chin. A sharper '
            'convergence reads as a more tapered, angular lower face.',
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
            'Forehead, midface and lower face as shares of total face '
            'height, compared with a 1 : 1 : 1 split.',
        advice: feedback.forFacialThirds(metrics, thirdsScore),
      ),
    ];

    final (String grade, String blurb) = _grade(overall);

    return AnalysisReport(
      overallScore: overall,
      grade: grade,
      gradeBlurb: blurb,
      metrics: results,
      raw: metrics,
      qualityWarnings: _qualityWarnings(metrics),
      safetyNote: _safetyNote(metrics),
      createdAt: createdAt ?? DateTime.now(),
      imagePath: imagePath,
    );
  }

  /// Mirrored faces lose nothing; every percentage point of difference past the
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
    if (span <= 0) {
      return 0;
    }
    final double t =
        (calibration.jawAngleWorstDegrees - metrics.jawAngleDegrees) / span;
    return (t * 100).clamp(0.0, 100.0);
  }

  /// Full marks inside the free band, linear penalty past it.
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

  (String, String) _grade(double overall) {
    if (overall >= 85) {
      return (
        'Excellent',
        'Every category is sitting inside its reference band. There is nothing '
            'structural left for a photo to tell you.',
      );
    }
    if (overall >= 72) {
      return (
        'Strong',
        'Most of the geometry is close to its reference band, with one area '
            'carrying most of the deviation.',
      );
    }
    if (overall >= 58) {
      return (
        'Balanced',
        'A normal, mixed result. The scores below show which measurement is '
            'pulling the total down, and what actually moves it.',
      );
    }
    if (overall >= 42) {
      return (
        'Room to grow',
        'Two or more categories sit outside their bands. The advice is ordered '
            'by what has the most leverage, starting with how the photo was '
            'taken.',
      );
    }
    return (
      'Focus area',
      'Several measurements are far from their reference bands. Check the '
          'capture conditions first: a turned or tilted head can produce this '
          'result on a perfectly normal face.',
    );
  }

  List<String> _qualityWarnings(RawFaceMetrics metrics) {
    final List<String> warnings = <String>[];
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
        'asymmetric, which is higher than the range this app expects from '
        'capture noise. Most people are mildly asymmetric and it is nothing to '
        'worry about. But if the difference appeared suddenly, or comes with '
        'drooping, numbness, weakness or a change in how you speak, see a '
        'doctor promptly \u2014 new one-sided facial change is a medical matter, '
        'not a cosmetic one.';
  }
}
