import 'dart:typed_data';

import 'package:facial_analysis/ml/exif_orientation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the smallest legal JPEG that still carries an EXIF orientation tag:
/// SOI, one APP1 segment with a big-endian TIFF header and a single IFD0 entry,
/// then EOI.
Uint8List jpegWithOrientation(int value) {
  final List<int> tiff = <int>[
    0x4D, 0x4D, // big-endian
    0x00, 0x2A, // 42
    0x00, 0x00, 0x00, 0x08, // IFD0 starts at offset 8
    0x00, 0x01, // one entry
    0x01, 0x12, // tag 0x0112 = Orientation
    0x00, 0x03, // type SHORT
    0x00, 0x00, 0x00, 0x01, // count 1
    (value >> 8) & 0xFF, value & 0xFF, 0x00, 0x00, // value, left-aligned
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  final int app1Length = 2 + 6 + tiff.length;
  return Uint8List.fromList(<int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, (app1Length >> 8) & 0xFF, app1Length & 0xFF, // APP1
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    ...tiff,
    0xFF, 0xD9, // EOI
  ]);
}

void main() {
  group('readExifOrientation', () {
    test('reads a quarter-turn tag', () {
      final ExifOrientation orientation = readExifOrientation(
        jpegWithOrientation(6),
      );
      expect(orientation, ExifOrientation.rotate90);
      expect(orientation.value, 6);
      expect(orientation.swapsAxes, isTrue);
      expect(orientation.mirrors, isFalse);
    });

    test('reads the upright tag', () {
      expect(
        readExifOrientation(jpegWithOrientation(1)),
        ExifOrientation.normal,
      );
    });

    test('reads a mirrored quarter turn', () {
      final ExifOrientation orientation = readExifOrientation(
        jpegWithOrientation(7),
      );
      expect(orientation, ExifOrientation.transverse);
      expect(orientation.swapsAxes, isTrue);
      expect(orientation.mirrors, isTrue);
    });

    test('ignores an out-of-range value', () {
      expect(
        readExifOrientation(jpegWithOrientation(9)),
        ExifOrientation.unknown,
      );
    });

    test('returns unknown for data that is not a JPEG', () {
      expect(
        readExifOrientation(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6])),
        ExifOrientation.unknown,
      );
      expect(readExifOrientation(Uint8List(0)), ExifOrientation.unknown);
    });

    test('returns unknown for a truncated segment instead of throwing', () {
      final Uint8List complete = jpegWithOrientation(6);
      final Uint8List truncated = Uint8List.sublistView(
        complete,
        0,
        complete.length - 8,
      );
      expect(readExifOrientation(truncated), ExifOrientation.unknown);
    });
  });

  group('uprightPoint', () {
    test('leaves an upright photo alone', () {
      final ({double x, double y}) point = uprightPoint(
        x: 10,
        y: 20,
        rawWidth: 4000,
        rawHeight: 3000,
        orientation: ExifOrientation.normal,
      );
      expect(point.x, 10);
      expect(point.y, 20);
    });

    test('rotates a sensor-space point 90° clockwise into portrait', () {
      // A 4000x3000 landscape sensor frame displayed as 3000x4000 portrait:
      // the sensor's top-left corner ends up at the portrait top-right.
      final ({double x, double y}) corner = uprightPoint(
        x: 0,
        y: 0,
        rawWidth: 4000,
        rawHeight: 3000,
        orientation: ExifOrientation.rotate90,
      );
      expect(corner.x, 3000);
      expect(corner.y, 0);

      final ({double x, double y}) opposite = uprightPoint(
        x: 4000,
        y: 3000,
        rawWidth: 4000,
        rawHeight: 3000,
        orientation: ExifOrientation.rotate90,
      );
      expect(opposite.x, 0);
      expect(opposite.y, 4000);
    });

    test('mirrors horizontally', () {
      final ({double x, double y}) point = uprightPoint(
        x: 100,
        y: 50,
        rawWidth: 4000,
        rawHeight: 3000,
        orientation: ExifOrientation.flipHorizontal,
      );
      expect(point.x, 3900);
      expect(point.y, 50);
    });
  });

  test('only the quarter-turn orientations swap the axes', () {
    final List<ExifOrientation> swapping = <ExifOrientation>[
      for (final ExifOrientation orientation in ExifOrientation.values)
        if (orientation.swapsAxes) orientation,
    ];
    expect(swapping, <ExifOrientation>[
      ExifOrientation.transpose,
      ExifOrientation.rotate90,
      ExifOrientation.transverse,
      ExifOrientation.rotate270,
    ]);
  });
}
