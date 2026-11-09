import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/data/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

SavedScan buildScan({
  required String id,
  required double score,
  required DateTime at,
}) {
  return SavedScan(
    id: id,
    createdAt: at,
    overallScore: score,
    metrics: const <SavedMetric>[
      SavedMetric(
        id: MetricId.eyeSymmetry,
        title: 'Eye symmetry',
        rawValue: '1.2%',
        score: 71,
      ),
      SavedMetric(
        id: MetricId.jawline,
        title: 'Jawline angularity',
        rawValue: '96°',
        score: 64,
      ),
      SavedMetric(
        id: MetricId.facialThirds,
        title: 'Facial thirds',
        rawValue: '1:1:1',
        score: 80,
      ),
    ],
  );
}

void main() {
  test('saves scans and reads them back newest first', () async {
    final MemoryScanHistoryStorage storage = MemoryScanHistoryStorage();
    final ScanHistory history = ScanHistory(storage: storage);
    await history.load();
    expect(history.isEmpty, isTrue);
    expect(history.isLoaded, isTrue);

    await history.addSaved(
      buildScan(id: 'older', score: 61, at: DateTime(2026, 10, 1, 9)),
    );
    await history.addSaved(
      buildScan(id: 'newer', score: 68, at: DateTime(2026, 11, 2, 18)),
    );

    expect(storage.contents, isNotNull);

    final ScanHistory reloaded = ScanHistory(storage: storage);
    await reloaded.load();

    expect(reloaded.scans, hasLength(2));
    expect(reloaded.scans.first.id, 'newer');
    expect(reloaded.scans.first.overallScore, 68);
    expect(
      reloaded.scans.first.bandLabel,
      ReportBand.fromScore(reloaded.scans.first.overallScore).label,
    );
    expect(reloaded.scans.first.metric(MetricId.jawline)?.rawValue, '96°');
    expect(reloaded.scans.first.metric(MetricId.jawline)?.score, 64);
    expect(reloaded.scans.last.id, 'older');
  });

  test('deletes one scan and then all of them', () async {
    final MemoryScanHistoryStorage storage = MemoryScanHistoryStorage();
    final ScanHistory history = ScanHistory(storage: storage);
    await history.load();
    await history.addSaved(
      buildScan(id: 'a', score: 60, at: DateTime(2026, 9, 1)),
    );
    await history.addSaved(
      buildScan(id: 'b', score: 70, at: DateTime(2026, 9, 2)),
    );

    await history.remove('a');
    expect(history.scans.single.id, 'b');

    final ScanHistory afterReload = ScanHistory(storage: storage);
    await afterReload.load();
    expect(afterReload.scans.single.id, 'b');

    await afterReload.clear();
    expect(afterReload.scans, isEmpty);
  });

  test('keeps the newest scans when the cap is reached', () async {
    final ScanHistory history = ScanHistory(
      storage: MemoryScanHistoryStorage(),
      maxEntries: 2,
    );
    await history.load();
    for (int day = 1; day <= 4; day += 1) {
      await history.addSaved(
        buildScan(
          id: 'scan-$day',
          score: (50 + day).toDouble(),
          at: DateTime(2026, 9, day),
        ),
      );
    }
    expect(history.scans.map((SavedScan scan) => scan.id), <String>[
      'scan-4',
      'scan-3',
    ]);
  });

  test('a corrupt file loads as an empty list instead of throwing', () async {
    final ScanHistory history = ScanHistory(
      storage: MemoryScanHistoryStorage('{ this is not json'),
    );
    await history.load();
    expect(history.scans, isEmpty);
    expect(history.isLoaded, isTrue);
  });

  test(
    'an entry missing its metrics is skipped, not treated as fatal',
    () async {
      final ScanHistory history = ScanHistory(
        storage: MemoryScanHistoryStorage(
          '{"version":1,"scans":[{"id":"x","at":"2026-09-01T10:00:00.000",'
          '"score":70,"grade":"Balanced","metrics":[]}]}',
        ),
      );
      await history.load();
      expect(history.scans, isEmpty);
    },
  );
}
