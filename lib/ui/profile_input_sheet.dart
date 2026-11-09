import 'package:flutter/material.dart';

import '../core/user_profile.dart';
import 'theme.dart';

/// Optional, skippable gender question shown before Face Analyze.
///
/// Returns the saved [UserProfile], or null when skipped/dismissed. It asks for
/// nothing else: no age, no height, no weight, no BMI. Gender is a display
/// preference here and is never used to compute geometry, measurements or
/// scores, and the app never guesses it from the photo.
Future<UserProfile?> showProfileInputSheet(BuildContext context) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const ProfileInputSheet(),
  );
}

class ProfileInputSheet extends StatefulWidget {
  const ProfileInputSheet({super.key});

  @override
  State<ProfileInputSheet> createState() => _ProfileInputSheetState();
}

class _ProfileInputSheetState extends State<ProfileInputSheet> {
  /// Null until the person taps an option: nothing is preselected.
  Gender? _gender;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 18),
              const Text(
                'Gender (optional)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'You can skip this. It is never used to measure your face or '
                'change a score, and it is never guessed from your photo.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 18),
              for (final Gender option in Gender.values) ...<Widget>[
                _GenderOption(
                  label: option.label,
                  selected: _gender == option,
                  onTap: () => setState(
                    () => _gender = _gender == option ? null : option,
                  ),
                ),
                if (option != Gender.values.last) const SizedBox(height: 8),
              ],
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(UserProfile(gender: _gender)),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Nothing leaves this device.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.outline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
