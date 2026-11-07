import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/metrics_fixture.dart';

void main() {
  const ScoringEngine engine = ScoringEngine();

  test('potential never falls below the baseline or past the scale', () {
    for (final double asymmetry in <double>[0, 1, 3, 6, 9]) {
      for (final double jaw in <double>[92, 105, 120, 148]) {
        final AnalysisReport report = engine.build(
          faceMetrics(asymmetry: asymmetry, jawAngle: jaw),
        );
        expect(
          report.potentialScore,
          greaterThanOrEqualTo(report.overallScore),
        );
        expect(report.potentialScore, lessThanOrEqualTo(100));
        expect(report.potentialGain, greaterThanOrEqualTo(0));
        expect(report.potentialGain, lessThanOrEqualTo(15));
      }
    }
  });

  test('a face with real headroom gains eight to fifteen points', () {
    final AnalysisReport report = engine.build(
      faceMetrics(
        asymmetry: 8,
        jawAngle: 148,
        upper: 0.5,
        middle: 0.3,
        lower: 0.2,
      ),
    );

    expect(report.overallScore, lessThan(60));
    expect(report.potentialGain, greaterThanOrEqualTo(8));
    expect(report.potentialGain, lessThanOrEqualTo(15));
    expect(report.potentialScore, greaterThan(report.overallScore));
    expect(report.hasMeaningfulPotential, isTrue);
  });

  test('the weaker the face, the larger the projection', () {
    final double weak = engine
        .build(faceMetrics(asymmetry: 7, jawAngle: 145))
        .potentialGain;
    final double middle = engine
        .build(faceMetrics(asymmetry: 3, jawAngle: 118))
        .potentialGain;
    final AnalysisReport strong = engine.build(
      faceMetrics(asymmetry: 0.2, jawAngle: 95),
    );

    expect(weak, greaterThan(middle));
    expect(middle, greaterThan(strong.potentialGain));
    expect(weak, lessThanOrEqualTo(15));

    // A near-perfect face has nowhere to project to: the bonus is clipped by
    // the top of the scale rather than pushing the number past 100.
    expect(strong.potentialScore, closeTo(100, 1e-9));
    expect(strong.potentialGain, lessThan(8));
  });

  test('a face already at the top of the scale gains nothing', () {
    final AnalysisReport report = engine.build(
      faceMetrics(
        asymmetry: 0.1,
        jawAngle: 90,
        upper: 1 / 3,
        middle: 1 / 3,
        lower: 1 / 3,
      ),
    );

    expect(report.overallScore, closeTo(100, 0.001));
    expect(report.potentialScore, 100);
    expect(report.potentialGain, 0);
    expect(report.hasMeaningfulPotential, isFalse);
  });

  test('the share text carries both numbers and the weakness', () {
    final String text = engine
        .build(faceMetrics(asymmetry: 8, jawAngle: 148))
        .toShareText();

    expect(text, contains('Overall:'));
    expect(text, contains('Potential:'));
    expect(text, contains('Core weakness:'));
    expect(text, contains('468 MediaPipe'));
  });
}
