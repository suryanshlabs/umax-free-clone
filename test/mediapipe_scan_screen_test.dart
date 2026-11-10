import 'package:facial_analysis/ui/media_pipe_face_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression tests for the MediaPipe Face Scan screen.
//
// The screen used to place `Positioned` widgets inside a `Row`, which throws
// "type 'FlexParentData' is not a subtype of type 'StackParentData'" as soon as
// the tree is built. It also used fixed pixel coordinates for the guide overlay,
// so the copy landed on top of the controls. These tests build the real widget
// tree at phone sizes and fail on any exception or overflow.
void main() {
  Future<void> pumpScreen(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: MediaPipeFaceScanScreen()),
    );
    // The camera plugin is not available in tests, so bootstrap settles into
    // the "camera could not start" state. One more pump lets that land.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('builds without a parent-data or layout exception',
      (WidgetTester tester) async {
    await pumpScreen(tester, const Size(411, 750));

    expect(tester.takeException(), isNull);
    expect(find.text('MediaPipe Face Scan'), findsOneWidget);
    expect(find.text('View 1 of 3'), findsOneWidget);
    // All three view chips are laid out as flex children of the strip.
    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Left 3/4'), findsOneWidget);
    expect(find.text('Right 3/4'), findsOneWidget);
  });

  testWidgets('builds on a small phone and a tall phone without overflowing',
      (WidgetTester tester) async {
    await pumpScreen(tester, const Size(360, 640));
    expect(tester.takeException(), isNull);

    await pumpScreen(tester, const Size(430, 932));
    expect(tester.takeException(), isNull);
  });
}
