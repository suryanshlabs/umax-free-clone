import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// The live-camera overlay: a breathing face silhouette, a dimmed surround, and
/// the axis marks that make "eyes level, face in the middle" easy to follow.
///
/// Everything is drawn from [guideRect], so the silhouette and the copy on
/// screen can never drift apart.
class FaceGuidePainter extends CustomPainter {
  const FaceGuidePainter({required this.pulse, required this.lineColor});

  /// 0..1. Animated by the camera screen so the outline gently breathes.
  final double pulse;

  final Color lineColor;

  /// The oval the user is asked to fill, as a fraction of the preview box.
  static Rect guideRect(Size size) {
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.70,
      height: size.height * 0.56,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect guide = guideRect(size);
    final Path oval = Path()..addOval(guide);

    // Dim everything outside the guide: the face stays the brightest thing on
    // screen, which also nudges people to fill it.
    final Path mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(guide);
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.42),
    );

    _drawDashed(
      canvas,
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = lineColor.withValues(alpha: 0.28 + 0.24 * pulse),
    );

    // Thirds marks: the analysis measures vertical proportions, so the guide
    // shows where those lines are.
    final Paint tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (final double fraction in <double>[0.34, 0.60]) {
      final double y = guide.top + guide.height * fraction;
      final double half = guide.width * 0.16;
      canvas.drawLine(
        Offset(guide.center.dx - half, y),
        Offset(guide.center.dx + half, y),
        tick,
      );
    }

    // Vertical midline, so a turned head is obvious before the shutter.
    _drawDashed(
      canvas,
      Path()
        ..moveTo(guide.center.dx, guide.top + guide.height * 0.04)
        ..lineTo(guide.center.dx, guide.bottom - guide.height * 0.07),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
      dash: 4,
      gap: 12,
    );

    // Corner brackets frame the capture area.
    final Paint bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.5);
    final Rect frame = guide.inflate(size.width * 0.045);
    final double arm = math.min(frame.width, frame.height) * 0.075;
    void corner(Offset origin, Offset horizontal, Offset vertical) {
      canvas.drawLine(origin, origin + horizontal * arm, bracket);
      canvas.drawLine(origin, origin + vertical * arm, bracket);
    }

    corner(frame.topLeft, const Offset(1, 0), const Offset(0, 1));
    corner(frame.topRight, const Offset(-1, 0), const Offset(0, 1));
    corner(frame.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    corner(frame.bottomRight, const Offset(-1, 0), const Offset(0, -1));
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 7,
    double gap = 9,
  }) {
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) =>
      oldDelegate.pulse != pulse || oldDelegate.lineColor != lineColor;
}
