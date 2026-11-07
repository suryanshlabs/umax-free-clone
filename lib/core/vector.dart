import 'dart:math' as math;

/// A point in a single, uniform coordinate space.
///
/// "Uniform" matters: every measurement in this app is a Euclidean distance or
/// an angle, and both are only meaningful if the x and y axes share the same
/// scale. [FaceMeshReader] guarantees that by converting MediaPipe's output into
/// fractions of the image height before the maths ever sees it.
class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  bool get isFinite => x.isFinite && y.isFinite;

  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);

  /// Euclidean length of the vector.
  double get magnitude => math.sqrt(x * x + y * y);

  double distanceTo(Vec2 other) => (this - other).magnitude;

  double dot(Vec2 other) => x * other.x + y * other.y;

  /// The angle between this vector and [other], in degrees, in `[0, 180]`.
  ///
  /// Returns 0 for degenerate (zero-length) vectors instead of throwing, so a
  /// collapsed mesh degrades gracefully rather than crashing the pipeline.
  double angleTo(Vec2 other) {
    final double denominator = magnitude * other.magnitude;
    if (denominator == 0 || !denominator.isFinite) {
      return 0;
    }
    final double cosine = (dot(other) / denominator).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
