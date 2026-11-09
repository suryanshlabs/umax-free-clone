import '../core/metrics.dart';
import '../core/report.dart';

export 'scan_history_store.dart';

/// One scored measurement, flattened for storage.
///
/// A saved measurement is geometry only. Older files also carried age, gender
/// and BMI copies on each metric; those keys are ignored on read and are no
/// longer written, so a scan can never carry body-composition data again.
class SavedMetric {
  const SavedMetric({
    required this.id,
    required this.title,
    required this.rawValue,
    required this.score,
    this.rawNumber,
  });

  final MetricId id;
  final String title;
  final String rawValue;
  final double score;
  final double? rawNumber;

  /// `%`, `°`, or empty for the unitless thirds index.
  String get unit => switch (id) {
    MetricId.eyeSymmetry => '%',
    MetricId.jawline => '°',
    MetricId.facialThirds => '',
  };

  /// The same agreement band the live dashboard uses.
  String get scoreLabel => ReportBand.fromScore(score).label;

  factory SavedMetric.fromMetric(MetricResult metric, {double? rawNumber}) {
    return SavedMetric(
      id: metric.id,
      title: metric.title,
      rawValue: metric.rawValue,
      score: metric.score,
      rawNumber: rawNumber,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.name,
    'title': title,
    'raw': rawValue,
    'score': score,
    'number': rawNumber,
  };

  static SavedMetric? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? rawId = json['id'];
    MetricId? metricId;
    for (final MetricId candidate in MetricId.values) {
      if (candidate.name == rawId) {
        metricId = candidate;
        break;
      }
    }
    final Object? rawScore = json['score'];
    if (metricId == null || rawScore is! num) {
      return null;
    }
    final Object? title = json['title'];
    final Object? rawValue = json['raw'];
    final Object? rawNumber = json['number'];
    return SavedMetric(
      id: metricId,
      title: title is String && title.isNotEmpty ? title : metricId.name,
      rawValue: rawValue is String ? rawValue : '—',
      score: rawScore.toDouble(),
      rawNumber: rawNumber is num ? rawNumber.toDouble() : null,
    );
  }
}

/// A completed analysis, small enough to keep dozens of.
class SavedScan {
  const SavedScan({
    required this.id,
    required this.createdAt,
    required this.overallScore,
    required this.metrics,
    this.warnings = const <String>[],
    this.imagePath,
    this.title,
    this.isFriend = false,
  });

  final String id;
  final DateTime createdAt;
  final double overallScore;
  final List<SavedMetric> metrics;
  final List<String> warnings;
  final String? imagePath;
  final String? title;
  final bool isFriend;

  /// Agreement band, derived from the stored score. Older files carried a
  /// `grade` string; it is ignored so a retired rating can never resurface in
  /// history, which keeps the wording consistent with the current app.
  String get bandLabel => ReportBand.fromScore(overallScore).label;

  factory SavedScan.fromReport(AnalysisReport report) {
    final RawFaceMetrics raw = report.raw;
    return SavedScan(
      id: report.createdAt.microsecondsSinceEpoch.toString(),
      createdAt: report.createdAt,
      overallScore: report.overallScore,
      metrics: <SavedMetric>[
        for (final MetricResult metric in report.metrics)
          SavedMetric.fromMetric(
            metric,
            rawNumber: switch (metric.id) {
              MetricId.eyeSymmetry => raw.eyeAsymmetryPercent,
              MetricId.jawline => raw.jawAngleDegrees,
              MetricId.facialThirds => raw.thirdsDeviation,
            },
          ),
      ],
      warnings: report.qualityWarnings,
      imagePath: report.imagePath,
    );
  }

  String get displayTitle {
    final String? named = title;
    if (named != null && named.isNotEmpty) {
      return named;
    }
    return isFriend ? 'Shared report' : 'Your scan';
  }

  SavedScan copyWith({
    String? id,
    DateTime? createdAt,
    double? overallScore,
    List<SavedMetric>? metrics,
    List<String>? warnings,
    String? imagePath,
    String? title,
    bool? isFriend,
  }) {
    return SavedScan(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      overallScore: overallScore ?? this.overallScore,
      metrics: metrics ?? this.metrics,
      warnings: warnings ?? this.warnings,
      imagePath: imagePath ?? this.imagePath,
      title: title ?? this.title,
      isFriend: isFriend ?? this.isFriend,
    );
  }

  String get scoreText => overallScore.toStringAsFixed(0);

  String get shortDate =>
      '${_month(createdAt.month)} ${createdAt.day} '
      '${createdAt.year} · ${_two(createdAt.hour)}:${_two(createdAt.minute)}';

  SavedMetric? metric(MetricId id) {
    for (final SavedMetric metric in metrics) {
      if (metric.id == id) {
        return metric;
      }
    }
    return null;
  }

  /// No `profile` key: a scan record holds geometry, not body composition. The
  /// older `profile` key in an existing file is ignored rather than migrated
  /// onto a new scan.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'at': createdAt.toIso8601String(),
    'score': overallScore,
    'title': title,
    'friend': isFriend,
    'metrics': <Object?>[
      for (final SavedMetric metric in metrics) metric.toJson(),
    ],
    'warnings': warnings,
    'image': imagePath,
  };

  static SavedScan? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? rawAt = json['at'];
    final Object? rawScore = json['score'];
    if (rawAt is! String || rawScore is! num) {
      return null;
    }
    final DateTime? createdAt = DateTime.tryParse(rawAt);
    if (createdAt == null) {
      return null;
    }
    final List<SavedMetric> metrics = <SavedMetric>[];
    final Object? rawMetrics = json['metrics'];
    if (rawMetrics is List) {
      for (final Object? entry in rawMetrics) {
        final SavedMetric? metric = SavedMetric.fromJson(entry);
        if (metric != null) {
          metrics.add(metric);
        }
      }
    }
    if (metrics.isEmpty) {
      return null;
    }
    final Object? rawWarnings = json['warnings'];
    final Object? rawImage = json['image'];
    final Object? rawTitle = json['title'];
    final Object? rawFriend = json['friend'];
    return SavedScan(
      id: json['id'] is String
          ? json['id']! as String
          : createdAt.microsecondsSinceEpoch.toString(),
      createdAt: createdAt,
      overallScore: rawScore.toDouble(),
      metrics: metrics,
      warnings: rawWarnings is List
          ? <String>[
              for (final Object? warning in rawWarnings)
                if (warning is String) warning,
            ]
          : const <String>[],
      imagePath: rawImage is String ? rawImage : null,
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : null,
      isFriend: rawFriend == true,
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _month(int month) {
    const List<String> names = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
