import '../core/vector.dart';

/// One face mesh, already converted into the uniform coordinate space the maths
/// expects: x and y share one scale, so distances and angles are meaningful.
class FaceMeshReading {
  const FaceMeshReading({
    required this.points,
    required this.faceWidthFraction,
    required this.faceHeightFraction,
    required this.faceCount,
    required this.coordinatesWereNormalised,
  });

  /// All 468 landmarks, indexed exactly as MediaPipe indexes them.
  final List<Vec2> points;

  /// Bounding-box width of the measured face, as a fraction of image height.
  final double faceWidthFraction;

  /// Bounding-box height of the measured face, as a fraction of image height.
  final double faceHeightFraction;

  /// How many faces were found. The largest one is the one that was measured.
  final int faceCount;

  /// True when the detector returned 0..1 coordinates that had to be
  /// aspect-corrected. Exposed for diagnostics; the maths does not use it.
  final bool coordinatesWereNormalised;

  /// Rough "is the face big enough to measure" gate. Below ~15% of the frame
  /// the landmark spacing gets noisy enough to shift scores by several points.
  bool get isLargeEnough => faceHeightFraction >= 0.15;
}

/// Anything that can produce face landmarks from a photo.
///
/// The camera pipeline depends on this interface rather than the concrete
/// ML Kit reader, which keeps the analysis controller testable without a
/// device or a platform channel.
abstract interface class FaceMeshSource {
  /// Returns `null` when no face was found. Throws
  /// [FacialAnalysisException] for anything the user can act on.
  Future<FaceMeshReading?> readFile(String path, {double? imageAspectRatio});

  /// Releases the detector.
  Future<void> dispose();
}
