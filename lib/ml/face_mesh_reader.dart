import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import '../core/facial_analysis_service.dart';
import '../core/landmarks.dart';
import '../core/vector.dart';
import 'face_mesh_source.dart';

/// Wraps Google's on-device face mesh detector (ML Kit Face Mesh Detection, the
/// production packaging of MediaPipe Face Mesh) and hands the app a clean
/// [FaceMeshReading].
///
/// It does the four things that quietly break a scoring app:
///
/// 1. **Picks the right face.** Group photos happen; the largest detection is
///    the subject.
/// 2. **Fixes the coordinate space.** ML Kit reports landmark x/y as pixels of
///    the input image, so x and y already share a scale — but they are pixels,
///    not fractions, and the maths wants a face-relative unit. Everything is
///    divided by the image height so a 12 MP photo and a 1080p photo of the same
///    face produce the same numbers. Builds that return 0..1 coordinates are
///    detected and aspect-corrected instead.
/// 3. **Fails loudly and usefully.** A missing or partial mesh throws a
///    [FacialAnalysisException] whose text can be shown to the user verbatim.
/// 4. **Stays on the device.** Nothing here touches the network: ML Kit runs the
///    468-point model in the app process and the photo never leaves the phone.
class FaceMeshReader implements FaceMeshSource {
  FaceMeshReader()
    : _detector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

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

    final Uint8List bytes = await file.readAsBytes();
    final _ImageGeometry geometry = imageAspectRatio == null
        ? await _geometry(bytes)
        : _ImageGeometry(aspect: imageAspectRatio, heightPx: null);

    final List<FaceMesh> meshes;
    try {
      meshes = await _detector.processImage(InputImage.fromFilePath(path));
    } on PlatformException catch (error) {
      throw FacialAnalysisException(
        'The face mesh detector could not read the image (${error.code}). '
        'Try a new capture.',
      );
    } on Exception catch (error) {
      throw FacialAnalysisException(
        'Face mesh detection failed: $error. Try a new capture.',
      );
    }

    if (meshes.isEmpty) {
      return null;
    }

    final FaceMesh face = _largest(meshes);
    final bool normalised = _looksNormalised(face.points);

    // Both branches end in the same uniform space: fractions of image height,
    // with x pre-multiplied by the aspect ratio when the SDK normalised both
    // axes to 0..1 (that is the only case where x and y disagree in scale).
    final double heightPx = geometry.heightPx ?? _verticalSpan(face.points);
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
      points[point.index] = Vec2(point.x * xScale, point.y * yScale);
      seen.add(point.index);
    }

    if (seen.length < FaceLandmarks.requiredCount) {
      throw FacialAnalysisException(
        'Only ${seen.length} of ${FaceLandmarks.requiredCount} landmarks came '
        'back. Part of your face was outside the frame or covered.',
      );
    }

    return FaceMeshReading(
      points: List<Vec2>.unmodifiable(points),
      faceWidthFraction: face.boundingBox.width * xScale,
      faceHeightFraction: face.boundingBox.height * yScale,
      faceCount: meshes.length,
      coordinatesWereNormalised: normalised,
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

  /// Aspect ratio and pixel height of the image as it is displayed.
  ///
  /// The 96px decoded thumbnail gives the orientation-correct aspect ratio
  /// (Flutter applies EXIF rotation the same way the UI does), and the encoded
  /// header gives the raw pixel dimensions. Combining the two yields the upright
  /// pixel height, which is the unit ML Kit's pixel coordinates are divided by.
  Future<_ImageGeometry> _geometry(Uint8List bytes) async {
    double? decodedAspect;
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 96,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final double aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (aspect.isFinite && aspect > 0) {
        decodedAspect = aspect;
      }
    } on Exception {
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
    } on Exception {
      rawWidth = null;
      rawHeight = null;
    } finally {
      buffer.dispose();
    }

    final double aspect =
        decodedAspect ??
        (rawWidth != null && rawHeight != null && rawHeight > 0
            ? rawWidth / rawHeight
            : 0.75);

    double? heightPx;
    if (rawWidth != null && rawHeight != null && rawWidth > 0) {
      final int large = math.max(rawWidth, rawHeight);
      final int small = math.min(rawWidth, rawHeight);
      heightPx = (aspect < 1 ? large : small).toDouble();
    }

    return _ImageGeometry(aspect: aspect, heightPx: heightPx);
  }
}

/// Everything the reader needs to know about the image's geometry.
class _ImageGeometry {
  const _ImageGeometry({required this.aspect, required this.heightPx});

  /// Displayed width / height.
  final double aspect;

  /// Displayed height in pixels, when it could be determined.
  final double? heightPx;
}
