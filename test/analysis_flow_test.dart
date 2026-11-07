import 'package:facial_analysis/core/facial_analysis_service.dart';
import 'package:facial_analysis/state/analysis_controller.dart';
import 'package:facial_analysis/ui/results_screen.dart';
import 'package:facial_analysis/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_mesh_source.dart';

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
      expect(controller.errorMessage, contains('No face'));
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
    tester.view.physicalSize = const Size(1200, 2600);
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
    expect(find.text('Eye symmetry'), findsOneWidget);
    expect(find.text('Jawline angularity'), findsOneWidget);
    expect(find.text('Facial thirds'), findsOneWidget);
    expect(find.textContaining('468 landmarks'), findsOneWidget);

    controller.dispose();
  });
}
