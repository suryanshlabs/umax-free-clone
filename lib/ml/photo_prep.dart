import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/error_logger.dart';
import 'exif_orientation.dart';
import 'square_crop.dart';

/// A photo that is ready for landmark detection: upright, square, and exactly
/// [PhotoPreparer.targetSize] pixels on each side.
class PreparedPhoto {
  const PreparedPhoto({
    required this.path,
    required this.size,
    required this.byteLength,
    required this.orientation,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final String path;
  final int size;
  final int byteLength;

  /// The EXIF tag that was applied. [ExifOrientation.unknown] means the pixels
  /// were already upright as decoded.
  final ExifOrientation orientation;

  final int sourceWidth;
  final int sourceHeight;
}

/// Raised when a picked or captured photo cannot be opened or re-encoded.
///
/// The message is written to be shown to the user verbatim, like the rest of the
/// app's failures.
class PhotoPreparationException implements Exception {
  const PhotoPreparationException(this.message);

  final String message;

  @override
  String toString() => 'PhotoPreparationException: $message';
}

/// Normalises camera captures and gallery picks into one predictable input:
/// an upright, square, 1080x1080 PNG in the app's temporary directory.
///
/// Two things make this worth doing rather than feeding the raw file straight to
/// ML Kit:
///
/// * **Orientation.** Android stores a landscape sensor frame plus an EXIF tag.
///   ML Kit's handling of that tag has varied between versions, so the picture
///   is rotated here, once, using the tag parsed in
///   [readExifOrientation]. Downstream code then never has to reason about it.
/// * **Size.** A 12 MP capture and a 1 MP gallery pick otherwise produce
///   different pixel densities per feature. Fixing the input at 1080x1080 makes
///   two scans of the same face comparable, which is the whole point of the
///   progress module.
///
/// Everything here is local: the file is written to the app's own temporary
/// directory, which no other app can read, and never uploaded.
class PhotoPreparer {
  const PhotoPreparer({this.targetSize = defaultTargetSize});

  /// The size the pipeline is calibrated for.
  static const int defaultTargetSize = 1080;

  /// Files are named with this prefix so stale ones can be swept up.
  static const String filePrefix = 'analysis_square_';

  /// Side length of the square output.
  final int targetSize;

  /// Prepares the photo at [path].
  Future<PreparedPhoto> preparePath(String path) => prepare(File(path));

  Future<PreparedPhoto> prepare(File source) async {
    if (!source.existsSync()) {
      throw const PhotoPreparationException(
        'That photo is no longer on the device. Try picking it again.',
      );
    }

    final Uint8List raw;
    try {
      raw = await source.readAsBytes();
    } on FileSystemException {
      throw const PhotoPreparationException(
        'That photo could not be read. Try a different image.',
      );
    }

    final ExifOrientation orientation = readExifOrientation(raw);

    ui.Image? image;
    ui.Image? squared;
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(raw);
      final ui.FrameInfo frame = await codec.getNextFrame();
      image = frame.image;

      final SquareCrop crop = squareCropFor(
        width: image.width.toDouble(),
        height: image.height.toDouble(),
        targetSize: targetSize,
        orientation: orientation,
      );

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, targetSize.toDouble(), targetSize.toDouble()),
      );
      final double half = targetSize / 2;
      canvas.translate(half, half);
      canvas.rotate(crop.angleRadians);
      canvas.scale(crop.scaleX, crop.scaleY);
      canvas.drawImage(
        image,
        ui.Offset(-image.width / 2, -image.height / 2),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );

      final ui.Picture picture = recorder.endRecording();
      try {
        squared = await picture.toImage(targetSize, targetSize);
      } finally {
        picture.dispose();
      }

      final ByteData? encoded = await squared.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (encoded == null) {
        throw const PhotoPreparationException(
          'That photo could not be re-encoded for analysis.',
        );
      }

      final Directory directory = await getTemporaryDirectory();
      await _sweep(directory);
      final File output = File(
        '${directory.path}/$filePrefix'
        '${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await output.writeAsBytes(encoded.buffer.asUint8List(), flush: true);

      return PreparedPhoto(
        path: output.path,
        size: targetSize,
        byteLength: encoded.lengthInBytes,
        orientation: orientation,
        sourceWidth: image.width,
        sourceHeight: image.height,
      );
    } on PhotoPreparationException {
      rethrow;
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.analysis,
      );
      debugPrint('Photo preparation failed: $error');
      throw const PhotoPreparationException(
        'That image could not be opened. Pick a JPEG or PNG photo and try '
        'again.',
      );
    } finally {
      squared?.dispose();
      image?.dispose();
    }
  }

  /// Deletes squares left behind by earlier runs. Bounded work: only this
  /// app's own temporary directory, only this app's own prefix.
  Future<void> _sweep(Directory directory) async {
    try {
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is File && entity.path.contains(filePrefix)) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // A failed clean-up is cosmetic; the write below still works.
    }
  }
}
