import 'package:facial_analysis/core/comparison.dart';
import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
// flutter_test also exports a `ComparisonResult` (for golden files), which is
// not the one this suite is about.
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;

import 'support/metrics_fixture.dart';

AnalysisReport reportFor({
  required double asymmetry,
  required double jawAngle,
  double upper = 0.333,
  double middle = 0.334,
  double lower = 0.333,
  DateTime? at,
}) {
  return const ScoringEngine().build(
    faceMetrics(
      asymmetry: asymmetry,
      jawAngle: jawAngle,
      upper: upper,
      middle: middle,
      lower: lower,
    ),
    createdAt: at ?? DateTime(2026, 10, 1, 9),
  );
}

void main() {
  test('a metric delta carries both percent and raw-unit wording', () {
    final AnalysisReport before = reportFor(asymmetry: 2.0, jawAngle: 120);
    final AnalysisReport after = reportFor(asymmetry: 1.6, jawAngle: 116);

    final ComparisonResult result = ComparisonResult(
      before: ComparisonEntry.fromReport(before, label: 'Before'),
      after: ComparisonEntry.fromReport(after, label: 'After'),
    );

    final MetricDelta symmetry = result.deltas.firstWhere(
      (MetricDelta d) => d.id == MetricId.eyeSymmetry,
    );
    final MetricDelta jaw = result.deltas.firstWhere(
      (MetricDelta d) => d.id == MetricId.jawline,
    );

    // Symmetry improved by 0.4 points of asymmetry, so the score went up.
    expect(symmetry.points, greaterThan(0));
    expect(symmetry.percentText, startsWith('+'));
    expect(symmetry.percentText, endsWith('%'));
    expect(symmetry.rawChangeText, 'more even by 0.4%');

    // A four degree drop in chin angle is the "optimized by 4°" headline.
    expect(jaw.isImprovement, isTrue);
    expect(jaw.rawChangeText, 'optimized by 4\u00B0');
  });

  test('a worse measurement reads as a decline, not a win', () {
    final AnalysisReport before = reportFor(asymmetry: 1.0, jawAngle: 110);
    final AnalysisReport after = reportFor(asymmetry: 4.0, jawAngle: 130);

    final ComparisonResult result = ComparisonResult(
      before: ComparisonEntry.fromReport(before),
      after: ComparisonEntry.fromReport(after),
    );

    final MetricDelta symmetry = result.deltas.firstWhere(
      (MetricDelta d) => d.id == MetricId.eyeSymmetry,
    );
    expect(symmetry.isDecline, isTrue);
    expect(symmetry.isImprovement, isFalse);
    expect(symmetry.percentText, startsWith('\u2212'));
    expect(symmetry.rawChangeText, 'less even by 3.0%');
    expect(result.overallDelta, lessThan(0));
    expect(result.overallPercentText, startsWith('\u2212'));
  });

  test('a difference inside the noise band counts as flat', () {
    final AnalysisReport before = reportFor(asymmetry: 2.0, jawAngle: 120);
    final AnalysisReport after = reportFor(asymmetry: 2.0, jawAngle: 120);

    final ComparisonResult result = ComparisonResult(
      before: ComparisonEntry.fromReport(before),
      after: ComparisonEntry.fromReport(after),
    );

    for (final MetricDelta delta in result.deltas) {
      expect(delta.isFlat, isTrue);
      expect(delta.percentText, '0.0%');
      expect(delta.pointsText, '0');
    }
    expect(result.overallFlat, isTrue);
    expect(result.overallPointsText, 'no meaningful change');
    expect(result.biggestSwing, isNull);
    expect(result.leader, isNull);
    expect(result.ties, result.deltas.length);
  });

  test('the leaderboard ranks categories by who gained most', () {
    // Jaw improves a lot, symmetry barely, thirds not at all.
    final AnalysisReport before = const ScoringEngine().build(
      faceMetrics(asymmetry: 1.2, jawAngle: 140, upper: 0.36),
    );
    final AnalysisReport after = const ScoringEngine().build(
      faceMetrics(asymmetry: 1.1, jawAngle: 105, upper: 0.36),
    );

    final ComparisonResult result = ComparisonResult(
      before: ComparisonEntry.fromReport(before, label: 'You'),
      after: ComparisonEntry.fromReport(after, label: 'Friend'),
    );

    expect(result.leaderboard.first.id, MetricId.jawline);
    expect(result.leader?.label, 'Friend');
    expect(result.winsAfter, greaterThan(result.winsBefore));
    expect(result.biggestSwing?.id, MetricId.jawline);
    expect(result.percentChangeOf(MetricId.jawline), greaterThan(0));
  });

  test('a metric missing from one side is skipped, not invented', () {
    final AnalysisReport before = reportFor(asymmetry: 2.0, jawAngle: 120);
    final AnalysisReport after = reportFor(asymmetry: 2.5, jawAngle: 120);

    final ComparisonEntry trimmed = ComparisonEntry(
      label: 'Friend',
      createdAt: after.createdAt,
      overallScore: after.overallScore,
      metrics: <ComparisonMetric>[
        ComparisonMetric(
          id: MetricId.jawline,
          title: 'Jawline angularity',
          score: after.metric(MetricId.jawline).score,
          rawValue: after.metric(MetricId.jawline).rawValue,
        ),
      ],
    );

    final ComparisonResult result = ComparisonResult(
      before: ComparisonEntry.fromReport(before),
      after: trimmed,
    );

    expect(result.deltas, hasLength(1));
    expect(result.deltas.single.id, MetricId.jawline);
    // No raw numbers on the trimmed side, so no raw sentence is produced.
    expect(result.deltas.single.rawChangeText, isNull);
  });

  test('scans saved without raw numbers fall back to score wording only', () {
    final DateTime fixed = DateTime.utc(2026, 9, 1);
    final ComparisonResult result = ComparisonResult(
      before: ComparisonEntry(
        label: 'Older scan',
        createdAt: fixed,
        overallScore: 60,
        metrics: <ComparisonMetric>[
          const ComparisonMetric(
            id: MetricId.jawline,
            title: 'Jawline angularity',
            score: 55,
            rawValue: '117°',
          ),
        ],
      ),
      after: ComparisonEntry(
        label: 'Newer scan',
        createdAt: fixed,
        overallScore: 66,
        metrics: <ComparisonMetric>[
          const ComparisonMetric(
            id: MetricId.jawline,
            title: 'Jawline angularity',
            score: 64,
            rawValue: '112°',
            rawNumber: 112,
          ),
        ],
      ),
    );

    expect(result.deltas.single.percentText, '+16.4%');
    expect(result.deltas.single.rawChangeText, isNull);
  });

  test('percent change is relative to the earlier score', () {
    const ComparisonMetric before = ComparisonMetric(
      id: MetricId.eyeSymmetry,
      title: 'Eye symmetry',
      score: 80,
      rawValue: '1.0%',
      rawNumber: 1.0,
    );
    const ComparisonMetric after = ComparisonMetric(
      id: MetricId.eyeSymmetry,
      title: 'Eye symmetry',
      score: 82.4,
      rawValue: '0.8%',
      rawNumber: 0.8,
    );
    const MetricDelta delta = MetricDelta(before: before, after: after);

    expect(delta.percentChange, closeTo(3.0, 1e-9));
    expect(delta.percentText, '+3.0%');
  });
}
