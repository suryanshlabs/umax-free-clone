import 'look_improvements.dart';
import 'metrics.dart';

/// The three measured categories. These are measurements, not judgements: the
/// app reports how close each one is to a stated reference.
enum MetricId { eyeSymmetry, jawline, facialThirds }

/// How much weight to give a piece of advice, in plain language.
///
/// Deliberately coarse. The app should never imply more certainty than the
/// literature has, and "mewing reshapes adult bone" and "this is how the mesh
/// was scaled" belong at opposite ends of this scale.
enum EvidenceStrength {
  strong('Strong evidence'),
  moderate('Moderate evidence'),
  emerging('Limited evidence'),
  measurement('Measurement factor');

  const EvidenceStrength(this.label);

  final String label;
}

/// One informational note with the reasoning and its evidence level attached.
class AdviceItem {
  const AdviceItem({
    required this.title,
    required this.detail,
    required this.evidence,
  });

  final String title;
  final String detail;
  final EvidenceStrength evidence;
}

/// Where a combined agreement value sits, described as agreement with the
/// app's reference bands rather than as a rating of the person.
enum ReportBand {
  close('Close', 'Close to the reference bands'),
  near('Near', 'Mostly inside the reference bands'),
  mixed('Mixed', 'Mixed agreement with the reference bands'),
  deviated('Deviated', 'Several measurements outside their reference bands'),
  far('Far', 'Large departures from the reference bands');

  const ReportBand(this.label, this.description);

  /// Short form, safe for chips and list tiles.
  final String label;

  /// One line for a results header.
  final String description;

  static ReportBand fromScore(double score) {
    if (score >= 85) return ReportBand.close;
    if (score >= 72) return ReportBand.near;
    if (score >= 58) return ReportBand.mixed;
    if (score >= 42) return ReportBand.deviated;
    return ReportBand.far;
  }

  /// Explains the band without implying a verdict on appearance, and without
  /// promising that a lower band can be "fixed".
  String get explanation => switch (this) {
    ReportBand.close =>
      'All three measurements sit close to the references this app uses. That '
          'is a statement about the geometry in this photo, not a ranking of '
          'how you look.',
    ReportBand.near =>
      'Two measurements sit close to the reference and one carries most of the '
          'difference. Treat the individual measurements below as the useful '
          'detail; the combined number is only their weighted mean.',
    ReportBand.mixed =>
      'The measurements disagree with each other. That is common and is often '
          'dominated by the photo rather than the face: head angle, focal '
          'length and hairline placement all move these numbers.',
    ReportBand.deviated =>
      'Two or more measurements are outside the references this app uses. '
          'Check the capture conditions first - a turned or tilted head can '
          'produce this on any face - then compare your own scans over time '
          'rather than against the number.',
    ReportBand.far =>
      'The measurements are far from the references. In practice this is '
          'usually a capture problem: an extreme angle, a partial face, or a '
          'hairline the mesh could not see. Re-scan before reading anything '
          'into it.',
  };
}

/// A measured category with its raw measurement and neutral notes.
class MetricResult {
  const MetricResult({
    required this.id,
    required this.title,
    required this.measurementLabel,
    required this.rawValue,
    required this.score,
    required this.summary,
    required this.advice,
  });

  final MetricId id;
  final String title;

  /// Short caption for the raw number, e.g. "Asymmetry".
  final String measurementLabel;

  /// The formatted measurement itself, e.g. "1.8%".
  final String rawValue;

  /// 0-100 agreement with the stated reference. Not an attractiveness score.
  final double score;

  /// One sentence explaining what the number is and what it means here.
  final String summary;

  final List<AdviceItem> advice;

  /// Qualitative band, used for colour and for the measurement chip.
  String get scoreLabel => ReportBand.fromScore(score).label;
}

/// When a measurement note applies. Chronological by declaration order, so the
/// list can be sorted by `index` and always reads as a sequence.
enum RoadmapStage {
  now('Now'),
  weeks1to2('Weeks 1–2'),
  weeks3to4('Weeks 3–4'),
  week5plus('Week 5+');

  const RoadmapStage(this.label);

  final String label;
}

/// One scheduled observation or capture routine.
class RoadmapStep {
  const RoadmapStep({
    required this.stage,
    required this.title,
    required this.detail,
    required this.evidence,
  });

  final RoadmapStage stage;
  final String title;

  /// What to do, with the reasoning and the limits of the evidence.
  final String detail;

  final EvidenceStrength evidence;
}

/// The measurement furthest from its reference, promoted out of the list.
///
/// "Lowest agreement" is this app's own framing, not a clinical finding: it is
/// simply the measurement contributing least to the weighted mean, which is
/// where a change in the *measurement* would move the combined number most. It
/// is not a defect, and a low value is frequently the photo rather than the
/// face.
class WeaknessInsight {
  const WeaknessInsight({
    required this.metricId,
    required this.title,
    required this.score,
    required this.rawValue,
    required this.gapToNextBest,
    required this.why,
    required this.steps,
  });

  final MetricId metricId;
  final String title;
  final double score;

  /// The formatted measurement behind the value, e.g. "4.1%".
  final String rawValue;

  /// Points between this measurement and the next-lowest one.
  final double gapToNextBest;

  /// Two or three sentences tying the number to how it was measured.
  final String why;

  /// Ordered `Now` → `Week 5+`. Never empty for a real report.
  final List<RoadmapStep> steps;

  String get scoreText => score.toStringAsFixed(0);

  /// True when the measurement is far enough below the others that singling it
  /// out is meaningful rather than noise.
  bool get isClearlyWeakest => gapToNextBest >= 4;

  List<RoadmapStep> stepsFor(RoadmapStage stage) => <RoadmapStep>[
    for (final RoadmapStep step in steps)
      if (step.stage == stage) step,
  ];
}

/// The complete output of one analysis: measurements, notes, and the conditions
/// they were taken under.
class AnalysisReport {
  const AnalysisReport({
    required this.overallScore,
    required this.metrics,
    required this.coreWeakness,
    required this.raw,
    required this.qualityWarnings,
    required this.createdAt,
    this.safetyNote,
    this.imagePath,
  });

  /// Weighted mean of the three agreement values. Kept as a single number for
  /// trend tracking only; the per-measurement values are the honest detail.
  final double overallScore;

  final List<MetricResult> metrics;

  /// The measurement furthest from its reference, with observation steps.
  final WeaknessInsight coreWeakness;

  final RawFaceMetrics raw;

  /// Conditions that make the numbers less trustworthy (head turned, tilted,
  /// partial mesh).
  final List<String> qualityWarnings;

  /// Present only when the asymmetry residual is large enough that "if this is
  /// new, see a doctor" is the responsible thing to say.
  final String? safetyNote;

  final DateTime createdAt;
  final String? imagePath;

  /// Agreement band for [overallScore].
  ReportBand get band => ReportBand.fromScore(overallScore);

  /// Short band name for headers and history chips.
  String get bandLabel => band.label;

  /// One-line explanation of the band.
  String get bandNote => band.description;

  /// Longer, non-judgemental explanation.
  String get bandExplanation => band.explanation;

  MetricResult metric(MetricId id) => metrics.firstWhere(
    (MetricResult metric) => metric.id == id,
    orElse: () => metrics.first,
  );

  bool get isReliable => qualityWarnings.isEmpty;

  /// Practical levers that change how a face reads, grouped by area, with a
  /// short set aimed at the lowest-agreement measurement.
  ///
  /// Derived from [metrics] rather than stored, so old scans get the same plan
  /// and nothing has to be migrated.
  LookImprovementPlan get improvements => LookImprovementPlan.forMetrics(metrics);

  String get overallText => overallScore.toStringAsFixed(0);

  /// Plain-text summary for the clipboard / messaging apps.
  String toShareText() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Facial geometry measurements — ${_formatDate(createdAt)}')
      ..writeln('Combined agreement: $overallText/100 ($bandLabel)')
      ..writeln()
      ..writeln(
        'Lowest agreement: ${coreWeakness.title} '
        '(${coreWeakness.scoreText}/100, ${coreWeakness.rawValue})',
      );
    for (final RoadmapStep step in coreWeakness.steps) {
      buffer.writeln(
        '  ${step.stage.label}: ${step.title} (${step.evidence.label})',
      );
    }
    buffer.writeln();
    for (final MetricResult metric in metrics) {
      buffer.writeln(
        '${metric.title}: ${metric.score.toStringAsFixed(0)}/100 agreement '
        '(${metric.measurementLabel} ${metric.rawValue})',
      );
    }
    final LookImprovementPlan plan = improvements;
    buffer
      ..writeln()
      ..writeln('What can move this - ${plan.targetedArea}:');
    for (final LookImprovement item in plan.targeted) {
      buffer.writeln('  ${item.title}');
    }
    buffer.writeln();
    buffer.writeln('What can move this - overall:');
    for (final LookImprovement item in plan.overall) {
      buffer.writeln('  ${item.title}');
    }
    buffer
      ..writeln()
      ..write(
        'Measured on-device from 468 MediaPipe Face Mesh landmarks. These are '
        'geometric agreements with stated references, not a medical or '
        'attractiveness assessment.',
      );
    return buffer.toString();
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
