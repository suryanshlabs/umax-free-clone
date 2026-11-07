import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/report.dart';

/// One scored measurement, flattened for storage.
///
/// Only what a comparison needs is kept: the identifier, the printed value and
/// the score. The advice text is regenerated from the live calibration if a
/// report is opened again, so an app update cannot leave stale advice behind.
class SavedMetric {
  const SavedMetric({
    required this.id,
    required this.title,
    required this.rawValue,
    required this.score,
  });

  final MetricId id;
  final String title;
  final String rawValue;
  final double score;

  /// The same qualitative bands the live dashboard uses.
  String get scoreLabel {
    if (score >= 85) return 'Excellent';
    if (score >= 72) return 'Strong';
    if (score >= 58) return 'Balanced';
    if (score >= 42) return 'Room to grow';
    return 'Focus area';
  }

  factory SavedMetric.fromMetric(MetricResult metric) {
    return SavedMetric(
      id: metric.id,
      title: metric.title,
      rawValue: metric.rawValue,
      score: metric.score,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.name,
    'title': title,
    'raw': rawValue,
    'score': score,
  };

  /// Returns null for anything unreadable, so one corrupt entry cannot take the
  /// whole history with it.
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
    return SavedMetric(
      id: metricId,
      title: title is String && title.isNotEmpty ? title : metricId.name,
      rawValue: rawValue is String ? rawValue : '—',
      score: rawScore.toDouble(),
    );
  }
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
  });

  final String id;
  final DateTime createdAt;
  final double overallScore;
  final String grade;
  final List<SavedMetric> metrics;
  final List<String> warnings;
  final String? imagePath;

  factory SavedScan.fromReport(AnalysisReport report) {
    return SavedScan(
      id: report.createdAt.microsecondsSinceEpoch.toString(),
      createdAt: report.createdAt,
      overallScore: report.overallScore,
      grade: report.grade,
      metrics: <SavedMetric>[
        for (final MetricResult metric in report.metrics)
          SavedMetric.fromMetric(metric),
      ],
      warnings: report.qualityWarnings,
      imagePath: report.imagePath,
    );
  }

  String get scoreText => overallScore.toStringAsFixed(0);

  /// `12 Nov 2026 · 14:05`
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
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _month(int month) {
    const List<String> names = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}

/// Where the saved scans live. Swappable so tests never touch the file system.
abstract interface class ScanHistoryStorage {
  Future<String?> read();

  Future<void> write(String contents);
}

/// JSON file in the app's private support directory. No permission is needed
/// and no other app (or the network) can read it.
class FileScanHistoryStorage implements ScanHistoryStorage {
  FileScanHistoryStorage({this.fileName = 'scan_history.json'});

  final String fileName;

  Future<File> _file() async {
    final Directory directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$fileName');
  }

  @override
  Future<String?> read() async {
    final File file = await _file();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    final File file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  }
}

/// In-memory storage used by tests.
class MemoryScanHistoryStorage implements ScanHistoryStorage {
  MemoryScanHistoryStorage([this.contents]);

  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async => contents = value;
}

/// The saved-scan list: newest first, persisted on every change.
///
/// A [ChangeNotifier] rather than a stream because three screens read it at
/// once and none of them need per-entry granularity.
class ScanHistory extends ChangeNotifier {
  ScanHistory({ScanHistoryStorage? storage, this.maxEntries = 60})
    : _storage = storage ?? FileScanHistoryStorage();

  static const int version = 1;

  final ScanHistoryStorage _storage;
  final int maxEntries;

  List<SavedScan> _scans = <SavedScan>[];
  bool _loaded = false;
  bool _loading = false;

  List<SavedScan> get scans => List<SavedScan>.unmodifiable(_scans);

  bool get isLoaded => _loaded;

  bool get isLoading => _loading;

  bool get isEmpty => _scans.isEmpty;

  /// Reads the file once. Safe to call from every screen's `initState`.
  Future<void> load() async {
    if (_loaded || _loading) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final String? contents = await _storage.read();
      _scans = _decode(contents);
    } on Exception catch (error) {
      debugPrint('Scan history could not be read: $error');
      _scans = <SavedScan>[];
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Records a finished analysis. Persistence failures are logged but never
  /// fail the scan the user just waited for.
  Future<void> add(AnalysisReport report) =>
      addSaved(SavedScan.fromReport(report));

  Future<void> addSaved(SavedScan scan) async {
    _scans = <SavedScan>[scan, ..._scans];
    if (_scans.length > maxEntries) {
      _scans = _scans.sublist(0, maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _scans = <SavedScan>[
      for (final SavedScan scan in _scans)
        if (scan.id != id) scan,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _scans = <SavedScan>[];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _storage.write(
        jsonEncode(<String, Object?>{
          'version': version,
          'scans': <Object?>[
            for (final SavedScan scan in _scans) scan.toJson(),
          ],
        }),
      );
    } on Exception catch (error) {
      debugPrint('Scan history could not be saved: $error');
    }
  }

  List<SavedScan> _decode(String? contents) {
    if (contents == null || contents.trim().isEmpty) {
      return <SavedScan>[];
    }
    try {
      final Object? decoded = jsonDecode(contents);
      if (decoded is! Map) {
        return <SavedScan>[];
      }
      final Object? rawScans = decoded['scans'];
      if (rawScans is! List) {
        return <SavedScan>[];
      }
      final List<SavedScan> scans = <SavedScan>[];
      for (final Object? entry in rawScans) {
        final SavedScan? scan = SavedScan.fromJson(entry);
        if (scan != null) {
          scans.add(scan);
        }
      }
      scans.sort(
        (SavedScan a, SavedScan b) => b.createdAt.compareTo(a.createdAt),
      );
      return scans;
    } on FormatException {
      return <SavedScan>[];
    }
  }
}
