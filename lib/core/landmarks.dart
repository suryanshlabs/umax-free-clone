/// Indices into the 468-point MediaPipe Face Mesh.
///
/// MediaPipe numbers the mesh once, in a fixed topological order, and every
/// client (Android, iOS, Python, JavaScript) receives the same numbering, so
/// these constants are stable across platform SDK versions.
///
/// Reference: the canonical face model (canonical_face_model.obj) that ships
/// with MediaPipe. Index 0 is the right-hand edge of the face oval near the ear;
/// the numbering then walks the contours in order.
abstract final class FaceLandmarks {
  /// Number of landmarks in a complete MediaPipe Face Mesh.
  static const int requiredCount = 468;

  /// Nose bridge, directly between the eyes. Used as the midline anchor.
  static const int noseBridge = 1;

  /// Top centre of the forehead, at the hairline.
  static const int foreheadTop = 10;

  /// Glabella: the point between the eyebrows.
  static const int glabella = 9;

  /// Upper nose bridge / radix, just below the glabella.
  ///
  /// This is the landmark the brief calls the "nose base". See
  /// [noseBaseAlternative] for the anatomically lower option.
  static const int noseBase = 2;

  /// Bottom of the nose (subnasale), midway between the two nostril wings
  /// ([noseWingLeft], [noseWingRight]). Available if you prefer to measure the
  /// middle third down to the true base of the nose instead of the radix.
  static const int noseBaseAlternative =
      -1; // resolved from the two wings below

  /// Left nostril wing.
  static const int noseWingLeft = 94;

  /// Right nostril wing.
  static const int noseWingRight = 195;

  /// Bottom of the chin (menton).
  static const int chin = 152;

  /// Outer corner of the subject's left eye (viewer's right in a selfie).
  static const int leftEyeCorner = 33;

  /// Outer corner of the subject's right eye (viewer's left in a selfie).
  static const int rightEyeCorner = 263;

  /// Jaw edge on one side, between the ramus and the chin.
  static const int jawEdgeLeft = 172;

  /// Jaw edge on the mirrored side.
  static const int jawEdgeRight = 397;

  /// Left-most point of the face oval at cheekbone height.
  static const int faceEdgeLeft = 234;

  /// Right-most point of the face oval at cheekbone height.
  static const int faceEdgeRight = 454;
}

/// The ideal share of total face height for each third (1 : 1 : 1).
const double idealThirdFraction = 1 / 3;
