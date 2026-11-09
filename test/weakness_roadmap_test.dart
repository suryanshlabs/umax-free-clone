import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/metrics_fixture.dart';

void main() {
  const ScoringEngine engine = ScoringEngine();

  test('the lowest measurement becomes the core weakness', () {
    final AnalysisReport report = engine.build(
      faceMetrics(asymmetry: 0.2, jawAngle: 148),
    );

    expect(report.coreWeakness.metricId, MetricId.jawline);
    expect(report.coreWeakness.title, 'Chin angle');
    expect(report.coreWeakness.score, report.metric(MetricId.jawline).score);
    expect(
      report.coreWeakness.rawValue,
      report.metric(MetricId.jawline).rawValue,
    );
  });

  test('the gap to the next measurement is reported honestly', () {
    final AnalysisReport report = engine.build(
      faceMetrics(asymmetry: 0.2, jawAngle: 148),
    );
    final List<double> scores = <double>[
      for (final MetricResult metric in report.metrics) metric.score,
    ]..sort();
    final double expectedGap = scores[1] - scores[0];

    expect(report.coreWeakness.gapToNextBest, closeTo(expectedGap, 0.001));
    expect(report.coreWeakness.isClearlyWeakest, expectedGap >= 4);
  });

  test('a different weakest metric produces a different roadmap', () {
    final WeaknessInsight jaw = engine
        .build(faceMetrics(asymmetry: 0.2, jawAngle: 148))
        .coreWeakness;
    final WeaknessInsight eyes = engine
        .build(faceMetrics(asymmetry: 9, jawAngle: 96))
        .coreWeakness;

    expect(jaw.metricId, MetricId.jawline);
    expect(eyes.metricId, MetricId.eyeSymmetry);

    final List<String> jawTitles = <String>[
      for (final RoadmapStep step in jaw.steps) step.title,
    ];
    final List<String> eyeTitles = <String>[
      for (final RoadmapStep step in eyes.steps) step.title,
    ];
    expect(jawTitles.toSet().difference(eyeTitles.toSet()), isNotEmpty);
  });

  test('the roadmap is chronological and complete', () {
    final WeaknessInsight insight = engine
        .build(faceMetrics(asymmetry: 9))
        .coreWeakness;

    expect(insight.steps.length, greaterThanOrEqualTo(4));
    expect(insight.steps.first.stage, RoadmapStage.now);
    expect(insight.steps.last.stage, RoadmapStage.week5plus);

    int previousStage = -1;
    for (final RoadmapStep step in insight.steps) {
      expect(step.stage.index, greaterThanOrEqualTo(previousStage));
      previousStage = step.stage.index;
      expect(step.title.trim(), isNotEmpty);
      expect(step.detail.length, greaterThan(40));
    }
  });

  test('every stage query returns only its own steps', () {
    final WeaknessInsight insight = engine
        .build(faceMetrics(asymmetry: 8))
        .coreWeakness;

    for (final RoadmapStage stage in RoadmapStage.values) {
      for (final RoadmapStep step in insight.stepsFor(stage)) {
        expect(step.stage, stage);
      }
    }

    final int total = <int>[
      for (final RoadmapStage stage in RoadmapStage.values)
        insight.stepsFor(stage).length,
    ].fold(0, (int sum, int count) => sum + count);
    expect(total, insight.steps.length);
  });

  test('the weakness text names the measurement and is not boilerplate', () {
    final WeaknessInsight insight = engine
        .build(faceMetrics(asymmetry: 6, jawAngle: 130))
        .coreWeakness;

    expect(insight.why, contains(insight.title));
    expect(insight.why, contains('not as a defect'));
    expect(insight.scoreText, isNotEmpty);
    expect(int.tryParse(insight.scoreText), isNotNull);
  });
}
