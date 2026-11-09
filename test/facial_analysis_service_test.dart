import 'package:facial_analysis/core/facial_analysis_service.dart';
import 'package:facial_analysis/core/metrics.dart';
import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
import 'package:facial_analysis/core/vector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/synthetic_face.dart';

void main() {
  const FacialAnalysisService service = FacialAnalysisService();
  const ScoringEngine engine = ScoringEngine();

  group('FacialAnalysisService — eye symmetry', () {
    test('a mirrored face reads as 0% asymmetry', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace());

      expect(metrics.eyeAsymmetryPercent, closeTo(0, 1e-9));
      expect(metrics.eyeDistanceRatio, closeTo(1, 1e-9));
      expect(metrics.interocularDistance, closeTo(50, 1e-9));
    });

    test('moves one eye corner out and reports the percentage difference', () {
      final RawFaceMetrics metrics = service.measure(
        syntheticFace(leftEye: const Vec2(-30, 25)),
      );

      // Only the outer-eye pair moved. Its residual is |30 - 25| / 55 * 100
      // = 9.09% of the (now 55-unit) eye span, and the residual is the mean of
      // four pairs, so the reported value is a quarter of that.
      expect(metrics.eyeAsymmetryPercent, closeTo(2.2727, 0.001));
      expect(metrics.eyeDistanceRatio, closeTo(1.2, 1e-9));
    });

    test('is scale invariant', () {
      final RawFaceMetrics small = service.measure(syntheticFace());
      final RawFaceMetrics large = service.measure(
        scaledMesh(syntheticFace(), 137.5),
      );

      expect(
        large.eyeAsymmetryPercent,
        closeTo(small.eyeAsymmetryPercent, 1e-9),
      );
      expect(large.jawAngleDegrees, closeTo(small.jawAngleDegrees, 1e-9));
    });
  });

  group('FacialAnalysisService — jawline angularity', () {
    test('measures the angle at the chin between the two jaw edges', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace());

      // Vectors (-40, -20) and (40, -20): cos = -1200 / 2000 = -0.6
      expect(metrics.jawAngleDegrees, closeTo(126.8699, 0.001));
    });

    test('narrower jaw edges produce a sharper angle', () {
      final RawFaceMetrics wide = service.measure(syntheticFace());
      final RawFaceMetrics narrow = service.measure(
        syntheticFace(
          jawLeft: const Vec2(-30, 100),
          jawRight: const Vec2(30, 100),
        ),
      );

      expect(narrow.jawAngleDegrees, lessThan(wide.jawAngleDegrees));
      expect(narrow.jawAngleDegrees, closeTo(112.6199, 0.001));

      final AnalysisReport wideReport = engine.build(wide);
      final AnalysisReport narrowReport = engine.build(narrow);
      expect(
        narrowReport.metric(MetricId.jawline).score,
        greaterThan(wideReport.metric(MetricId.jawline).score),
      );
    });
  });

  group('FacialAnalysisService — facial thirds', () {
    test('splits height into thirds and reports the fractions', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace());

      expect(metrics.upperThirdFraction, closeTo(0.25, 1e-9));
      expect(metrics.middleThirdFraction, closeTo(0.125, 1e-9));
      expect(metrics.lowerThirdFraction, closeTo(0.625, 1e-9));
      expect(
        metrics.upperThirdFraction +
            metrics.middleThirdFraction +
            metrics.lowerThirdFraction,
        closeTo(1, 1e-9),
      );
      expect(metrics.thirdsDeviation, closeTo(0.5833333, 1e-6));
    });

    test('a 1:1:1 face takes full marks', () {
      final RawFaceMetrics metrics = service.measure(
        syntheticFace(
          glabella: const Vec2(0, 40),
          noseBase: const Vec2(0, 80),
          chin: const Vec2(0, 120),
        ),
      );

      expect(metrics.thirdsDeviation, closeTo(0, 1e-9));
      expect(
        engine.build(metrics).metric(MetricId.facialThirds).score,
        closeTo(100, 1e-9),
      );
    });

    test('ratio display is normalised to the middle third', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace());

      expect(metrics.upperToMiddleRatio, closeTo(2.0, 1e-9));
      expect(metrics.lowerToMiddleRatio, closeTo(5.0, 1e-9));
      expect(metrics.dominantThird, 'lower third');
    });
  });

  group('FacialAnalysisService — pose and validation', () {
    test('a frontal face has a yaw index of 1 and no roll', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace());

      expect(metrics.yawIndex, closeTo(1, 1e-9));
      expect(metrics.rollDegrees, closeTo(0, 1e-9));
      expect(engine.build(metrics).qualityWarnings, isEmpty);
    });

    test('a turned head lowers the yaw index and raises a warning', () {
      final RawFaceMetrics metrics = service.measure(
        syntheticFace(faceLeft: const Vec2(-30, 40)),
      );

      expect(metrics.yawIndex, closeTo(0.6589, 0.001));
      expect(
        engine
            .build(metrics)
            .qualityWarnings
            .any((String warning) => warning.contains('turned')),
        isTrue,
      );
    });

    test('a tilted head reports roll and raises a warning', () {
      final RawFaceMetrics metrics = service.measure(
        syntheticFace(rightEye: const Vec2(25, 35)),
      );

      expect(metrics.rollDegrees, closeTo(11.3099, 0.001));
      expect(
        engine
            .build(metrics)
            .qualityWarnings
            .any((String warning) => warning.contains('tilted')),
        isTrue,
      );
    });

    test('rejects an incomplete mesh', () {
      expect(
        () => service.measure(List<Vec2>.filled(100, const Vec2(0, 0))),
        throwsA(isA<FacialAnalysisException>()),
      );
    });

    test('accepts a mesh with extra iris landmarks', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace(count: 478));

      expect(metrics.landmarkCount, 478);
      expect(metrics.eyeAsymmetryPercent, closeTo(0, 1e-9));
    });

    test('rejects a degenerate mesh instead of dividing by zero', () {
      expect(
        () => service.measure(List<Vec2>.filled(468, const Vec2(0, 0))),
        throwsA(isA<FacialAnalysisException>()),
      );
    });

    test('reads a mesh whose points are far below the minimum scale', () {
      // Everything collapsed onto one spot: also a divide-by-zero probe.
      expect(
        () => service.measure(List<Vec2>.filled(468, const Vec2(10, 10))),
        throwsA(isA<FacialAnalysisException>()),
      );
    });
  });

  group('ScoringEngine', () {
    test('normalises the three measurements and weights them', () {
      final AnalysisReport report = engine.build(
        service.measure(syntheticFace()),
      );

      expect(report.metrics, hasLength(3));
      expect(report.metric(MetricId.eyeSymmetry).score, closeTo(100, 1e-9));
      expect(report.metric(MetricId.jawline).score, closeTo(42.0547, 0.001));
      expect(
        report.metric(MetricId.facialThirds).score,
        closeTo(44.9667, 0.001),
      );
      expect(report.overallScore, closeTo(64.8893, 0.001));
      expect(report.bandLabel, 'Mixed');
    });

    test('never leaves the 0-100 range', () {
      final AnalysisReport extreme = engine.build(
        service.measure(
          syntheticFace(
            leftEye: const Vec2(-45, 25),
            rightEye: const Vec2(45, 25),
            jawLeft: const Vec2(-90, 60),
            jawRight: const Vec2(90, 60),
            faceLeft: const Vec2(-70, 40),
            faceRight: const Vec2(70, 40),
            glabella: const Vec2(0, 2),
            noseBase: const Vec2(0, 100),
          ),
        ),
      );

      for (final MetricResult metric in extreme.metrics) {
        expect(metric.score, inInclusiveRange(0, 100));
      }
      expect(extreme.overallScore, inInclusiveRange(0, 100));
    });

    test('every metric carries advice with an evidence label', () {
      final AnalysisReport report = engine.build(
        service.measure(syntheticFace()),
      );

      for (final MetricResult metric in report.metrics) {
        expect(metric.advice, isNotEmpty);
        for (final AdviceItem item in metric.advice) {
          expect(item.title, isNotEmpty);
          expect(item.detail.length, greaterThan(40));
          expect(item.evidence.label, isNotEmpty);
        }
      }
    });

    test('mentions a doctor only for a large asymmetry', () {
      final AnalysisReport symmetric = engine.build(
        service.measure(syntheticFace()),
      );
      final AnalysisReport asymmetric = engine.build(
        service.measure(
          syntheticFace(
            leftEye: const Vec2(-75, 25),
            rightEye: const Vec2(45, 25),
            faceLeft: const Vec2(-120, 40),
            faceRight: const Vec2(120, 40),
          ),
        ),
      );

      expect(symmetric.safetyNote, isNull);
      expect(asymmetric.safetyNote, isNotNull);
      expect(asymmetric.safetyNote, contains('doctor'));
    });

    test('zero middle third returns zero ratios instead of dividing', () {
      const RawFaceMetrics metrics = RawFaceMetrics(
        eyeAsymmetryPercent: 1,
        eyeDistanceRatio: 1,
        jawAngleDegrees: 110,
        upperThirdFraction: 0.5,
        middleThirdFraction: 0,
        lowerThirdFraction: 0.5,
        interocularDistance: 0.3,
        yawIndex: 1,
        rollDegrees: 0,
        landmarkCount: 468,
      );

      expect(metrics.upperToMiddleRatio, 0);
      expect(metrics.lowerToMiddleRatio, 0);
      // And the full build still completes with finite, in-range scores.
      final AnalysisReport report = engine.build(metrics);
      for (final MetricResult metric in report.metrics) {
        expect(metric.score.isFinite, isTrue);
        expect(metric.score, inInclusiveRange(0, 100));
      }
    });

    test('throws a ScoringException on non-finite measurements', () {
      const RawFaceMetrics metrics = RawFaceMetrics(
        eyeAsymmetryPercent: 1,
        eyeDistanceRatio: 1,
        jawAngleDegrees: double.nan,
        upperThirdFraction: 0.333,
        middleThirdFraction: 0.334,
        lowerThirdFraction: 0.333,
        interocularDistance: 0.3,
        yawIndex: 1,
        rollDegrees: 0,
        landmarkCount: 468,
      );

      expect(() => engine.build(metrics), throwsA(isA<ScoringException>()));
    });

    test('share text summarises every metric', () {
      final String text = engine
          .build(service.measure(syntheticFace()))
          .toShareText();

      expect(text, contains('Combined agreement:'));
      expect(text, contains('Eye symmetry:'));
      expect(text, contains('Chin angle:'));
      expect(text, contains('Facial thirds:'));
      expect(text, contains('468 MediaPipe Face Mesh'));
    });
  });
}
