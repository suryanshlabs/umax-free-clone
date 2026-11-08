import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/profile_report.dart';
import 'processing_screen_multiangle.dart';
import 'theme.dart';

/// Three-angle capture sheet: front, left profile, right profile.
/// Each slot can be filled from the gallery; at least the front photo
/// is needed to run, side photos may be skipped (they then read
/// "No reading" instead of hanging).
class MultiAngleScanSheet extends StatefulWidget {
  const MultiAngleScanSheet({super.key});

  @override
  State<MultiAngleScanSheet> createState() => _MultiAngleScanSheetState();
}

class _MultiAngleScanSheetState extends State<MultiAngleScanSheet> {
  Uint8List? _front;
  Uint8List? _left;
  Uint8List? _right;
  bool _picking = false;

  Future<void> _pick(ValueChanged<Uint8List> onPicked) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      if (mounted) onPicked(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That photo could not be read.')),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _analyse() {
    if (_front == null && _left == null && _right == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one photo to analyse.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ProcessingScreenMultiAngle(
          scan: MultiAngleScan(
            frontImage: _front,
            leftProfileImage: _left,
            rightProfileImage: _right,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-Angle Profile Scan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          const Text(
            'Front, left profile and right profile in one flow. '
            'Pick a photo for each angle from your gallery. Side photos '
            'work best edge-on, nose pointing sideways, at eye level.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          _Slot(
            label: 'Front',
            subtitle: 'Face straight to camera',
            filled: _front != null,
            onPick: () => _pick((Uint8List b) => setState(() => _front = b)),
          ),
          _Slot(
            label: 'Left profile',
            subtitle: 'Left side edge-on',
            filled: _left != null,
            onPick: () => _pick((Uint8List b) => setState(() => _left = b)),
          ),
          _Slot(
            label: 'Right profile',
            subtitle: 'Right side edge-on',
            filled: _right != null,
            onPick: () => _pick((Uint8List b) => setState(() => _right = b)),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _picking ? null : _analyse,
            child: const Text('Analyse profile'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Everything runs on this device. Photos are not uploaded.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.label,
    required this.subtitle,
    required this.filled,
    required this.onPick,
  });

  final String label;
  final String subtitle;
  final bool filled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: filled ? AppColors.mint : AppColors.outline),
      ),
      child: ListTile(
        leading: Icon(
          filled ? Icons.check_circle : Icons.add_a_photo,
          color: filled ? AppColors.mint : AppColors.textTertiary,
        ),
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
        trailing: Text(filled ? 'Picked' : 'Pick',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: filled ? AppColors.mint : AppColors.accentSoft)),
        onTap: onPick,
      ),
    );
  }
}
