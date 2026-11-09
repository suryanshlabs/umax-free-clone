import 'dart:io';

import 'package:facial_analysis/core/image_store.dart';
import 'package:facial_analysis/core/report.dart';
import 'package:facial_analysis/data/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Future<Directory> Function() saved;

  setUp(() {
    saved = ImageStore.directoryResolver;
    temp = Directory.systemTemp.createTempSync('image_store_test_');
    ImageStore.directoryResolver = () async => temp;
  });

  tearDown(() {
    ImageStore.directoryResolver = saved;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  File write(String name) {
    final File file = File('${temp.path}/$name');
    file.writeAsStringSync('pixels');
    return file;
  }

  test('only files this app prepared are considered managed', () async {
    final File owned = write('analysis_square_1.png');
    final File foreign = write('holiday.jpg');

    expect(await ImageStore.isManaged(owned.path), isTrue);
    expect(await ImageStore.isManaged(foreign.path), isFalse);
    expect(
      await ImageStore.isManaged('/data/elsewhere/analysis_square_1.png'),
      isFalse,
    );
    expect(await ImageStore.isManaged(null), isFalse);
  });

  test('deleting a managed file leaves everything else alone', () async {
    final File owned = write('analysis_square_2.png');
    final File foreign = write('holiday.jpg');

    await ImageStore.deleteManaged(owned.path);
    await ImageStore.deleteManaged(foreign.path);

    expect(owned.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
  });

  test('the sweep keeps referenced photos and deletes orphans', () async {
    final File kept = write('analysis_square_3.png');
    final File orphan = write('analysis_square_4.png');
    final File unrelated = write('notes.txt');

    await ImageStore.sweepUnreferenced(<String?>[kept.path]);

    expect(kept.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('clearing prepared photos keeps unrelated temp files', () async {
    final File prepared = write('analysis_square_5.png');
    final File unrelated = write('camera_capture.jpg');

    await ImageStore.deleteAllPrepared();

    expect(prepared.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('removing a scan deletes its photo once it is unreferenced', () async {
    final File first = write('analysis_square_6.png');
    final File second = write('analysis_square_7.png');

    final ScanHistory history = ScanHistory(
      storage: MemoryScanHistoryStorage(),
    );
    await history.addSaved(
      SavedScan(
        id: 'a',
        createdAt: DateTime(2026, 1, 1),
        overallScore: 70,
        imagePath: first.path,
        metrics: const <SavedMetric>[
          SavedMetric(
            id: MetricId.eyeSymmetry,
            title: 'Eye symmetry',
            rawValue: '1.0%',
            score: 70,
          ),
        ],
      ),
    );
    await history.addSaved(
      SavedScan(
        id: 'b',
        createdAt: DateTime(2026, 1, 2),
        overallScore: 72,
        imagePath: second.path,
        metrics: const <SavedMetric>[
          SavedMetric(
            id: MetricId.eyeSymmetry,
            title: 'Eye symmetry',
            rawValue: '0.8%',
            score: 72,
          ),
        ],
      ),
    );

    await history.remove('a');
    expect(first.existsSync(), isFalse, reason: 'removed scan photo goes');
    expect(second.existsSync(), isTrue, reason: 'kept scan photo stays');

    await history.clear();
    expect(second.existsSync(), isFalse, reason: 'clear removes the rest');
  });

  test('a photo shared by two scans survives one deletion', () async {
    final File shared = write('analysis_square_8.png');

    final ScanHistory history = ScanHistory(
      storage: MemoryScanHistoryStorage(),
    );
    for (final String id in <String>['a', 'b']) {
      await history.addSaved(
        SavedScan(
          id: id,
          createdAt: DateTime(2026, 1, 1),
          overallScore: 70,
          imagePath: shared.path,
          metrics: const <SavedMetric>[
            SavedMetric(
              id: MetricId.eyeSymmetry,
              title: 'Eye symmetry',
              rawValue: '1.0%',
              score: 70,
            ),
          ],
        ),
      );
    }

    await history.remove('a');
    expect(shared.existsSync(), isTrue);
    await history.remove('b');
    expect(shared.existsSync(), isFalse);
  });
}
