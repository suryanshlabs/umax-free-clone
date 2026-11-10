// ---------------------------------------------------------------------------
// Shared types for the MediaPipe Face Scan feature.
// Both [MediaPipeScanSource] (ml/) and [MediaPipeAnalysisService] (core/) and
// the scanning screen (ui/) import these, so they stay in one place.
// ---------------------------------------------------------------------------

import 'package:facial_analysis/ml/face_mesh_source.dart';
import 'package:facial_analysis/ml/mediapipe_face_landmarker.dart';
// Re-export the real MediaPipe value types so callers can use the canonical
// names without re-importing mediapipe_core everywhere.
export 'package:mediapipe_vision/mediapipe_vision.dart'
    show
        NormalizedLandmark,
        Landmark,
        Matrix,
        MediaPipeCategory;

/// View stage in a three-view MediaPipe Face Scan session.
enum CaptureView { front, left34, right34, complete }

/// Per-view scan status.
enum ViewStatus { pending, capturing, analysing, accepted, rejected }

/// The recorded output of one MediaPipe view scan.
///
/// Holds the full MediaPipe result (478 landmarks with Z, optional matrix and
/// blendshapes) so the MediaPipe geometry module can consume it. The existing
/// pipeline also consumes the [FaceMeshReading] that [MediaPipeScanSource] pairs
/// with this.
class MediaPipeScanReading {
  const MediaPipeScanReading({
    required this.view,
    required this.mediaPipeResult,
    required this.imageAspectRatio,
    required this.imageHeight,
  });

  final CaptureView view;
  final MediaPipeLandmarkerResult mediaPipeResult;
  final double imageAspectRatio;
  final int imageHeight;
}

/// A pair of readings from one MediaPipe scan: the existing-path [FaceMeshReading]
/// plus the full MediaPipe result.
class MediaPipeAttachedReading {
  const MediaPipeAttachedReading({
    required this.meshReading,
    required this.mediaPipeReading,
  });

  final FaceMeshReading meshReading;
  final MediaPipeScanReading mediaPipeReading;
}
