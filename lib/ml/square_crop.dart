import 'dart:math' as math;

import 'exif_orientation.dart';

/// The transform that turns a stored photo into the upright square the analysis
/// pipeline expects.
///
/// Kept as pure arithmetic — no canvas, no image decoding — so the orientation
/// cases can be unit-tested without a camera, a photo, or a rendering context.
/// [SignedScaleX] is negative for the four orientations that include a mirror.
class SquareCrop {
  const SquareCrop({
    required this.angleRadians,
    required this.scaleX,
    required this.scaleY,
    required this.uprightWidth,
    required this.uprightHeight,
    required this.targetSize,
  });

  /// Clockwise rotation applied to the image before it is scaled.
  final double angleRadians;

  /// Negative when the upright picture is mirrored left-to-right.
  final double scaleX;
  final double scaleY;

  /// Dimensions of the picture after the EXIF rotation, in source pixels.
  final double uprightWidth;
  final double uprightHeight;

  /// Side length of the square output, in pixels.
  final double targetSize;

  bool get isMirrored => scaleX < 0;

  bool get isRotated => angleRadians != 0;

  /// Size of the drawn image after scaling. Both must be at least
  /// [targetSize] or the square would show empty corners.
  double get drawnWidth => uprightWidth * scaleY.abs();

  double get drawnHeight => uprightHeight * scaleY.abs();
}

/// Cover-fit transform: rotate per the EXIF tag, scale so the *short* upright
/// side fills the square, and centre it.
///
/// Cover rather than contain is deliberate. A face fills the middle of a
/// portrait frame, so cropping the long edges costs nothing while letterboxing
/// would shrink the face — and smaller faces mean fewer pixels per feature and
/// noisier landmarks.
SquareCrop squareCropFor({
  required double width,
  required double height,
  required int targetSize,
  required ExifOrientation orientation,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError(
      'Image dimensions must be positive, got $width x $height',
    );
  }
  if (targetSize <= 0) {
    throw ArgumentError.value(targetSize, 'targetSize', 'must be positive');
  }

  final double uprightWidth = orientation.swapsAxes ? height : width;
  final double uprightHeight = orientation.swapsAxes ? width : height;
  final double shortSide = uprightWidth < uprightHeight
      ? uprightWidth
      : uprightHeight;
  final double scale = targetSize / shortSide;

  final (double angle, bool mirror) = switch (orientation) {
    // A vertical flip is a 180 degree rotation plus a horizontal mirror, and a
    // transpose is a quarter turn plus a mirror, which is why the angle and the
    // mirror are decided together.
    ExifOrientation.flipHorizontal => (0.0, true),
    ExifOrientation.rotate180 => (math.pi, false),
    ExifOrientation.flipVertical => (math.pi, true),
    ExifOrientation.transpose => (math.pi / 2, true),
    ExifOrientation.rotate90 => (math.pi / 2, false),
    ExifOrientation.transverse => (-math.pi / 2, true),
    ExifOrientation.rotate270 => (-math.pi / 2, false),
    ExifOrientation.normal || ExifOrientation.unknown => (0.0, false),
  };

  return SquareCrop(
    angleRadians: angle,
    scaleX: mirror ? -scale : scale,
    scaleY: scale,
    uprightWidth: uprightWidth,
    uprightHeight: uprightHeight,
    targetSize: targetSize.toDouble(),
  );
}
