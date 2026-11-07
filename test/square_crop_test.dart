import 'dart:math' as math;

import 'package:facial_analysis/ml/exif_orientation.dart';
import 'package:facial_analysis/ml/square_crop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an upright portrait photo is only scaled', () {
    final SquareCrop crop = squareCropFor(
      width: 1080,
      height: 1440,
      targetSize: 1080,
      orientation: ExifOrientation.normal,
    );

    expect(crop.angleRadians, 0);
    expect(crop.isMirrored, isFalse);
    expect(crop.scaleY, closeTo(1, 1e-9));
    expect(crop.drawnWidth, closeTo(1080, 1e-6));
    expect(crop.drawnHeight, closeTo(1440, 1e-6));
  });

  test('a landscape sensor frame becomes portrait', () {
    final SquareCrop crop = squareCropFor(
      width: 4000,
      height: 3000,
      targetSize: 1080,
      orientation: ExifOrientation.rotate90,
    );

    expect(crop.uprightWidth, 3000);
    expect(crop.uprightHeight, 4000);
    expect(crop.angleRadians, closeTo(math.pi / 2, 1e-9));
    expect(crop.scaleY, closeTo(1080 / 3000, 1e-9));
    expect(crop.isRotated, isTrue);
  });

  test('every orientation covers the square in both directions', () {
    for (final ExifOrientation orientation in ExifOrientation.values) {
      final SquareCrop crop = squareCropFor(
        width: 4000,
        height: 3000,
        targetSize: 1080,
        orientation: orientation,
      );
      expect(
        crop.drawnWidth,
        greaterThanOrEqualTo(1080 - 1e-6),
        reason: 'width for $orientation',
      );
      expect(
        crop.drawnHeight,
        greaterThanOrEqualTo(1080 - 1e-6),
        reason: 'height for $orientation',
      );
    }
  });

  test('mirrored orientations get a negative horizontal scale', () {
    for (final ExifOrientation orientation in ExifOrientation.values) {
      final SquareCrop crop = squareCropFor(
        width: 4000,
        height: 3000,
        targetSize: 1080,
        orientation: orientation,
      );
      expect(
        crop.isMirrored,
        orientation.mirrors,
        reason: 'mirror flag for $orientation',
      );
    }
  });

  test('a square source is scaled exactly', () {
    final SquareCrop crop = squareCropFor(
      width: 3024,
      height: 3024,
      targetSize: 1080,
      orientation: ExifOrientation.unknown,
    );

    expect(crop.scaleX, closeTo(1080 / 3024, 1e-9));
    expect(crop.scaleY, closeTo(1080 / 3024, 1e-9));
    expect(crop.drawnWidth, closeTo(1080, 1e-6));
    expect(crop.drawnHeight, closeTo(1080, 1e-6));
  });

  test('impossible dimensions are rejected instead of producing NaN', () {
    expect(
      () => squareCropFor(
        width: 0,
        height: 300,
        targetSize: 1080,
        orientation: ExifOrientation.normal,
      ),
      throwsArgumentError,
    );
    expect(
      () => squareCropFor(
        width: 300,
        height: 300,
        targetSize: 0,
        orientation: ExifOrientation.normal,
      ),
      throwsArgumentError,
    );
  });
}
