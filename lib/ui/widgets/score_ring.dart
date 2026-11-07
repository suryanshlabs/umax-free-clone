import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated score ring: sweeps to the score on first build, so the number feels
/// measured rather than printed.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    this.size = 132,
    this.caption = 'OF 100',
  });

  final double score;
  final double size;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: score),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double value, Widget? child) {
          return CustomPaint(
            painter: _ScoreRingPainter(
              progress: (value / 100).clamp(0.0, 1.0),
              color: scoreColor(value),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    value.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: size * 0.30,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -1.2,
                      color: AppColors.textPrimary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 10;
    final Rect arcRect = (Offset.zero & size).deflate(stroke / 2);

    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.outline,
    );

    if (progress <= 0) {
      return;
    }

    final double sweep = math.pi * 2 * progress;

    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: <Color>[color.withValues(alpha: 0.45), color],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
