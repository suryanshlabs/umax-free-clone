import 'dart:convert';

import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/core/scoring_engine.dart';
import 'package:facial_analysis/core/umax_file.dart';
import 'package:facial_analysis/data/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/metrics_fixture.dart';

AnalysisReport buildReport({DateTime? at}) => const ScoringEngine().build(
  faceMetrics(asymmetry: 2.4, jawAngle: 118),
  createdAt: at ?? DateTime(2026, 10, 4, 18, 30),
);

void main() {
  test('a report round-trips through .umax with its raw numbers intact', () {
    final AnalysisReport report = buildReport();
    final UmaxDocument document = UmaxDocument.fromReport(
      report,
      title: '  Alex   jawline check ',
    );

    expect(document.title, 'Alex jawline check');

    final UmaxDocument decoded = UmaxDocument.decode(document.encode());

    expect(decoded.title, 'Alex jawline check');
    expect(decoded.scan.overallScore, closeTo(report.overallScore, 1e-9));
    expect(
      decoded.scan.metrics.map((SavedMetric m) => m.score).toList(),
      report.metrics.map((MetricResult m) => m.score).toList(),
    );
    expect(decoded.scan.createdAt, report.createdAt);
    expect(decoded.scan.metrics, hasLength(3));

    final SavedMetric jaw = decoded.scan.metric(MetricId.jawline)!;
    expect(jaw.score, closeTo(report.metric(MetricId.jawline).score, 1e-9));
    expect(jaw.rawNumber, closeTo(118, 1e-9));
    expect(jaw.unit, '\u00B0');
  });

  test('the encoded file is plain readable JSON with a version marker', () {
    final UmaxDocument document = UmaxDocument.fromReport(
      buildReport(),
      title: 'Sam',
    );

    final Object? decoded = jsonDecode(document.encode());
    expect(decoded, isA<Map<String, Object?>>());
    final Map<String, Object?> map = decoded! as Map<String, Object?>;
    expect(map['format'], 'umax');
    expect(map['formatVersion'], 1);
    expect(map['title'], 'Sam');
    // No image path or bytes travel with the report.
    final Map<String, Object?> scan = map['scan']! as Map<String, Object?>;
    expect(scan['image'], isNull);
    expect(document.encode(), isNot(contains('base64')));
  });

  test('an imported document becomes a friend entry with its title', () {
    final UmaxDocument document = UmaxDocument.fromReport(
      buildReport(),
      title: 'Jordan',
    );
    final SavedScan imported = UmaxDocument.decode(
      document.encode(),
    ).asImportedScan();

    expect(imported.isFriend, isTrue);
    expect(imported.title, 'Jordan');
    expect(imported.displayTitle, 'Jordan');
    expect(imported.id, startsWith('friend-'));
  });

  test('a newer format version is refused with a readable sentence', () {
    final String contents = jsonEncode(<String, Object?>{
      'format': 'umax',
      'formatVersion': 99,
      'title': 'Future',
      'scan': UmaxDocument.fromReport(buildReport(), title: 'x').scan.toJson(),
    });

    expect(
      () => UmaxDocument.decode(contents),
      throwsA(
        isA<UmaxFormatException>().having(
          (UmaxFormatException e) => e.message,
          'message',
          contains('newer version'),
        ),
      ),
    );
  });

  test('garbage and foreign files are refused, not half-read', () {
    expect(
      () => UmaxDocument.decode('not json at all'),
      throwsA(isA<UmaxFormatException>()),
    );
    expect(
      () => UmaxDocument.decode('{"format":"other","scans":[]}'),
      throwsA(isA<UmaxFormatException>()),
    );
    expect(() => UmaxDocument.decode(''), throwsA(isA<UmaxFormatException>()));
    expect(
      () => UmaxDocument.decode(
        '{"format":"umax","formatVersion":1,"title":"x","scan":{"id":"1"}}',
      ),
      throwsA(
        isA<UmaxFormatException>().having(
          (UmaxFormatException e) => e.message,
          'message',
          contains('missing its measurements'),
        ),
      ),
    );
  });

  test('titles and file names are made safe', () {
    expect(UmaxDocument.sanitiseTitle('   '), 'Shared report');
    expect(UmaxDocument.sanitiseTitle('a' * 100), hasLength(60));
    expect(
      UmaxDocument.sanitiseTitle('Alex  /  jawline\ncheck'),
      'Alex / jawline check',
    );

    final String name = UmaxDocument.suggestedFileName('Alex / jawline check');
    expect(name, endsWith('.umax'));
    expect(name, contains('alex-jawline-check-'));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains(' ')));
  });
}
