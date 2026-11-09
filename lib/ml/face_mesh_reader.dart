import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import '../core/error_logger.dart';
import '../core/facial_analysis_service.dart';
import '../core/landmarks.dart';
import '../core/vector.dart';
import 'exif_orientation.dart';
import 'face_mesh_source.dart';

/// Wraps Google's on-device face mesh detector (ML Kit Face Mesh Detection, the
/// production packaging of MediaPipe Face Mesh) and hands the app a clean
/// [FaceMeshReading].
///
/// It does the five things that quietly break a scoring app:
///
/// 1. **Picks the right face.** Group photos happen; the largest detection is
///    the subject.
/// 2. **Fixes the coordinate space.** ML Kit reports landmark x/y as pixels of
///    the input image, so x and y already share a scale — but they are pixels,
///    not fractions, and the maths wants a face-relative unit. Everything is
///    divided by the image height so a 12 MP photo and a 1080p photo of the same
///    face produce the same numbers. Builds that return 0..1 coordinates are
///    detected and aspect-corrected instead.
/// 3. **Honours the EXIF orientation.** Android cameras store the sensor's
///    landscape frame plus an orientation tag. The tag decides which side is the
///    upright height — the unit every measurement is divided by — and, if the
///    detector hands back sensor-space points, it also rotates them upright.
/// 4. **Fails loudly and usefully.** A missing or partial mesh throws a
///    [FacialAnalysisException] whose text can be shown to the user verbatim,
///    and a detector that never answers is abandoned after
///    [detectionTimeout] instead of hanging the scanning animation forever.
/// 5. **Stays on the device.** Nothing here touches the network: ML Kit runs the
///    468-point model in the app process and the photo never leaves the phone.
class FaceMeshReader implements FaceMeshSource {
  FaceMeshReader()
    : _detector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

  /// Hard ceiling on one detection pass.
  ///
  /// A warm detector returns in 150-600 ms. A cold one, though — first run
  /// after install or after the system reclaimed the process, on a mid-range
  /// phone with a busy CPU — can take well over eight seconds just to load the
  /// model into memory. The previous 8 s deadline turned those cold starts
  /// into a false "Face not detected" (NO READING) even though the face was
  /// right there. Thirty seconds is long enough for the model to load on
  /// almost anything, and short enough that a genuinely wedged plugin call
  /// still gives up.
  static const Duration detectionTimeout = Duration(seconds: 30);

  final FaceMeshDetector _detector;
  bool _disposed = false;

  @override
  Future<FaceMeshReading?> readFile(
    String path, {
    double? imageAspectRatio,
  }) async {
    if (_disposed) {
      throw const FacialAnalysisException(
        'The face detector was already released.',
      );
    }

    final File file = File(path);
    if (!file.existsSync()) {
      throw const FacialAnalysisException(
        'That photo is no longer on the device. Capture a new one.',
      );
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      throw const FacialAnalysisException(
        'That photo could not be read from storage. Capture a new one.',
      );
    }
    final ExifOrientation orientation = readExifOrientation(bytes);
    final _ImageGeometry geometry = imageAspectRatio == null
        ? await _geometry(bytes, orientation)
        : _ImageGeometry(aspect: imageAspectRatio, heightPx: null);

    final List<FaceMesh> meshes;
    try {
      meshes = await _detector
          .processImage(InputImage.fromFilePath(path))
          .timeout(detectionTimeout);
    } on TimeoutException {
      ErrorLogger.instance.logWarning(
        'Face mesh detection exceeded ${detectionTimeout.inSeconds}s.',
        source: ErrorLogSource.facemesh,
      );
      throw const FacialAnalysisException(detectionTimedOutMessage);
    } on PlatformException catch (error) {
      // Native-side failures arrive with their detail in `error.message`;
      // dropping it (code only) is what turned a clear detector fault into a
      // generic "no reading".
      final String detail = error.message ?? error.code;
      debugPrint('Face mesh detector error (${error.code}): $detail');
      throw FacialAnalysisException(
        'The face mesh detector could not read the image: $detail. '
        'Try a new capture in good light.',
      );
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.facemesh,
      );
      debugPrint('Face mesh detection failed: $error');
      throw FacialAnalysisException(
        'Face mesh detection failed (${error.runtimeType}). '
        'Try a new capture in good light.',
      );
    }

    if (meshes.isEmpty) {
      return null;
    }

    final FaceMesh face = _largest(meshes);
    final bool normalised = _looksNormalised(face.points);
    final bool needsRotation =
        !normalised && _meshLooksSideways(face, geometry, orientation);

    // Both branches end in the same uniform space: fractions of the upright
    // image height, with x pre-multiplied by the aspect ratio when the SDK
    // normalised both axes to 0..1 (the only case where x and y disagree).
    final double rawHeightPx = geometry.heightPx ?? _verticalSpan(face.points);
    final double heightPx = rawHeightPx.isFinite && rawHeightPx > 0
        ? rawHeightPx
        : 1.0;
    final double yScale = normalised ? 1.0 : 1.0 / heightPx;
    final double xScale = normalised ? geometry.aspect : 1.0 / heightPx;

    final List<Vec2> points = List<Vec2>.filled(
      FaceLandmarks.requiredCount,
      const Vec2(0, 0),
    );
    final Set<int> seen = <int>{};
    for (final FaceMeshPoint point in face.points) {
      if (point.index < 0 || point.index >= FaceLandmarks.requiredCount) {
        continue;
      }
      final Vec2 source = needsRotation
          ? _toUpright(point.x, point.y, geometry, orientation)
          : Vec2(point.x, point.y);
      points[point.index] = Vec2(source.x * xScale, source.y * yScale);
      seen.add(point.index);
    }

    // Only the landmarks the measurements actually read are required. ML Kit
    // can return the full 468-point list with a duplicate index replacing a
    // non-critical point; demanding every single index turned those scans
    // into a false "no reading" even though the face was fully measured.
    const Set<int> needed = <int>{
      FaceLandmarks.nasion,
      FaceLandmarks.noseBridge,
      FaceLandmarks.leftEyeOuter,
      FaceLandmarks.rightEyeOuter,
      FaceLandmarks.leftEyeInner,
      FaceLandmarks.rightEyeInner,
      FaceLandmarks.mouthLeft,
      FaceLandmarks.mouthRight,
      FaceLandmarks.chin,
      FaceLandmarks.jawEdgeLeft,
      FaceLandmarks.jawEdgeRight,
      FaceLandmarks.foreheadTop,
      FaceLandmarks.glabella,
      FaceLandmarks.noseWingLeft,
      FaceLandmarks.noseWingRight,
      FaceLandmarks.faceEdgeLeft,
      FaceLandmarks.faceEdgeRight,
    };
    final List<int> missing = needed
        .where((int index) => !seen.contains(index))
        .toList();
    if (missing.isNotEmpty) {
      ErrorLogger.instance.logWarning(
        'Incomplete face mesh: ${seen.length} of '
        '${FaceLandmarks.requiredCount} landmarks, missing $missing.',
        source: ErrorLogSource.facemesh,
        context: <String, Object?>{'landmarks': seen.length},
      );
      throw FacialAnalysisException(
        'Only ${seen.length} of ${FaceLandmarks.requiredCount} landmarks came '
        'back, missing key points (${missing.join(', ')}). Part of your face '
        'was outside the frame or covered. Keep your face straight on, in '
        'bright light, with nothing covering it.',
      );
    }
    if (seen.length < FaceLandmarks.requiredCount) {
      debugPrint(
        'Face mesh returned ${seen.length} of '
        '${FaceLandmarks.requiredCount} landmarks; all key points present.',
      );
    }

    // A quarter turn swaps the bounding box sides, which matters because the
    // "is the face large enough" gate is a height fraction.
    final double boxWidth = needsRotation
        ? face.boundingBox.height
        : face.boundingBox.width;
    final double boxHeight = needsRotation
        ? face.boundingBox.width
        : face.boundingBox.height;

    return FaceMeshReading(
      points: List<Vec2>.unmodifiable(points),
      faceWidthFraction: boxWidth * xScale,
      faceHeightFraction: boxHeight * yScale,
      faceCount: meshes.length,
      coordinatesWereNormalised: normalised,
      exifOrientationApplied: needsRotation,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _detector.close();
  }

  Vec2 _toUpright(
    double x,
    double y,
    _ImageGeometry geometry,
    ExifOrientation orientation,
  ) {
    final double rawWidth = geometry.rawWidth!;
    final double rawHeight = geometry.rawHeight!;
    final ({double x, double y}) mapped = uprightPoint(
      x: x,
      y: y,
      rawWidth: rawWidth,
      rawHeight: rawHeight,
      orientation: orientation,
    );
    return Vec2(mapped.x, mapped.y);
  }

  /// True only when the mesh is demonstrably in the sensor's landscape frame.
  ///
  /// ML Kit is documented to read the EXIF tag and return points in the upright
  /// frame, and on every device tested so far it does — so rotating
  /// unconditionally would break the common case. The tell for the uncommon case
  /// is geometric: the photo is displayed portrait, needs a quarter turn, and
  /// the returned bounding box is clearly wider than it is tall. Anything
  /// ambiguous stays untouched.
  bool _meshLooksSideways(
    FaceMesh face,
    _ImageGeometry geometry,
    ExifOrientation orientation,
  ) {
    if (!needsQuarterTurn(orientation)) {
      return false;
    }
    if (geometry.rawWidth == null || geometry.rawHeight == null) {
      return false;
    }
    if (geometry.aspect >= 1.0) {
      return false;
    }
    final double width = face.boundingBox.width;
    final double height = face.boundingBox.height;
    if (width <= 0 || height <= 0) {
      return false;
    }
    return width / height > 1.25;
  }

  FaceMesh _largest(List<FaceMesh> meshes) {
    FaceMesh largest = meshes.first;
    for (final FaceMesh mesh in meshes.skip(1)) {
      final double area = mesh.boundingBox.width * mesh.boundingBox.height;
      final double bestArea =
          largest.boundingBox.width * largest.boundingBox.height;
      if (area > bestArea) {
        largest = mesh;
      }
    }
    return largest;
  }

  /// True when every coordinate sits inside roughly 0..1, which means the SDK
  /// normalised by image dimensions instead of reporting pixels.
  bool _looksNormalised(List<FaceMeshPoint> points) {
    if (points.isEmpty) {
      return false;
    }
    double maxCoordinate = 0;
    for (final FaceMeshPoint point in points) {
      final double magnitude = point.x.abs() > point.y.abs()
          ? point.x.abs()
          : point.y.abs();
      if (magnitude > maxCoordinate) {
        maxCoordinate = magnitude;
      }
    }
    return maxCoordinate <= 1.5;
  }

  /// Vertical extent of the mesh itself. Only used as a unit when the image
  /// dimensions cannot be read; it keeps the maths isotropic even then.
  double _verticalSpan(List<FaceMeshPoint> points) {
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final FaceMeshPoint point in points) {
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    final double span = maxY - minY;
    return span.isFinite && span > 0 ? span : 1.0;
  }

  /// Aspect ratio and pixel height of the image as the user sees it.
  ///
  /// The 96px decoded thumbnail gives the orientation-correct aspect ratio
  /// (Flutter applies EXIF rotation the same way the UI does), and the encoded
  /// header gives the raw, un-rotated pixel dimensions. Combining the two with
  /// the orientation tag yields the upright pixel height, which is the unit
  /// ML Kit's pixel coordinates are divided by.
  Future<_ImageGeometry> _geometry(
    Uint8List bytes,
    ExifOrientation orientation,
  ) async {
    double? decodedAspect;
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 96,
      );
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        final double aspect = frame.image.width / frame.image.height;
        frame.image.dispose();
        if (aspect.isFinite && aspect > 0) {
          decodedAspect = aspect;
        }
      } finally {
        codec.dispose();
      }
    } on Object {
      decodedAspect = null;
    }

    int? rawWidth;
    int? rawHeight;
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    try {
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      rawWidth = descriptor.width;
      rawHeight = descriptor.height;
      descriptor.dispose();
    } on Object {
      // Any failure here (including Errors) just means "unknown dimensions";
      // the aspect fallback below keeps the maths isotropic either way.
      rawWidth = null;
      rawHeight = null;
    } finally {
      buffer.dispose();
    }

    if (rawWidth != null &&
        rawWidth > 0 &&
        rawHeight != null &&
        rawHeight > 0) {
      // The tag says whether the stored frame needs a quarter turn; the decoder
      // says which way round the result is. They can disagree on files edited by
      // other apps, so the decoder wins when both are available.
      bool swapped = orientation.swapsAxes;
      if (decodedAspect != null && decodedAspect > 0) {
        swapped = (rawWidth > rawHeight) != (decodedAspect > 1);
      }
      final double uprightWidth = (swapped ? rawHeight : rawWidth).toDouble();
      final double uprightHeight = (swapped ? rawWidth : rawHeight).toDouble();
      return _ImageGeometry(
        aspect: decodedAspect ?? uprightWidth / uprightHeight,
        heightPx: uprightHeight,
        rawWidth: rawWidth.toDouble(),
        rawHeight: rawHeight.toDouble(),
      );
    }

    return _ImageGeometry(aspect: decodedAspect ?? 0.75, heightPx: null);
  }
}

/// Everything the reader needs to know about the image's geometry.
class _ImageGeometry {
  const _ImageGeometry({
    required this.aspect,
    required this.heightPx,
    this.rawWidth,
    this.rawHeight,
  });

  /// Displayed width / height, after the EXIF rotation is applied.
  final double aspect;

  /// Displayed height in pixels, when it could be determined.
  final double? heightPx;

  /// Encoded width in pixels, before any rotation.
  final double? rawWidth;

  /// Encoded height in pixels, before any rotation.
  final double? rawHeight;
}
