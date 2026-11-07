import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The processing animation: a stylised face lattice that lights up as a scan
/// band sweeps down the face.
///
/// Pure canvas — no video, no Lottie, no image assets — so it starts instantly,
/// scales to any screen and costs a couple of milliseconds a frame. The lattice
/// is a hand-built approximation of the mesh shape rather than the real 468
/// points, because the real points are exactly what the device is still busy
/// computing at this moment.
class ScanningPainter extends CustomPainter {
  const ScanningPainter({required this.progress, required this.meshOpacity});

  /// 0..1 sweep position.
  final double progress;

  /// 0..1 fade for the lattice, used to calm the animation on the error state.
  final double meshOpacity;

  static const int _rows = 13;
  static const int _columns = 11;

  static List<List<Offset>>? _meshCache;

  static List<List<Offset>> get _mesh => _meshCache ??= _buildMesh();

  /// Builds the lattice once in unit space, then reuses it forever.
  static List<List<Offset>> _buildMesh() {
    final List<List<Offset>> rows = <List<Offset>>[];
    for (int r = 0; r < _rows; r++) {
      final double v = r / (_rows - 1);
      final double spreadSquared = 1 - math.pow((v - 0.5) * 2, 2).toDouble();
      final double halfWidth = math.sqrt(math.max(0.0, spreadSquared));
      final List<Offset> row = <Offset>[];
      for (int c = 0; c < _columns; c++) {
        final double u = c / (_columns - 1);
        final double x = 0.5 + (u - 0.5) * halfWidth * 0.96;
        // Curve each row slightly so the lattice reads as a surface, not a grid.
        final double bow =
            math.sin((u - 0.5) * math.pi) * 0.02 * (1 - (v - 0.5).abs() * 2);
        row.add(Offset(x, v + bow));
      }
      rows.add(row);
    }
    return rows;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.68,
      height: size.height * 0.68,
    );
    final Path oval = Path()..addOval(rect);
    final double scanY = rect.top - 30 + (rect.height + 60) * progress;

    canvas.save();
    canvas.clipPath(oval);

    final Paint lattice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.accentSoft.withValues(alpha: 0.20 * meshOpacity);

    for (final List<Offset> row in _mesh) {
      final Path path = Path();
      for (int i = 0; i < row.length; i++) {
        final Offset point = _map(row[i], rect);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, lattice);
    }

    for (int c = 0; c < _columns; c++) {
      final Path path = Path();
      for (int r = 0; r < _mesh.length; r++) {
        final Offset point = _map(_mesh[r][c], rect);
        if (r == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, lattice);
    }

    // Landmark dots, brightest where the scan band is passing.
    for (final List<Offset> row in _mesh) {
      for (final Offset unit in row) {
        final Offset point = _map(unit, rect);
        final double proximity = (1 - (point.dy - scanY).abs() / 90).clamp(
          0.0,
          1.0,
        );
        canvas.drawCircle(
          point,
          1 + 1.6 * proximity,
          Paint()
            ..color = AppColors.mint.withValues(
              alpha: (0.12 + 0.7 * proximity) * meshOpacity,
            ),
        );
      }
    }

    // The band itself: a soft gradient trailing above the leading edge.
    final Paint band = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, scanY - 90),
        Offset(0, scanY + 8),
        <Color>[
          AppColors.accent.withValues(alpha: 0),
          AppColors.accent.withValues(alpha: 0.28),
          AppColors.mint.withValues(alpha: 0.04),
        ],
      );
    canvas.drawRect(
      Rect.fromLTRB(rect.left, scanY - 90, rect.right, scanY + 8),
      band,
    );
    canvas.restore();

    // Leading edge with a glow, drawn outside the clip so it can bleed.
    final Offset left = Offset(rect.left + 8, scanY);
    final Offset right = Offset(rect.right - 8, scanY);
    canvas.drawLine(
      left,
      right,
      Paint()
        ..strokeWidth = 7
        ..color = AppColors.mint.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawLine(
      left,
      right,
      Paint()
        ..strokeWidth = 1.6
        ..color = AppColors.mint.withValues(alpha: 0.9),
    );

    // Faint dashed face oval, echoing the camera guide.
    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.12);
    for (final ui.PathMetric metric in oval.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = math.min(distance + 6, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), outline);
        distance = next + 8;
      }
    }
  }

  Offset _map(Offset unit, Rect rect) => Offset(
    rect.left + unit.dx * rect.width,
    rect.top + unit.dy * rect.height,
  );

  @override
  bool shouldRepaint(ScanningPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.meshOpacity != meshOpacity;
}
