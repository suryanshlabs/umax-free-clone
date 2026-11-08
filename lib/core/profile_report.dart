import 'dart:typed_data';

/// Three photos captured for a multi-angle scan. Any side photo may be
/// null; the report then says so instead of hanging.
class MultiAngleScan {
  const MultiAngleScan({
    this.frontImage,
    this.leftProfileImage,
    this.rightProfileImage,
  });

  final Uint8List? frontImage;
  final Uint8List? leftProfileImage;
  final Uint8List? rightProfileImage;

  int get completedAngles =>
      (frontImage != null ? 1 : 0) +
      (leftProfileImage != null ? 1 : 0) +
      (rightProfileImage != null ? 1 : 0);
}

/// One angle's reading. angleDegrees == 0 means no reading.
class ProfileMeasurement {
  const ProfileMeasurement({
    required this.angleDegrees,
    required this.label,
  });

  final double angleDegrees;
  final String label;

  bool get hasReading => angleDegrees > 0;
  String get display => hasReading ? '${angleDegrees.toStringAsFixed(1)}°' : 'No reading';
}

class ProfileReport {
  const ProfileReport({
    required this.front,
    required this.left,
    required this.right,
  });

  final ProfileMeasurement front;
  final ProfileMeasurement left;
  final ProfileMeasurement right;
}

class ProfileCrossProfile {
  const ProfileCrossProfile({
    this.gonialAngleLeft = 0,
    this.gonialAngleRight = 0,
    this.nasolabialAngleEstimate = 0,
    this.noseDeviationEstimate = 0,
    this.jawWidthEstimate = 0,
  });

  final double gonialAngleLeft;
  final double gonialAngleRight;
  final double nasolabialAngleEstimate;
  final double noseDeviationEstimate;
  final double jawWidthEstimate;
}

class ProfileAnalysisMeta {
  const ProfileAnalysisMeta({
    this.frontRotation = 0,
    this.leftRotation = 0,
    this.rightRotation = 0,
    this.capturedVersion = 1,
  });

  final double frontRotation;
  final double leftRotation;
  final double rightRotation;
  final int capturedVersion;

  List<String> warnings() {
    final List<String> out = <String>[];
    if (frontRotation > 10) out.add('Front photo was rotated — retake level for a reliable reading.');
    if (leftRotation > 10) out.add('Left profile was rotated — retake level for a reliable reading.');
    if (rightRotation > 10) out.add('Right profile was rotated — retake level for a reliable reading.');
    return out;
  }
}

/// Combined multi-angle result. Never throws for a missing side photo.
class ProfileAnalysisReport {
  const ProfileAnalysisReport({
    required this.baseline,
    required this.crossProfile,
    required this.gonialAngleEstimate,
    required this.meta,
    this.errors = const <String>[],
  });

  final ProfileReport baseline;
  final ProfileCrossProfile crossProfile;
  final double gonialAngleEstimate;
  final ProfileAnalysisMeta meta;
  final List<String> errors;

  bool get isReliable =>
      meta.frontRotation <= 14 &&
      meta.leftRotation <= 14 &&
      meta.rightRotation <= 14;

  static ProfileAnalysisReport empty() {
    return const ProfileAnalysisReport(
      baseline: ProfileReport(
        front: ProfileMeasurement(angleDegrees: 0, label: 'Front'),
        left: ProfileMeasurement(angleDegrees: 0, label: 'Left profile'),
        right: ProfileMeasurement(angleDegrees: 0, label: 'Right profile'),
      ),
      crossProfile: ProfileCrossProfile(),
      gonialAngleEstimate: 0,
      meta: ProfileAnalysisMeta(),
      errors: <String>[
        'Clearly oriented photos are required on every angle to deliver a profile reading.',
      ],
    );
  }
}
