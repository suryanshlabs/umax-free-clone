import 'metrics.dart';

/// The three scored categories.
enum MetricId { eyeSymmetry, jawline, facialThirds }

/// How much weight to give a piece of advice, in plain language.
///
/// Deliberately coarse. The app should never imply more certainty than the
/// literature has, and "mewing reshapes adult bone" and "fat loss reveals the
/// jawline" belong at opposite ends of this scale.
enum EvidenceStrength {
  strong('Strong evidence'),
  moderate('Moderate evidence'),
  emerging('Limited evidence'),
  measurement('Measurement factor');

  const EvidenceStrength(this.label);

  final String label;
}

/// One actionable suggestion with the reasoning attached.
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

/// A scored category with its raw measurement and generated advice.
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

  /// 0-100.
  final double score;

  /// One sentence explaining what the number is and what it means here.
  final String summary;

  final List<AdviceItem> advice;

  /// Qualitative band, used for colour and for the score chip.
  String get scoreLabel {
    if (score >= 85) return 'Excellent';
    if (score >= 72) return 'Strong';
    if (score >= 58) return 'Balanced';
    if (score >= 42) return 'Room to grow';
    return 'Focus area';
  }
}

/// When a roadmap step happens. Chronological by declaration order, so the list
/// can be sorted by `index` and always reads as a plan rather than a wish list.
enum RoadmapStage {
  now('Now'),
  weeks1to2('Weeks 1–2'),
  weeks3to4('Weeks 3–4'),
  week5plus('Week 5+');

  const RoadmapStage(this.label);

  final String label;
}

/// One scheduled corrective routine on the weakness roadmap.
class RoadmapStep {
  const RoadmapStep({
    required this.stage,
    required this.title,
    required this.detail,
    required this.evidence,
  });

  final RoadmapStage stage;
  final String title;

  /// What to actually do, with the reasoning and the limits of the evidence.
  final String detail;

  final EvidenceStrength evidence;
}

/// The weakest measurement, promoted out of the list and turned into a plan.
///
/// "Core weakness" is this app's own framing, not a clinical finding: it is
/// simply the measurement contributing least to the weighted total, which is
/// where a change moves the overall number most.
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

  /// The formatted measurement behind the score, e.g. "4.1%".
  final String rawValue;

  /// Points between this measurement and the next-weakest one. A large gap
  /// means the face is genuinely uneven; a small one means all three are in the
  /// same band and nothing dominates.
  final double gapToNextBest;

  /// Two or three sentences tying the number to a cause and a lever.
  final String why;

  /// Ordered `Now` → `Week 5+`. Never empty for a real report.
  final List<RoadmapStep> steps;

  String get scoreText => score.toStringAsFixed(0);

  /// True when the metric is far enough below the others that calling it *the*
  /// weakness is fair rather than an artefact of noise.
  bool get isClearlyWeakest => gapToNextBest >= 4;

  List<RoadmapStep> stepsFor(RoadmapStage stage) => <RoadmapStep>[
    for (final RoadmapStep step in steps)
      if (step.stage == stage) step,
  ];
}

/// The complete output of one analysis: scores, advice, and the conditions the
/// measurement was taken under.
class AnalysisReport {
  const AnalysisReport({
    required this.overallScore,
    required this.potentialScore,
    required this.potentialGain,
    required this.grade,
    required this.gradeBlurb,
    required this.metrics,
    required this.coreWeakness,
    required this.raw,
    required this.qualityWarnings,
    required this.createdAt,
    this.safetyNote,
    this.imagePath,
  });

  /// Strict geometric baseline: the weighted mean of the three measurements.
  final double overallScore;

  /// The projection: the baseline plus the calibration's projection bonus,
  /// sized by how much headroom the two weakest measurements have.
  final double potentialScore;

  /// `potentialScore - overallScore`, in score points. Between
  /// [AnalysisCalibration.potentialMinGain] and
  /// [AnalysisCalibration.potentialMaxGain] unless the scale's ceiling of 100 is
  /// closer than the bonus.
  final double potentialGain;

  final String grade;
  final String gradeBlurb;
  final List<MetricResult> metrics;

  /// The lowest-scoring measurement, with its chronological roadmap.
  final WeaknessInsight coreWeakness;

  final RawFaceMetrics raw;

  /// Conditions that make the numbers less trustworthy (head turned, tilted).
  final List<String> qualityWarnings;

  /// Present only when the asymmetry reading is large enough that "if this is
  /// new, see a doctor" is the responsible thing to say.
  final String? safetyNote;

  final DateTime createdAt;
  final String? imagePath;

  MetricResult metric(MetricId id) => metrics.firstWhere(
    (MetricResult metric) => metric.id == id,
    orElse: () => metrics.first,
  );

  bool get isReliable => qualityWarnings.isEmpty;

  String get overallText => overallScore.toStringAsFixed(0);

  String get potentialText => potentialScore.toStringAsFixed(0);

  String get potentialGainText => '+${potentialGain.toStringAsFixed(0)}';

  /// True when there is headroom worth showing. A face already at the top of the
  /// scale gains almost nothing, and pretending otherwise would be dishonest.
  bool get hasMeaningfulPotential => potentialGain >= 1;

  /// Plain-text summary for the clipboard / messaging apps.
  String toShareText() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Facial geometry analysis — ${_formatDate(createdAt)}')
      ..writeln('Overall: $overallText/100 ($grade)')
      ..writeln('Potential: $potentialText/100 ($potentialGainText)')
      ..writeln()
      ..writeln(
        'Core weakness: ${coreWeakness.title} '
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
        '${metric.title}: ${metric.score.toStringAsFixed(0)}/100 '
        '(${metric.measurementLabel} ${metric.rawValue})',
      );
    }
    buffer
      ..writeln()
      ..write(
        'Measured on-device from 468 MediaPipe Face Mesh landmarks. '
        'Geometric estimate, not a medical or attractiveness assessment.',
      );
    return buffer.toString();
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
