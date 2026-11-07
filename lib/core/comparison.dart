import '../data/scan_history.dart';
import 'report.dart';

/// One measurement in the form a comparison needs: the score, the printed raw
/// value, and — when the scan recorded it — the raw number behind that value.
///
/// The raw number is what makes a sentence like "optimized by 4°" possible.
/// Scans saved before the number was recorded simply carry null and fall back to
/// score-only wording.
class ComparisonMetric {
  const ComparisonMetric({
    required this.id,
    required this.title,
    required this.score,
    required this.rawValue,
    this.rawNumber,
    this.unit = '',
  });

  final MetricId id;
  final String title;

  /// 0-100, the same scale the dashboard shows.
  final double score;

  /// The formatted raw value, e.g. `1.8%` or `112°`.
  final String rawValue;

  final double? rawNumber;

  /// `%`, `°`, or empty for the unitless thirds index.
  final String unit;

  /// The unit each metric is recorded in.
  static String unitFor(MetricId id) => switch (id) {
    MetricId.eyeSymmetry => '%',
    MetricId.jawline => '°',
    MetricId.facialThirds => '',
  };
}

/// One side of a comparison: a saved scan, a freshly measured photo, or an
/// imported friend's report.
///
/// Both modules speak this type so the arithmetic and the rendering never need
/// to know where the numbers came from.
class ComparisonEntry {
  const ComparisonEntry({
    required this.label,
    required this.createdAt,
    required this.overallScore,
    required this.metrics,
    this.potentialScore,
    this.id,
    this.isImported = false,
    this.warnings = const <String>[],
  });

  /// What the card calls this side: `Before`, `Friend`, the imported title.
  final String label;

  final DateTime createdAt;
  final double overallScore;
  final double? potentialScore;
  final List<ComparisonMetric> metrics;

  /// History id when this entry came from the archive; null for a photo that was
  /// measured just now.
  final String? id;

  /// True for a report that arrived as a `.umax` file from someone else.
  final bool isImported;

  /// Capture notes recorded with the scan (head turned, tilted). Carried so the
  /// comparison can repeat them rather than presenting a shaky reading as a
  /// fact.
  final List<String> warnings;

  factory ComparisonEntry.fromScan(SavedScan scan) {
    return ComparisonEntry(
      label: scan.displayTitle,
      createdAt: scan.createdAt,
      overallScore: scan.overallScore,
      potentialScore: scan.potentialScore,
      id: scan.id,
      isImported: scan.isFriend,
      warnings: scan.warnings,
      metrics: <ComparisonMetric>[
        for (final SavedMetric metric in scan.metrics)
          ComparisonMetric(
            id: metric.id,
            title: metric.title,
            score: metric.score,
            rawValue: metric.rawValue,
            rawNumber: metric.rawNumber,
            unit: ComparisonMetric.unitFor(metric.id),
          ),
      ],
    );
  }

  factory ComparisonEntry.fromReport(
    AnalysisReport report, {
    String label = 'This photo',
  }) {
    return ComparisonEntry(
      label: label,
      createdAt: report.createdAt,
      overallScore: report.overallScore,
      potentialScore: report.potentialScore,
      warnings: report.qualityWarnings,
      metrics: <ComparisonMetric>[
        for (final MetricResult metric in report.metrics)
          ComparisonMetric(
            id: metric.id,
            title: metric.title,
            score: metric.score,
            rawValue: metric.rawValue,
            rawNumber: metric.id == MetricId.eyeSymmetry
                ? report.raw.eyeAsymmetryPercent
                : metric.id == MetricId.jawline
                ? report.raw.jawAngleDegrees
                : report.raw.thirdsDeviation,
            unit: ComparisonMetric.unitFor(metric.id),
          ),
      ],
    );
  }

  ComparisonMetric? metric(MetricId id) {
    for (final ComparisonMetric metric in metrics) {
      if (metric.id == id) {
        return metric;
      }
    }
    return null;
  }

  String get scoreText => overallScore.toStringAsFixed(0);
}

/// The change in one measurement between the two sides.
class MetricDelta {
  const MetricDelta({required this.before, required this.after});

  final ComparisonMetric before;
  final ComparisonMetric after;

  MetricId get id => before.id;
  String get title => before.title;

  /// Score points gained. Positive means the second side scores higher.
  double get points => after.score - before.score;

  /// Percentage change relative to the first side, which is what the comparison
  /// matrix prints (`+3.2%`).
  double get percentChange =>
      before.score <= 0 ? 0 : points / before.score * 100;

  /// The threshold below which a difference is inside capture noise rather than
  /// a real change.
  static const double flatThreshold = 0.5;

  bool get isImprovement => points >= flatThreshold;
  bool get isDecline => points <= -flatThreshold;
  bool get isFlat => !isImprovement && !isDecline;

  /// `+3.2%`, `−1.4%`, `0.0%`.
  String get percentText {
    if (isFlat) {
      return '0.0%';
    }
    final String sign = points > 0 ? '+' : '\u2212';
    return '$sign${percentChange.abs().toStringAsFixed(1)}%';
  }

  /// `+3`, `−2`, `0` — score points, for the leaderboard column.
  String get pointsText {
    if (isFlat) {
      return '0';
    }
    final String sign = points > 0 ? '+' : '\u2212';
    return '$sign${points.abs().toStringAsFixed(0)}';
  }

  /// The change in the underlying geometry, in its own units.
  ///
  /// Null when either side predates raw-number storage, so the UI can omit the
  /// line rather than invent one.
  String? get rawChangeText {
    final double? start = before.rawNumber;
    final double? end = after.rawNumber;
    if (start == null || end == null) {
      return null;
    }
    final double change = end - start;
    final double noise = switch (id) {
      MetricId.eyeSymmetry => 0.05,
      MetricId.jawline => 0.5,
      MetricId.facialThirds => 0.005,
    };
    if (change.abs() < noise) {
      return switch (id) {
        MetricId.eyeSymmetry => 'asymmetry unchanged',
        MetricId.jawline => 'chin angle unchanged',
        MetricId.facialThirds => 'proportions unchanged',
      };
    }
    return switch (id) {
      MetricId.eyeSymmetry =>
        change < 0
            ? 'more even by ${change.abs().toStringAsFixed(1)}%'
            : 'less even by ${change.abs().toStringAsFixed(1)}%',
      MetricId.jawline =>
        change < 0
            ? 'optimized by ${change.abs().toStringAsFixed(0)}\u00B0'
            : 'widened by ${change.abs().toStringAsFixed(0)}\u00B0',
      MetricId.facialThirds =>
        change < 0
            ? 'closer to a 1:1:1 split by '
                  '${change.abs().toStringAsFixed(2)}'
            : 'further from a 1:1:1 split by '
                  '${change.abs().toStringAsFixed(2)}',
    };
  }
}

/// Everything the two comparison screens render, computed once.
class ComparisonResult {
  ComparisonResult({required this.before, required this.after});

  final ComparisonEntry before;
  final ComparisonEntry after;

  late final List<MetricDelta> deltas = _buildDeltas();

  List<MetricDelta> _buildDeltas() {
    final List<MetricDelta> out = <MetricDelta>[];
    for (final ComparisonMetric metric in before.metrics) {
      final ComparisonMetric? other = after.metric(metric.id);
      if (other != null) {
        out.add(MetricDelta(before: metric, after: other));
      }
    }
    return out;
  }

  bool get hasMetrics => deltas.isNotEmpty;

  double get overallDelta => after.overallScore - before.overallScore;

  double get overallPercent =>
      before.overallScore <= 0 ? 0 : overallDelta / before.overallScore * 100;

  bool get overallFlat => overallDelta.abs() < 1.5;

  /// Metrics where the second side scores higher. For a versus screen this is
  /// literally "who won the category".
  int get winsAfter => deltas.where((MetricDelta d) => d.isImprovement).length;

  int get winsBefore => deltas.where((MetricDelta d) => d.isDecline).length;

  int get ties => deltas.where((MetricDelta d) => d.isFlat).length;

  /// Highest-scoring side by categories won, or null for a draw.
  ComparisonEntry? get leader {
    if (winsAfter == winsBefore) {
      return null;
    }
    return winsAfter > winsBefore ? after : before;
  }

  /// Categories ordered by who gained the most, which is how a leaderboard
  /// reads.
  List<MetricDelta> get leaderboard {
    final List<MetricDelta> ordered = List<MetricDelta>.of(deltas)
      ..sort((MetricDelta a, MetricDelta b) => b.points.compareTo(a.points));
    return ordered;
  }

  /// Percentage change for one metric, or null when it is missing on a side.
  double? percentChangeOf(MetricId id) {
    for (final MetricDelta delta in deltas) {
      if (delta.id == id) {
        return delta.percentChange;
      }
    }
    return null;
  }

  /// True when either side carried capture warnings.
  bool get hasCaptureNotes =>
      before.warnings.isNotEmpty || after.warnings.isNotEmpty;

  /// The single measurement with the largest swing, when it clears the noise
  /// threshold.
  MetricDelta? get biggestSwing {
    if (deltas.isEmpty) {
      return null;
    }
    final List<MetricDelta> ordered = leaderboard;
    return ordered.first.isFlat ? null : ordered.first;
  }

  /// `+3.0%` style text for the overall score.
  String get overallPercentText {
    if (overallFlat) {
      return '0.0%';
    }
    final String sign = overallDelta > 0 ? '+' : '\u2212';
    return '$sign${overallPercent.abs().toStringAsFixed(1)}%';
  }

  String get overallPointsText {
    if (overallFlat) {
      return 'no meaningful change';
    }
    final String sign = overallDelta > 0 ? '+' : '\u2212';
    return '$sign${overallDelta.abs().toStringAsFixed(1)} points';
  }
}
