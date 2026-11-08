import 'package:flutter/material.dart';

import 'theme.dart';

/// One navigation module. [highlight] promotes the primary action to a tinted
/// card so the eye lands there first.
class HomeModuleTile extends StatelessWidget {
  const HomeModuleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.trailing,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final String? trailing;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: highlight
                ? accent.withValues(alpha: 0.13)
                : AppColors.surface,
            border: Border.all(
              color: highlight
                  ? accent.withValues(alpha: 0.5)
                  : AppColors.outline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
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
                          letterSpacing: -0.1,
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
                if (trailing != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      trailing!,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: accent,
                      ),
                    ),
                  )
                else
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

class HomePrivacyFooter extends StatelessWidget {
  const HomePrivacyFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.lock_outline_rounded,
          size: 13,
          color: AppColors.textTertiary,
        ),
        SizedBox(width: 7),
        Flexible(
          child: Text(
            'Nothing leaves this device · no account · no tracking',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.2,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
