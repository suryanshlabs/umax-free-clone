/// Indices into the 468-point MediaPipe Face Mesh.
///
/// MediaPipe numbers the mesh once, in a fixed topological order, and every
/// client (Android, iOS, Python, JavaScript) receives the same numbering, so
/// these constants are stable across platform SDK versions.
///
/// Reference: the canonical face model (`canonical_face_model.obj`) shipped in
/// `mediapipe/modules/face_geometry/data`. The indices below are the ones used
/// by MediaPipe's own iris and face-geometry modules; the comments record what
/// each point is, because a single wrong index silently corrupts every
/// measurement downstream.
///
/// Coordinate note: the mesh is in image space. "Left" and "right" below mean
/// the subject's own sides, which appear mirrored in a front camera selfie.
abstract final class FaceLandmarks {
  /// Number of landmarks in a complete MediaPipe Face Mesh.
  static const int requiredCount = 468;

  // ---- Midline ---------------------------------------------------------

  /// Nasion: the midline dip between the eyebrows, top of the nose bridge.
  /// This is the anchor the midline is built from; it is far more stable than
  /// the nose tip and does not move with a smile.
  static const int nasion = 168;

  /// Upper nose bridge, just below the nasion. Kept for reference; the midline
  /// uses [nasion] because it is the documented anatomical point.
  static const int noseBridge = 1;

  /// Glabella: the midline point between the eyebrows, used as the boundary
  /// between the upper and middle thirds.
  static const int glabella = 9;

  /// Top centre of the forehead, at the hairline.
  static const int foreheadTop = 10;

  /// Bottom of the chin (menton).
  static const int chin = 152;

  // ---- Nose base -------------------------------------------------------

  /// Left nostril wing (alare).
  static const int noseWingLeft = 94;

  /// Right nostril wing (alare).
  static const int noseWingRight = 195;

  // ---- Eyes ------------------------------------------------------------

  /// Outer corner of the subject's left eye.
  static const int leftEyeOuter = 33;

  /// Outer corner of the subject's right eye.
  static const int rightEyeOuter = 263;

  /// Inner corner of the subject's left eye (tear duct area).
  static const int leftEyeInner = 133;

  /// Inner corner of the subject's right eye.
  static const int rightEyeInner = 362;

  // ---- Mouth -----------------------------------------------------------

  /// Left mouth corner.
  static const int mouthLeft = 61;

  /// Right mouth corner.
  static const int mouthRight = 291;

  // ---- Face oval -------------------------------------------------------

  /// Face-oval point level with the cheekbone on the subject's left side.
  static const int faceEdgeLeft = 234;

  /// Face-oval point level with the cheekbone on the subject's right side.
  static const int faceEdgeRight = 454;

  /// Jaw contour point on the subject's left side, between the ramus and chin.
  static const int jawEdgeLeft = 172;

  /// Jaw contour point on the subject's right side, mirrored from [jawEdgeLeft].
  static const int jawEdgeRight = 397;

  /// The mirrored landmark pairs used to measure asymmetry.
  ///
  /// Each pair sits at the same anatomical place on opposite sides of the
  /// midline, so a perfectly symmetrical, level, frontal face puts both points
  /// the same distance from the midline. Pairs are deliberately from four
  /// different regions: a camera or lighting artefact usually affects one
  /// region, while real asymmetry tends to show in several.
  static const List<(int, int)> symmetryPairs = <(int, int)>[
    (leftEyeOuter, rightEyeOuter),
    (leftEyeInner, rightEyeInner),
    (mouthLeft, mouthRight),
    (faceEdgeLeft, faceEdgeRight),
  ];
}

/// The ideal share of total face height for each third (1 : 1 : 1).
const double idealThirdFraction = 1 / 3;
