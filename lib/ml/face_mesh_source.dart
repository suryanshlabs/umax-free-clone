import '../core/vector.dart';

/// The one message every "we could not get a mesh" path shows the user.
///
/// Detection returning nothing, detection throwing, and the detector hanging
/// past its deadline are three different faults with exactly one piece of useful
/// advice, so the copy lives in one place and cannot drift between them.
const String faceNotDetectedMessage =
    'Face not detected. Keep your face centered in bright light and try again';

/// Shown when the detector itself never answered in time.
///
/// Kept separate from [faceNotDetectedMessage] on purpose: a slow, cold
/// detector is not a missing face, and telling the user to "keep your face in
/// the light" when the real problem is a 30-second deadline misleads them.
/// The analysis controller's deadline is 45 s and the reader's is 30 s, so
/// this only appears for genuinely wedged plugin calls.
const String detectionTimedOutMessage =
    'Analysis timed out. The on-device face detector is still loading on its '
    'first run; give it a few seconds, keep the phone cool, and try again.';

/// One face mesh, already converted into the uniform coordinate space the maths
/// expects: x and y share one scale, so distances and angles are meaningful.
class FaceMeshReading {
  const FaceMeshReading({
    required this.points,
    required this.faceWidthFraction,
    required this.faceHeightFraction,
    required this.faceCount,
    required this.coordinatesWereNormalised,
    this.exifOrientationApplied = false,
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

  /// True when the landmarks had to be rotated out of the sensor's landscape
  /// frame using the EXIF orientation tag. Diagnostics only.
  final bool exifOrientationApplied;

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
