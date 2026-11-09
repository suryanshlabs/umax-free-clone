import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facial_analysis/ui/widgets/scanning_painter.dart';

void main() {
  testWidgets('ScanningPainter does not throw when painting a valid size', (
    WidgetTester tester,
  ) async {
    // Pump a real widget tree so the framework actually walks the
    // CustomPaint path and invokes ScanningPainter.paint(). If the band
    // gradient is invalid (three colours without colourStops), paint()
    // throws ArgumentError and the test fails.
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(
          body: CustomPaint(
            painter: ScanningPainter(progress: 0.45, meshOpacity: 0.8),
          ),
        ),
      ),
    );
    await tester.pump();
    // Second pump: some test harness paths only paint on the second frame.
    await tester.pump();
  });

  group('direct painter calls', () {
    // RenderObject-style coverage for the progress branches without spinning
    // up a full widget tree. We invoke paint() directly with a real Canvas
    // and Size and assert it does not throw.
    final List<double> progressValues = <double>[0.0, 0.45, 0.82, 1.0];

    for (final double progress in progressValues) {
      test('paints without throwing at progress=$progress', () {
        final ScanningPainter painter = ScanningPainter(
          progress: progress,
          meshOpacity: 1.0,
        );

        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 200, 200));

        // This is the path that used to throw:
        //   Gradient._validateColorStops ->
        //   "colors" must have length 2 if "colorStops" is omitted.
        painter.paint(canvas, const Size(200, 200));

        // If we reach here, paint() completed for this progress value,
        // including the scanning-band gradient with three colours and
        // explicit stops.
      });
    }

    test('paints smaller size without throwing', () {
      final ScanningPainter painter = ScanningPainter(
        progress: 0.6,
        meshOpacity: 0.5,
      );
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 100, 100));
      painter.paint(canvas, const Size(100, 100));
    });

    test('paints with alpha fade without throwing', () {
      final ScanningPainter painter = ScanningPainter(
        progress: 0.3,
        meshOpacity: 0.15,
      );
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 200, 200));
      painter.paint(canvas, const Size(200, 200));
    });
  });
}
