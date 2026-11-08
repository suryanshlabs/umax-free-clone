import 'package:flutter/material.dart';

import '../core/profile_report.dart';
import 'theme.dart';

/// Multi-angle result: per-angle readings, cross-profile angles, warnings.
/// Zero angles honestly read "No reading" — never a fabricated number.
class ResultsScreenMultiAngle extends StatelessWidget {
  const ResultsScreenMultiAngle({super.key, required this.report});

  final ProfileAnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final ProfileReport baseline = report.baseline;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile Scan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          _Card(title: 'Gonial angle (estimate)', value: _deg(report.gonialAngleEstimate)),
          const SizedBox(height: 10),
          _Card(title: 'Nasolabial angle (estimate)', value: _deg(report.crossProfile.nasolabialAngleEstimate)),
          const SizedBox(height: 10),
          _Card(title: 'Left gonial', value: _deg(report.crossProfile.gonialAngleLeft)),
          _Card(title: 'Right gonial', value: _deg(report.crossProfile.gonialAngleRight)),
          const SizedBox(height: 18),
          const Text('PER-ANGLE READINGS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.textTertiary)),
          const SizedBox(height: 10),
          _Card(title: baseline.front.label, value: baseline.front.display),
          _Card(title: baseline.left.label, value: baseline.left.display),
          _Card(title: baseline.right.label, value: baseline.right.display),
          if (report.errors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            for (final String error in report.errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error,
                    style: const TextStyle(fontSize: 12, color: AppColors.amber)),
              ),
          ],
          for (final String warning in report.meta.warnings())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(warning,
                  style: const TextStyle(fontSize: 12, color: AppColors.amber)),
            ),
          const SizedBox(height: 12),
          const Text(
            'Side-photo angles need a clear profile with the face edge-on to the camera. '
            'If a photo was missing or not a true profile, that angle shows "No reading" '
            'instead of a guess.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  String _deg(double v) => v > 0 ? '${v.toStringAsFixed(1)}°' : 'No reading';
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(children: <Widget>[
        Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
    );
  }
}
