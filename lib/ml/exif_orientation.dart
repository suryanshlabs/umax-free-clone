import 'dart:typed_data';

/// The eight EXIF orientation values, by their meaning rather than their
/// number, because "6" tells a reader nothing.
///
/// Values 5-8 describe an image that is stored rotated by a quarter turn, which
/// is exactly what Android cameras produce when the sensor is mounted sideways.
enum ExifOrientation {
  unknown(0),
  normal(1),
  flipHorizontal(2),
  rotate180(3),
  flipVertical(4),
  transpose(5),
  rotate90(6),
  transverse(7),
  rotate270(8);

  const ExifOrientation(this.value);

  /// The raw tag value, 1-8, or 0 when nothing could be read.
  final int value;

  /// True when the stored image needs a quarter turn, i.e. width and height
  /// swap to reach the upright picture the user actually took.
  bool get swapsAxes =>
      this == ExifOrientation.transpose ||
      this == ExifOrientation.rotate90 ||
      this == ExifOrientation.transverse ||
      this == ExifOrientation.rotate270;

  /// True when the upright picture involves a mirror as well as a rotation.
  bool get mirrors =>
      this == ExifOrientation.flipHorizontal ||
      this == ExifOrientation.flipVertical ||
      this == ExifOrientation.transpose ||
      this == ExifOrientation.transverse;

  static ExifOrientation fromValue(int value) {
    for (final ExifOrientation orientation in ExifOrientation.values) {
      if (orientation.value == value) {
        return orientation;
      }
    }
    return ExifOrientation.unknown;
  }
}

/// Reads the EXIF Orientation tag (0x0112) out of a JPEG byte stream.
///
/// Only the bytes that matter are parsed — the SOI marker, then the APP1
/// segment carrying `Exif\0\0`, then IFD0 — so a 12 MP photo costs a few
/// hundred comparisons and no decoding. Anything unexpected returns
/// [ExifOrientation.unknown], which callers treat as "1": use the pixels as
/// they are. A wrong guess here would silently tilt every measurement, so the
/// parser is deliberately conservative.
ExifOrientation readExifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return ExifOrientation.unknown;
  }

  int offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      return ExifOrientation.unknown;
    }
    final int marker = bytes[offset + 1];
    // Padding bytes and standalone markers carry no length field.
    if (marker == 0xFF) {
      offset += 1;
      continue;
    }
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    // Start of scan: image data begins, no more metadata segments.
    if (marker == 0xDA) {
      return ExifOrientation.unknown;
    }
    final int segmentLength = _readUint16(bytes, offset + 2, false);
    if (segmentLength < 2) {
      return ExifOrientation.unknown;
    }
    final int segmentStart = offset + 4;
    final int segmentEnd = offset + 2 + segmentLength;
    if (segmentEnd > bytes.length) {
      return ExifOrientation.unknown;
    }
    if (marker == 0xE1 && segmentEnd - segmentStart > 6) {
      final bool hasExifHeader =
          bytes[segmentStart] == 0x45 && // E
          bytes[segmentStart + 1] == 0x78 && // x
          bytes[segmentStart + 2] == 0x69 && // i
          bytes[segmentStart + 3] == 0x66 && // f
          bytes[segmentStart + 4] == 0x00 &&
          bytes[segmentStart + 5] == 0x00;
      if (hasExifHeader) {
        final ExifOrientation orientation = _readOrientationFromTiff(
          bytes,
          segmentStart + 6,
          segmentEnd,
        );
        if (orientation != ExifOrientation.unknown) {
          return orientation;
        }
      }
    }
    offset = segmentEnd;
  }
  return ExifOrientation.unknown;
}

/// Walks the TIFF header and IFD0 looking for tag 0x0112.
ExifOrientation _readOrientationFromTiff(Uint8List bytes, int start, int end) {
  if (start + 8 > end) {
    return ExifOrientation.unknown;
  }
  final bool littleEndian;
  if (bytes[start] == 0x49 && bytes[start + 1] == 0x49) {
    littleEndian = true;
  } else if (bytes[start] == 0x4D && bytes[start + 1] == 0x4D) {
    littleEndian = false;
  } else {
    return ExifOrientation.unknown;
  }

  final int ifdOffset = _readUint32(bytes, start + 4, littleEndian);
  final int ifdStart = start + ifdOffset;
  if (ifdStart + 2 > end) {
    return ExifOrientation.unknown;
  }

  final int entryCount = _readUint16(bytes, ifdStart, littleEndian);
  for (int index = 0; index < entryCount; index += 1) {
    final int entry = ifdStart + 2 + index * 12;
    if (entry + 12 > end) {
      return ExifOrientation.unknown;
    }
    final int tag = _readUint16(bytes, entry, littleEndian);
    if (tag != 0x0112) {
      continue;
    }
    // The value is a single SHORT, left-aligned inside the 4-byte field.
    final int value = _readUint16(bytes, entry + 8, littleEndian);
    return ExifOrientation.fromValue(value);
  }
  return ExifOrientation.unknown;
}

/// Maps a point from the sensor's unrotated pixel grid into the upright pixel
/// grid the photo is displayed in.
///
/// The eight cases are the standard EXIF transforms: four rotations and four
/// mirrors. Keeping this as a pure function means the orientation maths is
/// testable without a camera.
({double x, double y}) uprightPoint({
  required double x,
  required double y,
  required double rawWidth,
  required double rawHeight,
  required ExifOrientation orientation,
}) {
  return switch (orientation) {
    ExifOrientation.flipHorizontal => (x: rawWidth - x, y: y),
    ExifOrientation.rotate180 => (x: rawWidth - x, y: rawHeight - y),
    ExifOrientation.flipVertical => (x: x, y: rawHeight - y),
    ExifOrientation.transpose => (x: y, y: x),
    ExifOrientation.rotate90 => (x: rawHeight - y, y: x),
    ExifOrientation.transverse => (x: rawHeight - y, y: rawWidth - x),
    ExifOrientation.rotate270 => (x: y, y: rawWidth - x),
    ExifOrientation.normal || ExifOrientation.unknown => (x: x, y: y),
  };
}

/// True when [orientation] means the stored pixels need a quarter turn before
/// they match what the user saw in the viewfinder.
bool needsQuarterTurn(ExifOrientation orientation) => orientation.swapsAxes;

int _readUint16(Uint8List bytes, int offset, bool littleEndian) => littleEndian
    ? bytes[offset] | (bytes[offset + 1] << 8)
    : (bytes[offset] << 8) | bytes[offset + 1];

int _readUint32(Uint8List bytes, int offset, bool littleEndian) {
  if (littleEndian) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
