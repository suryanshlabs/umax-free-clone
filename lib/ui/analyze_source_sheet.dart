import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_screen.dart';
import 'processing_screen.dart';
import 'theme.dart';

/// Where the photo for a Face Analyze run comes from.
enum AnalyzeSource { camera, gallery }

/// Presents the input choice: the custom camera, or an existing photo.
///
/// Returns null when the sheet is dismissed without a choice, which the caller
/// treats as "do nothing" rather than as an error.
Future<AnalyzeSource?> showAnalyzeSourceSheet(BuildContext context) {
  return showModalBottomSheet<AnalyzeSource>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const _SourceSheet(),
  );
}

/// Runs the chosen path.
///
/// Both branches end on [ProcessingScreen], which rotates the photo upright,
/// crops it to 1080x1080 and hands it to the mesh reader — so a gallery photo
/// and a camera capture are measured by exactly the same pipeline.
Future<void> startFaceAnalyze(
  BuildContext context,
  AnalyzeSource source,
) async {
  if (source == AnalyzeSource.camera) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const CameraScreen(),
      ),
    );
    return;
  }
  await _pickFromGallery(context);
}

Future<void> _pickFromGallery(BuildContext context) async {
  final ImagePicker picker = ImagePicker();
  final XFile? picked;
  try {
    picked = await picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
      maxWidth: 4096,
      maxHeight: 4096,
    );
  } on PlatformException catch (error) {
    if (context.mounted) {
      _tell(context, 'The gallery could not be opened (${error.code}).');
    }
    return;
  } on Exception {
    if (context.mounted) {
      _tell(context, 'A photo could not be read from the gallery.');
    }
    return;
  }

  if (picked == null) {
    // The user backed out of the picker. Silence is the correct response.
    return;
  }
  if (!context.mounted) {
    return;
  }

  final String path = picked.path;
  if (!File(path).existsSync()) {
    _tell(context, 'That photo could not be opened. Try another one.');
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => ProcessingScreen(imagePath: path),
    ),
  );
}

void _tell(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Face Analyze',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'One photo produces three measurements. It is rotated upright, '
              'cropped to 1080 x 1080 and measured on this phone.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 20),
            _SheetAction(
              icon: Icons.photo_camera_rounded,
              title: 'Take a Photo',
              subtitle: 'Custom camera with the face-silhouette guide',
              accent: AppColors.accent,
              onTap: () => Navigator.of(context).pop(AnalyzeSource.camera),
            ),
            const SizedBox(height: 10),
            _SheetAction(
              icon: Icons.photo_library_rounded,
              title: 'Upload from Gallery',
              subtitle: 'Use an existing photo from this device',
              accent: AppColors.mint,
              onTap: () => Navigator.of(context).pop(AnalyzeSource.gallery),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppColors.surfaceHigh,
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: accent.withValues(alpha: 0.16),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
