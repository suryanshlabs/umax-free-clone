import 'dart:async';

import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'package:facial_analysis/core/error_logger.dart';

/// Normalized facial landmark coordinate from MediaPipe.
///
/// MediaPipe uses a normalized coordinate system where (0, 0) is the top-left
/// corner and (1, 1) is the bottom-right corner of the image.
class NormalizedLandmark {
  /// X coordinate (0.0 to 1.0).
  final double x;

  /// Y coordinate (0.0 to 1.0).
  final double y;

  /// Z coordinate (depth), optional estimate from the model.
  final double z;

  NormalizedLandmark({required this.x, required this.y, this.z = 0.0});

  /// Create from MediaPipe's NormalizedLandmark.
  factory NormalizedLandmark.fromMediaPipe(dynamic landmark) {
    if (landmark is! Map) {
      return NormalizedLandmark(x: 0.0, y: 0.0);
    }
    final map = landmark as Map;
    final x = map['x'] as num?;
    final y = map['y'] as num?;
    final z = map['z'] as num?;
    return NormalizedLandmark(
      x: x?.toDouble() ?? 0.0,
      y: y?.toDouble() ?? 0.0,
      z: z?.toDouble() ?? 0.0,
    );
  }
}

/// Result of a MediaPipe Face Landmarker inference.
class FaceLandmarkerResult {
  /// List of face landmark groups, one per detected face.
  final List<List<NormalizedLandmark>> faceLandmarks;

  /// List of blendshape/expression results, one per detected face.
  final List<List<dynamic>>? faceBlendshapes;

  /// List of facial transformation matrices, one per detected face.
  final List<List<double>>? facialTransformationMatrixes;

  /// Image width after EXIF orientation correction.
  final int imageWidth;

  /// Image height after EXIF orientation correction.
  final int imageHeight;

  FaceLandmarkerResult({
    required this.faceLandmarks,
    this.faceBlendshapes,
    this.facialTransformationMatrixes,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Convert from the mediapipe_vision FaceLandmarkerResult.
  factory FaceLandmarkerResult.fromVision(
    FaceLandmarkerResult visionResult,
    int imageWidth,
    int imageHeight,
  ) {
    final List<List<NormalizedLandmark>> landmarks = List.generate(
      visionResult.faceLandmarks.length,
      (i) => visionResult.faceLandmarks[i]
          .map((lm) => NormalizedLandmark.fromMediaPipe(lm))
          .toList(),
    );

    final List<List<dynamic>>? blendshapes;
    if (visionResult.faceBlendshapes != null) {
      blendshapes = List.generate(
        visionResult.faceBlendshapes!.length,
        (i) => visionResult.faceBlendshapes![i].map((cat) => cat).toList(),
      );
    } else {
      blendshapes = null;
    }

    final List<List<double>>? transformationMatrixes;
    if (visionResult.facialTransformationMatrixes != null) {
      transformationMatrixes = List.generate(
        visionResult.facialTransformationMatrixes!.length,
        (i) => visionResult.facialTransformationMatrixes![i],
      );
    } else {
      transformationMatrixes = null;
    }

    return FaceLandmarkerResult(
      faceLandmarks: landmarks,
      faceBlendshapes: blendshapes,
      facialTransformationMatrixes: transformationMatrixes,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }
}

/// Wrapper for running the MediaPipe Face Landmarker task.
///
/// This class handles:
/// - Initialization with the bundled face_landmarker.task model.
/// - Running inference and receiving landmark results.
/// - Proper lifecycle management of native resources.
MediapipeFaceLandmarkerWrapper {
  FaceLandmarker? _task;
  bool _disposed = false;

  MediapipeFaceLandmarkerWrapper();

  Future<void> init() async {
    _task = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        model: VisionModels.faceLandmarker,
        minFaceDetectionConfidence: 0.5,
        minFacePresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
        numFaces: 1,
        outputFaceBlendshapes: false,
        outputFacialTransformationMatrixes: false,
        runningMode: RunningMode.image,
      ),
    );
  }

  /// Run face landmarker on a preprocessed VisionImage.
  Future<FaceLandmarkerResult> detectImage(VisionImage image,
      {int rotationDegrees = 0}) async {
    if (_disposed) {
      throw MediapipeException('Face Landmarker has been disposed');
    }

    try {
      final dynamic visionResult = await _task!.detect(image, rotationDegrees: rotationDegrees);
      return FaceLandmarkerResult.fromVision(
        visionResult as FaceLandmarkerResult,
        visionResult.imageWidth,
        visionResult.imageHeight,
      );
    } on Exception catch (e) {
      ErrorLogger.instance.logError(
        e,
        StackTrace.current,
        source: ErrorLogSource.facemesh,
      );
      rethrow;
    }
  }

  /// Dispose of the native task and release resources.
  Future<void> dispose() async {
    if (!_disposed) {
      _disposed = true;
      _task?.dispose();
      _task = null;
    }
  }
}

/// Error type for MediaPipe operations.
class MediapipeException implements Exception {
  @override
  final String message;

  MediapipeException(this.message);

  @override
  String toString() => 'MediapipeException: $message';
}