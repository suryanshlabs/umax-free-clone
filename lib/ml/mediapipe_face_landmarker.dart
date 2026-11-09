import 'dart:async';

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_vision/src/types/vision_types.dart' show VisionImage;

import 'package:facial_analysis/core/error_logger.dart';

// ---------------------------------------------------------------------------
// Re-export the real MediaPipe value types so callers can use the canonical
// names without re-importing mediapipe_core everywhere.
// ---------------------------------------------------------------------------

export 'package:mediapipe_core/mediapipe_core.dart'
    show
        NormalizedLandmark,
        Landmark,
        Matrix,
        MediaPipeCategory,
        Classifications,
        ConfidenceMask;

// ---------------------------------------------------------------------------
// Thin wrappers that give the app's own data model stable, documented names and
// that convert from the runtime's result types into app-owned forms.
// ---------------------------------------------------------------------------

/// Result of a MediaPipe Face Landmarker inference, app-owned copy.
///
/// This is the stable type the scanning pipeline hands around. It owns its own
/// copies of the landmark lists and the blendshape list so the result is valid
/// after the native task is disposed and so callers never accidentally hold a
/// reference to a runtime object.
class MediaPipeLandmarkerResult {
  const MediaPipeLandmarkerResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.faceLandmarks,
    required this.faceBlendshapes,
    required this.facialTransformationMatrixes,
    this.timestampMilliseconds,
  });

  final int imageWidth;
  final int imageHeight;

  /// 478 normalised landmarks per detected face, in the runtime's face order.
  final List<MediaPipeFaceLandmarks> faceLandmarks;

  /// 52 expression scores per detected face; one empty list per face when the
  /// landmarker was created without blendshapes.
  final List<List<MediaPipeCategory>> faceBlendshapes;

  /// One 4x4 canonical-face-to-detected-face matrix per face, column-major;
  /// empty when the landmarker was created without the matrix output.
  final List<Matrix> facialTransformationMatrixes;

  final int? timestampMilliseconds;

  /// Build from the runtime's [FaceLandmarkerResult], taking ownership copies.
  factory MediaPipeLandmarkerResult.fromRuntime(
    FaceLandmarkerResult runtime, {
    int? timestampMilliseconds,
  }) {
    final List<MediaPipeFaceLandmarks> faces = List.of(
      runtime.faceLandmarks.map((list) => MediaPipeFaceLandmarks._fromList(list)),
    );
    final List<List<MediaPipeCategory>> blendshapes = List.of(
      runtime.faceBlendshapes.map((list) => List.of(list)),
    );
    final List<Matrix> matrices = List.of(runtime.facialTransformationMatrixes);

    return MediaPipeLandmarkerResult(
      imageWidth: runtime.imageWidth,
      imageHeight: runtime.imageHeight,
      faceLandmarks: faces,
      faceBlendshapes: blendshapes,
      facialTransformationMatrixes: matrices,
      timestampMilliseconds: timestampMilliseconds ?? runtime.timestampMilliseconds,
    );
  }
}

/// The MediaPipe landmarks of one detected face, app-owned copy.
class MediaPipeFaceLandmarks {
  MediaPipeFaceLandmarks._fromList(List<NormalizedLandmark> list)
      : _landmarks = List.from(list),
        _landmarks3d = <Landmark>[];

  /// 478 normalised image-space landmarks, in the runtime's landmark order.
  final List<NormalizedLandmark> _landmarks;

  /// World-space landmarks, in meters, when the face had them. Face Landmarker
  /// does not return world landmarks, so this is intentionally empty; it exists
  /// so the same container type can be reused by the holistic path without every
  /// caller branching on the task kind.
  final List<Landmark> _landmarks3d;

  /// Landmark at [index], or the zeroed default when out of range. Indices are
  /// the canonical face topology indices (0..477).
  NormalizedLandmark operator [](int index) {
    if (index < 0 || index >= _landmarks.length) {
      return const NormalizedLandmark(x: 0, y: 0, z: 0);
    }
    return _landmarks[index];
  }

  int get length => _landmarks.length;

  List<NormalizedLandmark> get all => List.unmodifiable(_landmarks);
  List<Landmark> get all3D => List.unmodifiable(_landmarks3d);
}

/// One face blendshape category, app-owned copy.
class MediaPipeBlendshapeCategory {
  const MediaPipeBlendshapeCategory({
    required this.index,
    required this.score,
    this.categoryName,
    this.displayName,
  });

  final int index;
  final double score;
  final String? categoryName;
  final String? displayName;

  factory MediaPipeBlendshapeCategory.fromRuntime(MediaPipeCategory c) {
    return MediaPipeBlendshapeCategory(
      index: c.index,
      score: c.score,
      categoryName: c.categoryName,
      displayName: c.displayName,
    );
  }
}

// ---------------------------------------------------------------------------
// Wrapper that owns one Face Landmarker and runs it on prepared images.
// ---------------------------------------------------------------------------

/// Wrapper for running Google MediaPipe Face Landmarker on still images.
///
/// Owns a single `FaceLandmarker` task for the lifetime of this wrapper, so a
/// sequence of scans reuses the same native model instead of reloading it every
/// frame. The model is bundled at pub-get time by the `mediapipe_vision` package
/// hook; it is never downloaded at runtime.
///
/// **Running mode.** This wrapper uses [RunningMode.image] for still-photo
/// analysis. If you need a live camera stream you must create the task in
/// [RunningMode.liveStream] separately (with its own lifecycle) — this wrapper
/// does not do that, because the app's existing scanning pattern is one
/// high-resolution photo per view.
///
/// **Features.** The facial transformation matrix and the 52 blendshape scores
/// are opt-in, at creation time, through [FaceLandmarkerOptions]. Once created
/// a task's options cannot change, so a wrapper that needs blendshapes and a
/// matrix must be created with those flags on.
///
/// **Errors.** Missing model, a wedged platform call, or an invalid image each
/// produce a readable [MediapipeException] rather than a silent fallback to
/// ML Kit.
class MediapipeFaceLandmarkerWrapper {
  MediaPipeLandmarkerResult? _lastResult;
  FaceLandmarker? _task;
  bool _disposed = false;

  MediapipeFaceLandmarkerWrapper();

  /// Initialise the landmarker from the bundled face_landmarker.task model.
  ///
  /// [enableBlendshapes] and [enableTransformationMatrix] must be chosen before
  /// creation because options are fixed at task creation.
  Future<void> init({
    bool enableBlendshapes = true,
    bool enableTransformationMatrix = true,
  }) async {
    if (_disposed) {
      throw const MediapipeException('Face Landmarker has been disposed');
    }
    if (_task != null) {
      return;
    }

    _task = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        model: VisionModels.faceLandmarker,
        minFaceDetectionConfidence: 0.5,
        minFacePresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
        numFaces: 1,
        outputFaceBlendshapes: enableBlendshapes,
        outputFacialTransformationMatrixes: enableTransformationMatrix,
        runningMode: RunningMode.image,
      ),
    );
  }

  /// Run face landmarker on a prepared image already on disk.
  ///
  /// [path] must point at a JPEG/PNG the app has prepared (upright, square,
  /// 1080x1080 in this app). The wrapper does not do camera capture or EXIF
  /// handling — that lives in [MediaPipeScanSource], which owns the prepare
  /// step and owns this wrapper.
  Future<MediaPipeLandmarkerResult> detectImage(String path) async {
    if (_disposed) {
      throw const MediapipeException('Face Landmarker has been disposed');
    }
    if (_task == null) {
      throw const MediapipeException(
        'Face Landmarker was not initialised. Call init() first.',
      );
    }

    try {
      final VisionImage image = VisionImage.fromFile(path);
      final FaceLandmarkerResult runtime = await _task!.detect(image);

      _lastResult = MediaPipeLandmarkerResult.fromRuntime(runtime);
      return _lastResult!;
    } on RuntimeUnavailableException catch (error) {
      ErrorLogger.instance.logError(
        error,
        StackTrace.current,
        source: ErrorLogSource.facemesh,
      );
      throw MediapipeException('MediaPipe is not available on this device: $error');
    } on TaskException catch (error) {
      ErrorLogger.instance.logError(
        error,
        StackTrace.current,
        source: ErrorLogSource.facemesh,
      );
      throw MediapipeException('MediaPipe detection failed: $error');
    } on MediapipeException {
      rethrow;
    } on Exception catch (error) {
      ErrorLogger.instance.logError(
        error,
        StackTrace.current,
        source: ErrorLogSource.facemesh,
      );
      throw MediapipeException('MediaPipe detection failed: $error');
    }
  }

  /// The last successful inference result, for callers that want the result
  /// again without re-running detection.
  MediaPipeLandmarkerResult? get lastResult => _lastResult;

  /// Release the native task and any queued work.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _task?.dispose();
    } on Object catch (error) {
      ErrorLogger.instance.logWarning(
        'MediaPipe dispose failed (ignored): $error',
        source: ErrorLogSource.facemesh,
      );
    } finally {
      _task = null;
      _lastResult = null;
    }
  }
}

/// Error type for MediaPipe operations.
class MediapipeException implements Exception {
  const MediapipeException(this.message);

  final String message;

  @override
  String toString() => 'MediapipeException: $message';
}
