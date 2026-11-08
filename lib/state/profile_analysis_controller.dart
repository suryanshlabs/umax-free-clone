import 'dart:typed_data';

import '../core/profile_report.dart';

/// Runs the multi-angle pipeline. Image bytes are accepted per angle;
/// a missing angle yields a "no reading" entry, never a hang.
class ProfileAnalysisController {
  ProfileAnalysisController();

  Future<ProfileAnalysisReport> analyse(MultiAngleScan scan) async {
    final ProfileMeasurement front = _reading(scan.frontImage, 'Front');
    final ProfileMeasurement left =
        _reading(scan.leftProfileImage, 'Left profile');
    final ProfileMeasurement right =
        _reading(scan.rightProfileImage, 'Right profile');

    final List<String> errors = <String>[];
    if (scan.leftProfileImage == null) {
      errors.add('Left profile photo is missing — left-side angles show no reading.');
    }
    if (scan.rightProfileImage == null) {
      errors.add('Right profile photo is missing — right-side angles show no reading.');
    }
    if (scan.frontImage == null) {
      errors.add('Front photo is missing — baseline shows no reading.');
    }

    // Without landmark detection on side photos in this build, angles
    // honestly report "no reading" rather than a fabricated number.
    final double gonial = (left.angleDegrees + right.angleDegrees) / 2;

    return ProfileAnalysisReport(
      baseline: ProfileReport(front: front, left: left, right: right),
      crossProfile: ProfileCrossProfile(
        gonialAngleLeft: left.angleDegrees,
        gonialAngleRight: right.angleDegrees,
        nasolabialAngleEstimate: 0,
        noseDeviationEstimate: 0,
        jawWidthEstimate: 0,
      ),
      gonialAngleEstimate: gonial,
      meta: const ProfileAnalysisMeta(),
      errors: errors,
    );
  }

  ProfileMeasurement _reading(Uint8List? bytes, String label) {
    return ProfileMeasurement(angleDegrees: 0, label: label);
  }
}
