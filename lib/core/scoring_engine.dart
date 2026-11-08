import 'dart:math' as math;

import 'calibration.dart';
import 'feedback_engine.dart';
import 'metrics.dart';
import 'report.dart';
import 'user_profile.dart';

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
/// Two numbers come out of those three scores:
///
/// * **Overall** is the weighted mean. It is deliberately strict: it is what the
///   landmark coordinates say, with no allowance for a bad photo or a bad day.
/// * **Potential** is the projection. It takes the two weakest measurements,
///   measures the headroom those have between them, and adds a bonus of
///   [AnalysisCalibration.potentialMinGain] to
///   [AnalysisCalibration.potentialMaxGain] points accordingly. The weakest
///   measurement is weighted by [AnalysisCalibration.potentialPrimaryWeight] so
///   one noisy score cannot own the whole projection. Capped at 100, because
///   that is where the scale ends.
///
/// Weights, bands, penalties and the projection range all live in
/// [AnalysisCalibration]; nothing is hard-coded here.
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
    UserProfile? profile,
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
        rawValue: '${metrics.jawAngleDegrees.toStringAsFixed(0)}°',
        score: jawScore,
        summary:
            'The angle the two jaw edges make at the chin. A sharper '
            'convergence reads as a more tapered, angular lower face.',
        advice: feedback.forJawline(
          metrics,
          jawScore,
          bmi: profile?.bmi,
          bmiCategory: profile?.bmiCategory.$2,
        ),
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

    final double gain = _projectionGain(<double>[
      symmetryScore,
      jawScore,
      thirdsScore,
    ]);
    final double potential = math.min(100.0, overall + gain);

    final (String grade, String blurb) = _grade(overall);

    return AnalysisReport(
      overallScore: overall,
      potentialScore: potential,
      potentialGain: potential - overall,
      grade: grade,
      gradeBlurb: blurb,
      metrics: results,
      coreWeakness: feedback.coreWeakness(results),
      raw: metrics,
      qualityWarnings: _qualityWarnings(metrics),
      safetyNote: _safetyNote(metrics),
      createdAt: createdAt ?? DateTime.now(),
      imagePath: imagePath,
      profile: profile,
    );
  }
