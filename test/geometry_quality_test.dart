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

  group('midline symmetry', () {
    test('a mirrored face reads as zero residual', () {
      expect(service.measure(syntheticFace()).eyeAsymmetryPercent, 0);
    });

    test('a wide-set but symmetric face is not called asymmetric', () {
      // The old nose-to-eye formula reported a difference whenever the two eye
      // distances differed, even on a perfectly mirrored face with wide-set
      // eyes. Distance from the midline is what matters, so this must stay 0.
      final RawFaceMetrics wide = service.measure(
        syntheticFace(
          leftEye: const Vec2(-40, 25),
          rightEye: const Vec2(40, 25),
          leftEyeInner: const Vec2(-14, 25),
          rightEyeInner: const Vec2(14, 25),
          faceLeft: const Vec2(-70, 40),
          faceRight: const Vec2(70, 40),
        ),
      );
      expect(wide.eyeAsymmetryPercent, closeTo(0, 1e-9));
      expect(wide.eyeDistanceRatio, closeTo(1, 1e-9));
    });

    test('a single moved mouth corner moves the averaged residual', () {
      final RawFaceMetrics moved = service.measure(
        syntheticFace(mouthLeft: const Vec2(-18, 70)),
      );
      // Outer span is 50, so the mouth pair is 6/50 * 100 = 12% off and the
      // mean across four pairs is a quarter of that.
      expect(moved.eyeAsymmetryPercent, closeTo(3.0, 0.001));
      expect(moved.eyeAsymmetryPercent, greaterThan(0));
    });

    test('residual is unchanged by uniform scale', () {
      final RawFaceMetrics small = service.measure(syntheticFace());
      final RawFaceMetrics large = service.measure(
        scaledMesh(syntheticFace(), 4.2),
      );
      expect(
        large.eyeAsymmetryPercent,
        closeTo(small.eyeAsymmetryPercent, 1e-9),
      );
    });
  });

  group('facial thirds use the subnasale', () {
    test('the middle third runs glabella to the nostril-wing midpoint', () {
      final RawFaceMetrics metrics = service.measure(syntheticFace());
      // 0 -> 30 -> 45 -> 120 over a 120-unit face.
      expect(metrics.upperThirdFraction, closeTo(0.25, 1e-9));
      expect(metrics.middleThirdFraction, closeTo(0.125, 1e-9));
      expect(metrics.lowerThirdFraction, closeTo(0.625, 1e-9));
    });

    test('moving only the nostril wings changes the thirds', () {
      final RawFaceMetrics base = service.measure(syntheticFace());
      final List<Vec2> moved = List<Vec2>.of(syntheticFace());
      moved[TestLandmarks.noseWingLeft] = const Vec2(-8, 60);
      moved[TestLandmarks.noseWingRight] = const Vec2(8, 60);
      final RawFaceMetrics lower = service.measure(moved);

      // Same landmark 2, different subnasale: if the old radix boundary were
      // still in use these would be identical.
      expect(lower.middleThirdFraction, greaterThan(base.middleThirdFraction));
      expect(lower.lowerThirdFraction, lessThan(base.lowerThirdFraction));
    });
  });

  group('landmark and pose validation', () {
    test('refuses a mesh whose face width is implausible for its eye span', () {
      expect(
        () => service.measure(
          syntheticFace(
            leftEye: const Vec2(-10, 25),
            rightEye: const Vec2(10, 25),
          ),
        ),
        throwsA(isA<FacialAnalysisException>()),
      );
    });

    test('refuses an upside-down mesh', () {
      expect(
        () => service.measure(
          syntheticFace(
            glabella: const Vec2(0, 80),
            noseBase: const Vec2(0, 40),
            chin: const Vec2(0, 10),
          ),
        ),
        throwsA(isA<FacialAnalysisException>()),
      );
    });

    test('reports a turned head as a capture note, not a silent number', () {
      final RawFaceMetrics turned = service.measure(
        syntheticFace(faceLeft: const Vec2(-30, 40)),
      );
      final AnalysisReport report = engine.build(turned);
      expect(turned.yawIndex, lessThan(0.82));
      expect(
        report.qualityWarnings.any((String w) => w.contains('head was turned')),
        isTrue,
      );
    });

    test('a partial mesh still measures but carries a note', () {
      final RawFaceMetrics partial = service.measure(syntheticFace(count: 470));
      final AnalysisReport report = engine.build(partial);
      expect(
        report.qualityWarnings.any((String w) => w.contains('instead of')),
        isTrue,
      );
    });
  });
}
