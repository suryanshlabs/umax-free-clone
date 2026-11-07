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

/// The complete output of one analysis: scores, advice, and the conditions the
/// measurement was taken under.
class AnalysisReport {
  const AnalysisReport({
    required this.overallScore,
    required this.grade,
    required this.gradeBlurb,
    required this.metrics,
    required this.raw,
    required this.qualityWarnings,
    required this.createdAt,
    this.safetyNote,
    this.imagePath,
  });

  final double overallScore;
  final String grade;
  final String gradeBlurb;
  final List<MetricResult> metrics;
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

  /// Plain-text summary for the clipboard / messaging apps.
  String toShareText() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Facial geometry analysis — ${_formatDate(createdAt)}')
      ..writeln('Overall: ${overallScore.toStringAsFixed(0)}/100 ($grade)')
      ..writeln();
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
