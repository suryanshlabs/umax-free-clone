import '../data/scan_history.dart';
import 'report.dart';

/// One measurement in the form a comparison needs: the agreement value, the
/// printed raw value, and — when the scan recorded it — the raw number behind
/// that value.
///
/// The raw number is what makes a sentence like "0.4% lower" possible. Scans
/// saved before the number was recorded simply carry null and fall back to
/// value-only wording.
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

  /// 0-100 agreement with the stated reference, the same value the dashboard
  /// shows. Not an attractiveness score.
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
/// imported report.
///
/// Both modules speak this type so the arithmetic and the rendering never need
/// to know where the numbers came from.
class ComparisonEntry {
  const ComparisonEntry({
    required this.label,
    required this.createdAt,
    required this.overallScore,
    required this.metrics,
    this.id,
    this.isImported = false,
    this.warnings = const <String>[],
  });

  /// What the card calls this side: `Earlier`, `Later`, the imported title.
  final String label;

  final DateTime createdAt;
  final double overallScore;
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
///
/// Deliberately arithmetic only. There is no "better" side: a larger number
/// means closer agreement with a reference band, which is a property of the
/// measurement, not a ranking of the person. For a comparison between two
/// people the direction is reported and nothing more.
class MetricDelta {
  const MetricDelta({required this.before, required this.after});

  final ComparisonMetric before;
  final ComparisonMetric after;

  MetricId get id => before.id;
  String get title => before.title;

  /// Agreement points on the second side minus the first.
  double get points => after.score - before.score;

  /// Percentage change relative to the first side.
  double get percentChange =>
      before.score <= 0 ? 0 : points / before.score * 100;

  /// The threshold below which a difference is inside capture noise rather than
  /// a real change.
  static const double flatThreshold = 0.5;

  bool get isHigher => points >= flatThreshold;
  bool get isLower => points <= -flatThreshold;
  bool get isFlat => !isHigher && !isLower;

  /// `+3.2%`, `−1.4%`, `0.0%`.
  String get percentText {
    if (isFlat) {
      return '0.0%';
    }
    final String sign = points > 0 ? '+' : '\u2212';
    return '$sign${percentChange.abs().toStringAsFixed(1)}%';
  }

  /// `+3`, `−2`, `0` — agreement points, for the difference column.
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
    final String amount = switch (id) {
      MetricId.eyeSymmetry => '${change.abs().toStringAsFixed(1)}%',
      MetricId.jawline => '${change.abs().toStringAsFixed(0)}\u00B0',
      MetricId.facialThirds => change.abs().toStringAsFixed(2),
    };
    return change > 0 ? '$amount higher' : '$amount lower';
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

  /// Measurements that moved up, down, or stayed inside the noise band.
  int get higherCount => deltas.where((MetricDelta d) => d.isHigher).length;

  int get lowerCount => deltas.where((MetricDelta d) => d.isLower).length;

  int get unchangedCount => deltas.where((MetricDelta d) => d.isFlat).length;

  /// True when every measurement is inside the noise band, i.e. the two sides
  /// cannot be told apart by this app.
  bool get allWithinNoise => deltas.every((MetricDelta d) => d.isFlat);

  /// Measurements ordered by the size of the change, largest first. Used for
  /// the detail list, not to rank people.
  List<MetricDelta> get byChange {
    final List<MetricDelta> ordered = List<MetricDelta>.of(deltas)
      ..sort(
        (MetricDelta a, MetricDelta b) =>
            b.points.abs().compareTo(a.points.abs()),
      );
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

  /// The single measurement with the largest change, when it clears the noise
  /// threshold.
  MetricDelta? get biggestSwing {
    if (deltas.isEmpty) {
      return null;
    }
    final MetricDelta first = byChange.first;
    return first.isFlat ? null : first;
  }

  /// `+3.0%` style text for the combined value.
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
