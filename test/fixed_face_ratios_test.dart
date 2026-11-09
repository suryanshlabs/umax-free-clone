import 'dart:math' as math;

import 'package:facial_analysis/core/facial_analysis_service.dart';
import 'package:facial_analysis/core/metrics.dart';
import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/synthetic_face.dart';

/// Fixed synthetic face → exact expected ratios.
///
/// These pin the measurement maths against a mesh whose geometry is known to
/// the digit, so a regression in any ratio (the class of bug that silently
/// ruins scores) fails loudly here instead of on a user's selfie.
void main() {
  const FacialAnalysisService service = FacialAnalysisService();
  const ScoringEngine engine = ScoringEngine();

  group('fixed synthetic face', () {
    late RawFaceMetrics metrics;

    setUp(() {
      metrics = service.measure(syntheticFace());
    });

    test(
      'symmetry is zero when both eyes sit equidistant from the midline',
      () {
        expect(metrics.eyeAsymmetryPercent, closeTo(0, 1e-9));
        expect(metrics.eyeDistanceRatio, closeTo(1, 1e-9));
      },
    );

    test('thirds split 30 / 15 / 75 across a 120-unit face', () {
      expect(metrics.upperThirdFraction, closeTo(30 / 120, 1e-9));
      expect(metrics.middleThirdFraction, closeTo(15 / 120, 1e-9));
      expect(metrics.lowerThirdFraction, closeTo(75 / 120, 1e-9));
      expect(
        metrics.upperThirdFraction +
            metrics.middleThirdFraction +
            metrics.lowerThirdFraction,
        closeTo(1, 1e-9),
      );
    });

    test('ratios against the middle third are 2.00 and 5.00', () {
      expect(metrics.upperToMiddleRatio, closeTo(2, 1e-9));
      expect(metrics.lowerToMiddleRatio, closeTo(5, 1e-9));
    });

    test('jaw angle is acos(-0.6) for the fixed jaw edges', () {
      // Jaw vectors from the chin: (-40, -20) and (40, -20).
      // dot = -1600 + 400 = -1200, |a| = |b| = sqrt(2000) -> cos = -0.6.
      final double expected = math.acos(-0.6) * 180 / math.pi;
      expect(metrics.jawAngleDegrees, closeTo(expected, 1e-6));
    });

    test('pose: perfectly frontal and level', () {
      expect(metrics.yawIndex, closeTo(1, 1e-9));
      expect(metrics.rollDegrees, closeTo(0, 1e-9));
    });

    test('ratios are scale invariant', () {
      final RawFaceMetrics big = service.measure(
        scaledMesh(syntheticFace(), 3.7),
      );
      expect(
        big.eyeAsymmetryPercent,
        closeTo(metrics.eyeAsymmetryPercent, 1e-9),
      );
      expect(big.upperToMiddleRatio, closeTo(metrics.upperToMiddleRatio, 1e-9));
      expect(big.lowerToMiddleRatio, closeTo(metrics.lowerToMiddleRatio, 1e-9));
      expect(big.jawAngleDegrees, closeTo(metrics.jawAngleDegrees, 1e-9));
    });

    test('the scoring engine produces finite, in-range scores', () {
      final report = engine.build(metrics);
      for (final score in <double>[
        report.overallScore,
        for (final m in report.metrics) m.score,
      ]) {
        expect(score.isFinite, isTrue);
        expect(score, inInclusiveRange(0, 100));
      }
      // Perfectly symmetric -> eye symmetry must score full marks.
      expect(report.metric(MetricId.eyeSymmetry).score, 100);
    });
  });
}
