import 'dart:convert';

import 'package:facial_analysis/core/comparison.dart';
import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
import 'package:facial_analysis/data/scan_history.dart';
// flutter_test also exports a golden-file ComparisonResult; the app's model is
// the one this file is about.
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;

import 'support/metrics_fixture.dart';

void main() {
  const ScoringEngine engine = ScoringEngine();

  group('no unsupported ratings', () {
    test('the report exposes no potential score and no grade', () {
      final AnalysisReport report = engine.build(faceMetrics());

      // Compile-time proof: these fields no longer exist. If someone adds them
      // back, this file stops compiling rather than silently shipping.
      expect(report.bandLabel, isNotEmpty);
      expect(<String>[
        'Close',
        'Near',
        'Mixed',
        'Deviated',
        'Far',
      ], contains(report.bandLabel));
      expect(report.bandNote, isNotEmpty);
      expect(report.bandExplanation, isNotEmpty);
    });

    test('the share text makes no rating claim', () {
      final String text = engine
          .build(faceMetrics(jawAngle: 120))
          .toShareText()
          .toLowerCase();
      expect(text, contains('combined agreement'));
      expect(text, contains('not a medical or attractiveness assessment'));
      expect(text, isNot(contains('potential')));
      expect(text, isNot(contains('grade')));
      expect(text, isNot(contains('excellent')));
      expect(text, isNot(contains('strong')));
      expect(text, isNot(contains('room to grow')));
    });

    test('every metric is labelled as an agreement band', () {
      final AnalysisReport report = engine.build(faceMetrics());
      for (final MetricResult metric in report.metrics) {
        expect(<String>[
          'Close',
          'Near',
          'Mixed',
          'Deviated',
          'Far',
        ], contains(metric.scoreLabel));
      }
    });

    test('advice carries no weight-loss or appearance promises', () {
      final AnalysisReport report = engine.build(
        faceMetrics(asymmetry: 3.5, jawAngle: 140),
      );
      final StringBuffer all = StringBuffer()..write(report.coreWeakness.why);
      for (final MetricResult metric in report.metrics) {
        for (final AdviceItem item in metric.advice) {
          all
            ..write(' ')
            ..write(item.title)
            ..write(' ')
            ..write(item.detail);
        }
      }
      for (final RoadmapStep step in report.coreWeakness.steps) {
        all
          ..write(' ')
          ..write(step.detail);
      }
      final String text = all.toString().toLowerCase();
      for (final String banned in <String>[
        'calorie',
        'deficit',
        'lose fat',
        'weight loss',
        'target weight',
        'how much better you would look',
      ]) {
        expect(text, isNot(contains(banned)), reason: 'found "$banned"');
      }
      // The only medical advice allowed is the new-one-sided-change caveat.
      if (report.safetyNote != null) {
        expect(report.safetyNote!.toLowerCase(), contains('doctor'));
      }
    });
  });

  group('stored scans stay neutral', () {
    test('saved scans write no retired rating keys', () {
      final SavedScan scan = SavedScan.fromReport(
        engine.build(faceMetrics(), imagePath: '/tmp/example.png'),
      );
      final Map<String, Object?> json = scan.toJson();
      expect(json.keys, isNot(contains('grade')));
      expect(json.keys, isNot(contains('potential')));
      expect(json.keys, isNot(contains('profile')));
      expect(json.keys, isNot(contains('bmi')));

      final SavedScan reloaded = SavedScan.fromJson(
        jsonDecode(jsonEncode(json)) as Object?,
      )!;
      expect(reloaded.bandLabel, scan.bandLabel);
    });

    test('a legacy rating is ignored when the history is rewritten', () async {
      final MemoryScanHistoryStorage storage = MemoryScanHistoryStorage(
        '{"version":3,"scans":[{"id":"a","at":"2026-01-01T00:00:00.000",'
        '"score":88,"grade":"Excellent","potential":99,'
        '"metrics":[{"id":"jawline","title":"Chin angle","raw":"110°",'
        '"score":88}]}]}',
      );
      final ScanHistory history = ScanHistory(storage: storage);
      await history.load();

      expect(history.scans, hasLength(1));
      expect(history.scans.single.bandLabel, 'Close');

      await history.setProfile(null);
      final Map<String, Object?> written =
          jsonDecode(storage.contents!) as Map<String, Object?>;
      final Map<String, Object?> scan =
          (written['scans']! as List<Object?>).single! as Map<String, Object?>;
      expect(scan.containsKey('grade'), isFalse);
      expect(scan.containsKey('potential'), isFalse);
    });
  });

  group('comparison is arithmetic, not a contest', () {
    test('direction only, same colour semantics for both directions', () {
      final ComparisonEntry before = ComparisonEntry(
        label: 'A',
        createdAt: DateTime(2026),
        overallScore: 60,
        metrics: const <ComparisonMetric>[
          ComparisonMetric(
            id: MetricId.jawline,
            title: 'Chin angle',
            score: 60,
            rawValue: '120°',
            rawNumber: 120,
            unit: '°',
          ),
        ],
      );
      final ComparisonEntry after = ComparisonEntry(
        label: 'B',
        createdAt: DateTime(2026),
        overallScore: 50,
        metrics: const <ComparisonMetric>[
          ComparisonMetric(
            id: MetricId.jawline,
            title: 'Chin angle',
            score: 50,
            rawValue: '130°',
            rawNumber: 130,
            unit: '°',
          ),
        ],
      );
      final ComparisonResult result = ComparisonResult(
        before: before,
        after: after,
      );

      expect(result.lowerCount, 1);
      expect(result.higherCount, 0);
      expect(result.deltas.single.rawChangeText, '10\u00B0 higher');
      expect(result.deltas.single.isLower, isTrue);
      // No "winner" language exists in the model.
      expect(result.allWithinNoise, isFalse);
    });
  });
}
