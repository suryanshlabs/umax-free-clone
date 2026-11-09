import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/error_logger.dart';
import '../core/facial_analysis_service.dart';
import '../core/landmarks.dart';
import '../core/vector.dart';
import 'exif_orientation.dart';
import 'face_mesh_source.dart';
import 'mediapipe_face_landmarker.dart';
import 'dart:ui' as ui;
import 'mediapipe_types.dart';


/// A [FaceMeshSource] that runs Google MediaPipe Face Landmarker on prepared
/// photos and converts the 478 normalised landmarks into the app's uniform
/// coordinate space.
///
/// Why a new source rather than reuse of [FaceMeshReader]:
/// [FaceMeshReader] was written for ML Kit Face Mesh Detection, which returns
/// 468 pixel-space points and a specific topology. MediaPipe Face Landmarker
/// returns 478 normalised landmarks with a different topology and, optionally,
/// Z estimates and a facial transformation matrix. Forcing the MediaPipe output
/// into the old `Vec2`-only contract would drop Z and map the wrong indices
/// onto the existing measurement code.
///
/// So this source:
/// * reads the prepared 1080x1080 square PNG,
/// * runs MediaPipe Face Landmarker (IMAGE mode) on it,
/// * converts the normalised coordinates into the app's `Vec2` uniform space
///   (fractions of the image height, aspect-corrected so X and Y share a scale)
///   **only for the landmarks that the existing measurement code can safely use**,
/// * also produces a `MediaPipeScanReading` that holds the full MediaPipe output
///   (all 478 landmarks with Z, the transformation matrix when enabled, blendshapes
///   when enabled) for the future MediaPipe-aware geometry module.
///
/// A `FaceMeshReading` is also produced (from the overlapping landmarks this app
/// already knows how to score) so the existing `AnalysisController.analyse()` path
/// can run a MediaPipe scan through the existing pipeline **unchanged** — keeping
/// the existing results screen, history format and scoring engine working for
/// MediaPipe scans too, without pretending the new model is the same as the old one.
///
/// Threading and lifecycle:
/// * one `MediapipeFaceLandmarkerWrapper` is reused for every scan in the session,
/// * detection runs on a background async path and the camera is released before
///   detection starts, so the two heavy camera-adjacent pipelines never race,
/// * `dispose()` releases the native task.
///
/// This wrapper does **not** fall back to ML Kit when MediaPipe cannot initialise
/// or cannot detect a face.
class MediaPipeScanSource implements FaceMeshSource {
  /// The square size the existing preparer produces.
  static const int squareSize = 1080;

  /// Hard ceiling on one detection pass.
  static const Duration detectionTimeout = Duration(seconds: 30);

  MediaPipeScanSource({
    bool enableBlendshapes = true,
    bool enableTransformationMatrix = true,
  }) : _enableBlendshapes = enableBlendshapes,
       _enableTransformationMatrix = enableTransformationMatrix;

  final bool _enableBlendshapes;
  final bool _enableTransformationMatrix;

  late final MediapipeFaceLandmarkerWrapper _wrapper = MediapipeFaceLandmarkerWrapper();
  bool _disposed = false;
  bool _initialised = false;

  @override
  Future<FaceMeshReading?> readFile(
    String path, {
    double? imageAspectRatio,
  }) async {
    if (_disposed) {
      throw const FacialAnalysisException('The MediaPipe scanner was already released.');
    }
    if (!await _ensureInitialised()) {
      throw const FacialAnalysisException(
        'MediaPipe could not start. Check the model and try again.',
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
      throw const FacialAnalysisException('That photo could not be read. Try another one.');
    }

    final ExifOrientation orientation = readExifOrientation(bytes);

    final _ImageGeometry geometry = imageAspectRatio == null
        ? await _geometry(bytes, orientation)
        : _ImageGeometry(aspect: imageAspectRatio, heightPx: null);

    final MediaPipeLandmarkerResult result;
    try {
      result = await _wrapper.detectImage(path).timeout(detectionTimeout);
    } on TimeoutException {
      ErrorLogger.instance.logWarning(
        'MediaPipe detection exceeded ${detectionTimeout.inSeconds}s.',
        source: ErrorLogSource.facemesh,
        context: <String, Object?>{'path': path},
      );
      throw const FacialAnalysisException(detectionTimedOutMessage);
    } on MediapipeException {
      rethrow;
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.facemesh,
        context: <String, Object?>{'path': path},
      );
      throw FacialAnalysisException(
        'MediaPipe detection failed (${error.runtimeType}). Try a new capture.',
      );
    }

    if (result.faceLandmarks.isEmpty) {
      return null;
    }

    // Use the largest face if more than one was detected.
    final MediaPipeFaceLandmarks best = _largestFace(result.faceLandmarks);

    // Convert MediaPipe's normalised landmarks into the app's uniform Vec2 space.
    // MediaPipe normalises to (0,0)..(1,1), so X and Y already share a scale, but
    // X was normalised by image width and Y by image height, which differ for a
    // non-square image. Correct X by the aspect ratio so the symmetry and yaw maths
    // in [FacialAnalysisService] stays valid.
    //
    // The existing measurement code expects 468 indices. MediaPipe returns 478. We map
    // the overlapping indices back into the 0..467 space the existing code uses and
    // leave the extra indices out of [FaceMeshReading.points]. The full 478-point
    // result (with Z) lives in [MediaPipeScanReading.mediaPipeResult].
    final int imageHeight = (geometry.heightPx ?? squareSize.toDouble()).toInt();
    final double aspect = geometry.aspect;
    final double yScale = imageHeight > 0 ? 1.0 / imageHeight : 1.0;
    final double xScale = aspect > 0 ? 1.0 / imageHeight * aspect : 1.0;

      final List<Vec2> points = List<Vec2>.filled(FaceLandmarks.requiredCount, const Vec2(0, 0));
    final Set<int> seen = <int>{};

    final int lmLen = best.length;
    for (int i = 0; i < lmLen; i++) {
      if (i < FaceLandmarks.requiredCount) {
        final NormalizedLandmark n = best[i];
        final double x = n.x * xScale;
        final double y = n.y * yScale;
        points[i] = Vec2(x, y);
        seen.add(i);
      }
    }

    final double faceHeightPx = _verticalSpan(best, imageHeight);
    final double faceWidthPx = _horizontalSpan(best, imageWidth: imageHeight * aspect);

    // Demand the same key points the existing reader demands, so a partial read still
    // fails usefully.
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
    final List<int> missing = needed.where((int index) => !seen.contains(index)).toList();
    if (missing.isNotEmpty) {
      ErrorLogger.instance.logWarning(
        'MediaPipe returned ${seen.length} of ${FaceLandmarks.requiredCount} '
        'key landmarks, missing $missing.',
        source: ErrorLogSource.facemesh,
        context: <String, Object?>{'path': path, 'landmarks': seen.length},
      );
      throw FacialAnalysisException(
        'MediaPipe found ${seen.length} of ${FaceLandmarks.requiredCount} '
        'key landmarks, missing (${missing.join(', ')}). Part of your face '
        'was outside the frame or covered. Keep your face straight on, in '
        'bright light.',
      );
    }

    final double boxWidth = faceWidthPx * xScale;
    final double boxHeight = faceHeightPx * yScale;

    final FaceMeshReading meshReading = FaceMeshReading(
      points: List<Vec2>.unmodifiable(points),
      faceWidthFraction: boxWidth,
      faceHeightFraction: boxHeight,
      faceCount: result.faceLandmarks.length,
      coordinatesWereNormalised: true,
      exifOrientationApplied: orientation != ExifOrientation.unknown,
    );

    // Build the app-owned MediaPipe reading that the MediaPipe geometry module will
    // consume later. We do not run that module here: the existing pipeline consumes
    // [meshReading], and the MediaPipe-only path is a separate future feature that
    // can be added without touching this one.
    final MediaPipeScanReading mpReading = MediaPipeScanReading(
      view: CaptureView.front, // caller will overwrite this; placeholder for the type
      mediaPipeResult: MediaPipeLandmarkerResult(
        imageWidth: result.imageWidth,
        imageHeight: result.imageHeight,
        faceLandmarks: result.faceLandmarks,
        faceBlendshapes: result.faceBlendshapes,
        facialTransformationMatrixes: result.facialTransformationMatrixes,
      ),
      imageAspectRatio: aspect,
      imageHeight: result.imageHeight,
    );

    // Store the attached result for callers that need the MediaPipe-specific data.
    _lastAttachedReading = MediaPipeAttachedReading(
      meshReading: meshReading,
      mediaPipeReading: mpReading,
    );
    return meshReading;
  }

  /// The result from the most recent [readFile] / [readAttached] call, if any.
  MediaPipeAttachedReading? get lastAttachedReading => _lastAttachedReading;
  MediaPipeAttachedReading? _lastAttachedReading;

  /// Like [readFile], but returns the full [MediaPipeAttachedReading] (mesh + MediaPipe data).
  /// Returns `null` if no face was detected.
  Future<MediaPipeAttachedReading?> readAttached(
    String path, {
    double? imageAspectRatio,
  }) async {
    final FaceMeshReading? mesh = await readFile(path, imageAspectRatio: imageAspectRatio);
    if (mesh == null) return null;
    return _lastAttachedReading;
  }

  // ---- helpers ----

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _wrapper.dispose();
  }

  // ---- initialisation ----

  Future<bool> _ensureInitialised() async {
    if (_initialised) {
      return true;
    }
    if (_disposed) {
      return false;
    }
    try {
      await _wrapper.init(
        enableBlendshapes: _enableBlendshapes,
        enableTransformationMatrix: _enableTransformationMatrix,
      );
    } on MediapipeException {
      _initialised = false;
      return false;
    } on Object {
      _initialised = false;
      return false;
    }
    _initialised = true;
    return true;
  }

  // ---- helpers ----

  /// Package both readings into one attached pair.
  @visibleForTesting
  static MediaPipeAttachedReading package(
    FaceMeshReading meshReading,
    MediaPipeScanReading mediaPipeReading,
  ) {
    return MediaPipeAttachedReading(
      meshReading: meshReading,
      mediaPipeReading: mediaPipeReading,
    );
  }


  /// The largest face in the MediaPipe result.
  static MediaPipeFaceLandmarks _largestFace(
    List<MediaPipeFaceLandmarks> faces,
  ) {
    MediaPipeFaceLandmarks best = faces.first;
    double bestSpan = _faceSpan(best);
    for (final MediaPipeFaceLandmarks face in faces.skip(1)) {
      final double span = _faceSpan(face);
      if (span > bestSpan) {
        bestSpan = span;
        best = face;
      }
    }
    return best;
  }

  static double _faceSpan(MediaPipeFaceLandmarks face) {
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    final int len = face.length;
    for (int i = 0; i < len; i++) {
      final NormalizedLandmark lm = face[i];
      if (lm.x < minX) minX = lm.x;
      if (lm.x > maxX) maxX = lm.x;
      if (lm.y < minY) minY = lm.y;
      if (lm.y > maxY) maxY = lm.y;
    }
    return (maxX - minX) + (maxY - minY);
  }

  static double _verticalSpan(MediaPipeFaceLandmarks face, int imageHeight) {
    double minY = double.infinity;
    double maxY = -double.infinity;
    final int len = face.length;
    for (int i = 0; i < len; i++) {
      final double y = face[i].y;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final double span = maxY - minY;
    return span.isFinite && span > 0 ? span * imageHeight : imageHeight.toDouble();
  }

  static double _horizontalSpan(MediaPipeFaceLandmarks face, {required double imageWidth}) {
    double minX = double.infinity;
    double maxX = -double.infinity;
    final int len = face.length;
    for (int i = 0; i < len; i++) {
      final double x = face[i].x;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }
    final double span = maxX - minX;
    return span.isFinite && span > 0 ? span * imageWidth : imageWidth;
  }  static int _imageWidthFor(double aspect, int height) {
    if (!aspect.isFinite || aspect <= 0 || height <= 0) return height;
    final double w = height * aspect;
    return w.isFinite ? w.round() : height;
  }

  /// Image geometry from the prepared file bytes.
  Future<_ImageGeometry> _geometry(Uint8List bytes, ExifOrientation orientation) async {
    double? decodedAspect;
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 96);
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
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
        rawWidth = descriptor.width;
        rawHeight = descriptor.height;
        descriptor.dispose();
      } finally {
        buffer.dispose();
      }
    } on Object {
      rawWidth = null;
      rawHeight = null;
    }

    if (rawWidth != null && rawWidth > 0 && rawHeight != null && rawHeight > 0) {
      return _ImageGeometry(
        aspect: decodedAspect ?? (rawWidth / rawHeight),
        heightPx: rawHeight.toDouble(),
        rawWidth: rawWidth.toDouble(),
        rawHeight: rawHeight.toDouble(),
      );
    }
    return _ImageGeometry(aspect: decodedAspect ?? 1.0, heightPx: null);
  }

  /// Decode bytes into a [ui.Image] for testing/inspection.
  @visibleForTesting
  Future<ui.Image> decodeToImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: squareSize,
      targetHeight: squareSize,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Image geometry from the prepared file bytes.
  @visibleForTesting
  Future<_ImageGeometry> imageGeometry(Uint8List bytes) async {
    final ExifOrientation orientation = readExifOrientation(bytes);
    return _geometry(bytes, orientation);
  }
}

/// The on-device geometry of a prepared image.
class _ImageGeometry {
  const _ImageGeometry({
    required this.aspect,
    required this.heightPx,
    this.rawWidth,
    this.rawHeight,
  });

  final double aspect;
  final double? heightPx;
  final double? rawWidth;
  final double? rawHeight;
}
