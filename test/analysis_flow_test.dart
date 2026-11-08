import 'dart:async';

import 'package:facial_analysis/core/facial_analysis_service.dart';
import 'package:facial_analysis/ml/face_mesh_source.dart';
import 'package:facial_analysis/state/analysis_controller.dart';
import 'package:facial_analysis/ui/results_screen.dart';
import 'package:facial_analysis/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:facial_analysis/data/scan_history.dart';

import 'support/fake_mesh_source.dart';

/// A detector that never completes, standing in for a wedged platform channel.
class _HangingSource implements FaceMeshSource {
  @override
  Future<FaceMeshReading?> readFile(String path, {double? imageAspectRatio}) =>
      Completer<FaceMeshReading?>().future;

  @override
  Future<void> dispose() async {}
}

void main() {
  group('AnalysisController', () {
    test('runs the pipeline end to end', () async {
      final FakeFaceMeshSource source = FakeFaceMeshSource(
        reading: syntheticReading(),
      );
      final AnalysisController controller = AnalysisController(reader: source);

      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      expect(controller.phase, AnalysisPhase.ready);
      expect(controller.report, isNotNull);
      expect(controller.report!.metrics, hasLength(3));
      expect(source.readCount, 1);
      controller.dispose();
      expect(source.disposed, isTrue);
    });

    test('reports "no face" as an actionable failure', () async {
      final AnalysisController controller = AnalysisController(
        reader: FakeFaceMeshSource(),
      );

      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      expect(controller.phase, AnalysisPhase.failed);
      expect(controller.report, isNull);
      expect(controller.errorMessage, faceNotDetectedMessage);
      controller.dispose();
    });

    test('gives up on a detector that never answers', () async {
      final AnalysisController controller = AnalysisController(
        reader: _HangingSource(),
        timeout: const Duration(milliseconds: 40),
      );

      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      expect(controller.phase, AnalysisPhase.failed);
      expect(controller.report, isNull);
      // A timeout is no longer reported as "face not detected": the user
      // gets the honest timeout message instead.
      expect(controller.errorMessage, detectionTimedOutMessage);
      controller.dispose();
    });

    test('records a finished scan in the history store', () async {
      final ScanHistory history = ScanHistory(
        storage: MemoryScanHistoryStorage(),
      );
      await history.load();
      final AnalysisController controller = AnalysisController(
        reader: FakeFaceMeshSource(reading: syntheticReading()),
        history: history,
      );

      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      expect(history.scans, hasLength(1));
      expect(
        history.scans.single.overallScore,
        controller.report!.overallScore,
      );
      controller.dispose();
    });

    test('surfaces detector exceptions as friendly text', () async {
      final AnalysisController controller = AnalysisController(
        reader: FakeFaceMeshSource(
          error: const FacialAnalysisException('Mesh incomplete.'),
        ),
      );

      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      expect(controller.phase, AnalysisPhase.failed);
      expect(controller.errorMessage, 'Mesh incomplete.');
      controller.dispose();
    });

    test('surfaces non-Exception errors with their real message', () async {
      // An Error (not an Exception) used to escape the controller and freeze
      // the UI on "ANALYSING"; now it must land on the failed state with the
      // actual error named.
      final AnalysisController controller = AnalysisController(
        reader: FakeFaceMeshSource(error: StateError('detector wedged')),
      );

      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      expect(controller.phase, AnalysisPhase.failed);
      expect(controller.isAnalysing, isFalse);
      expect(controller.errorMessage, contains('StateError'));
      expect(controller.errorMessage, contains('detector wedged'));
      controller.dispose();
    });

    test('ignores a second analyse call while one is running', () async {
      final FakeFaceMeshSource source = FakeFaceMeshSource(
        reading: syntheticReading(),
      );
      final AnalysisController controller = AnalysisController(
        reader: source,
        timeout: const Duration(seconds: 5),
      );

      final Future<void> first = controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );
      // This call must be a no-op: the first run owns the pipeline.
      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );
      await first;

      expect(source.readCount, 1);
      expect(controller.phase, AnalysisPhase.ready);
      expect(controller.isAnalysing, isFalse);
      controller.dispose();
    });

    test('reset clears the result', () async {
      final AnalysisController controller = AnalysisController(
        reader: FakeFaceMeshSource(reading: syntheticReading()),
      );
      await controller.analyse(
        '/tmp/photo.jpg',
        minimumVisibleTime: Duration.zero,
      );

      controller.reset();

      expect(controller.phase, AnalysisPhase.idle);
      expect(controller.report, isNull);
      controller.dispose();
    });
  });

  testWidgets('results dashboard renders scores and advice', (
    WidgetTester tester,
  ) async {
    // Tall enough that the lazily built sliver renders every card, including
    // the projection and roadmap sections below the score.
    tester.view.physicalSize = const Size(1200, 6200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AnalysisController controller = AnalysisController(
      reader: FakeFaceMeshSource(reading: syntheticReading()),
    );
    await controller.analyse(
      '/tmp/photo.jpg',
      minimumVisibleTime: Duration.zero,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AnalysisController>.value(
        value: controller,
        child: MaterialApp(theme: buildAppTheme(), home: const ResultsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Analysis complete'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    // Each title appears on its measurement card and, for the weakest one, on
    // the core-weakness card as well.
    expect(find.text('Eye symmetry'), findsWidgets);
    expect(find.text('Jawline angularity'), findsWidgets);
    expect(find.text('Facial thirds'), findsWidgets);
    expect(find.textContaining('468 landmarks'), findsOneWidget);
    expect(find.text('POTENTIAL'), findsOneWidget);
    expect(find.text('CORE WEAKNESS AREA'), findsOneWidget);

    controller.dispose();
  });
}
