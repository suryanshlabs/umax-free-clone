import '../core/metrics.dart';
import '../core/report.dart';
import '../core/user_profile.dart';

export 'scan_history_store.dart';

/// One scored measurement, flattened for storage.
class SavedMetric {
  const SavedMetric({
    required this.id,
    required this.title,
    required this.rawValue,
    required this.score,
    this.rawNumber,
    this.gender,
    this.age,
    this.bmi,
  });

  final MetricId id;
  final String title;
  final String rawValue;
  final double score;
  final double? rawNumber;
  final Gender? gender;
  final int? age;
  final double? bmi;

  /// `%`, `°`, or empty for the unitless thirds index.
  String get unit => switch (id) {
    MetricId.eyeSymmetry => '%',
    MetricId.jawline => '°',
    MetricId.facialThirds => '',
  };

  /// The same qualitative bands the live dashboard uses.
  String get scoreLabel {
    if (score >= 85) return 'Excellent';
    if (score >= 72) return 'Strong';
    if (score >= 58) return 'Balanced';
    if (score >= 42) return 'Room to grow';
    return 'Focus area';
  }

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
    'gender': gender?.name,
    'age': age,
    'bmi': bmi,
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
    final Object? rawGender = json['gender'];
    final Object? rawAge = json['age'];
    final Object? rawBmi = json['bmi'];
    return SavedMetric(
      id: metricId,
      title: title is String && title.isNotEmpty ? title : metricId.name,
      rawValue: rawValue is String ? rawValue : '—',
      score: rawScore.toDouble(),
      rawNumber: rawNumber is num ? rawNumber.toDouble() : null,
      gender: rawGender is String ? genderFromName(rawGender) : null,
      age: rawAge is int ? rawAge : null,
      bmi: rawBmi is num ? rawBmi.toDouble() : null,
    );
  }

}

Gender? genderFromName(String name) {
  for (final Gender g in Gender.values) {
    if (g.name == name) {
      return g;
    }
  }
  return null;
}

/// A completed analysis, small enough to keep dozens of.
class SavedScan {
  const SavedScan({
    required this.id,
    required this.createdAt,
    required this.overallScore,
    required this.grade,
    required this.metrics,
    this.warnings = const <String>[],
    this.imagePath,
    this.potentialScore,
    this.title,
    this.isFriend = false,
    this.profile,
  });

  final String id;
  final DateTime createdAt;
  final double overallScore;
  final String grade;
  final List<SavedMetric> metrics;
  final List<String> warnings;
  final String? imagePath;
  final double? potentialScore;
  final String? title;
  final bool isFriend;
  final UserProfile? profile;

  factory SavedScan.fromReport(AnalysisReport report) {
    final RawFaceMetrics raw = report.raw;
    return SavedScan(
      id: report.createdAt.microsecondsSinceEpoch.toString(),
      createdAt: report.createdAt,
      overallScore: report.overallScore,
      grade: report.grade,
      potentialScore: report.potentialScore,
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
      profile: report.profile,
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
    String? grade,
    List<SavedMetric>? metrics,
    List<String>? warnings,
    String? imagePath,
    double? potentialScore,
    String? title,
    bool? isFriend,
    UserProfile? profile,
  }) {
    return SavedScan(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      overallScore: overallScore ?? this.overallScore,
      grade: grade ?? this.grade,
      metrics: metrics ?? this.metrics,
      warnings: warnings ?? this.warnings,
      imagePath: imagePath ?? this.imagePath,
      potentialScore: potentialScore ?? this.potentialScore,
      title: title ?? this.title,
      isFriend: isFriend ?? this.isFriend,
      profile: profile ?? this.profile,
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

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'at': createdAt.toIso8601String(),
    'score': overallScore,
    'grade': grade,
    'potential': potentialScore,
    'title': title,
    'friend': isFriend,
    'profile': profile == null
        ? null
        : <String, Object?>{
            'gender': profile?.gender.name,
            'age': profile?.age,
            'heightCm': profile?.heightCm,
            'weightKg': profile?.weightKg,
            'heightKnown': profile?.heightKnown,
            'weightKnown': profile?.weightKnown,
          },
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
    final Object? rawGrade = json['grade'];
    final Object? rawImage = json['image'];
    final Object? rawPotential = json['potential'];
    final Object? rawTitle = json['title'];
    final Object? rawFriend = json['friend'];
    final Object? rawProfile = json['profile'];
    UserProfile? profile;
    if (rawProfile is Map) {
      final Gender? gender = rawProfile['gender'] is String
          ? genderFromName(rawProfile['gender'] as String)
          : null;
      final int? age = rawProfile['age'] is int ? rawProfile['age'] as int : null;
      final double? heightCm = rawProfile['heightCm'] is double
          ? rawProfile['heightCm'] as double
          : (rawProfile['heightCm'] is num ? (rawProfile['heightCm'] as num).toDouble() : null);
      final double? weightKg = rawProfile['weightKg'] is double
          ? rawProfile['weightKg'] as double
          : (rawProfile['weightKg'] is num ? (rawProfile['weightKg'] as num).toDouble() : null);
      final bool heightKnown = rawProfile['heightKnown'] == true;
      final bool weightKnown = rawProfile['weightKnown'] == true;
      profile = UserProfile(
        gender: gender ?? Gender.other,
        age: age ?? 0,
        heightCm: heightKnown ? heightCm : null,
        weightKg: weightKnown ? weightKg : null,
        heightKnown: heightKnown,
        weightKnown: weightKnown,
      );
    }
    return SavedScan(
      id: json['id'] is String
          ? json['id']! as String
          : createdAt.microsecondsSinceEpoch.toString(),
      createdAt: createdAt,
      overallScore: rawScore.toDouble(),
      grade: rawGrade is String ? rawGrade : 'Measured',
      metrics: metrics,
      warnings: rawWarnings is List
          ? <String>[
              for (final Object? warning in rawWarnings)
                if (warning is String) warning,
            ]
          : const <String>[],
      imagePath: rawImage is String ? rawImage : null,
      potentialScore: rawPotential is num ? rawPotential.toDouble() : null,
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : null,
      isFriend: rawFriend == true,
      profile: profile,
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _month(int month) {
    const List<String> names = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
