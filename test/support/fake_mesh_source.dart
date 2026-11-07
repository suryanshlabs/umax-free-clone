import 'package:facial_analysis/core/vector.dart';
import 'package:facial_analysis/ml/face_mesh_source.dart';

import 'synthetic_face.dart';

/// A [FaceMeshSource] that returns a prepared reading, so the controller and the
/// results screen can be exercised without a camera or a platform channel.
class FakeFaceMeshSource implements FaceMeshSource {
  FakeFaceMeshSource({this.reading, this.error});

  final FaceMeshReading? reading;
  final Object? error;

  int readCount = 0;
  bool disposed = false;

  @override
  Future<FaceMeshReading?> readFile(
    String path, {
    double? imageAspectRatio,
  }) async {
    readCount++;
    if (error != null) {
      throw error!;
    }
    return reading;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// A reading built from the synthetic mesh: a plausible face filling a good part
/// of a portrait frame.
FaceMeshReading syntheticReading({List<Vec2>? points}) {
  return FaceMeshReading(
    points: List<Vec2>.unmodifiable(points ?? syntheticFace()),
    faceWidthFraction: 0.42,
    faceHeightFraction: 0.58,
    faceCount: 1,
    coordinatesWereNormalised: true,
  );
}
