import 'package:flutter/material.dart';

import '../data/scan_history.dart';
import 'theme.dart';

class HomeWordmark extends StatelessWidget {
  const HomeWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.accent, AppColors.accentSoft],
            ),
          ),
          child: const Icon(
            Icons.face_retouching_natural_rounded,
            size: 19,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'FACE GEOMETRY',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'On-device facial analysis',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The last result, or an invitation to take the first one.
class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({super.key, required this.latest, required this.onStart});

  final SavedScan? latest;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final SavedScan? scan = latest;
    final Color accent = scan == null
        ? AppColors.accentSoft
        : scoreColor(scan.overallScore);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.surfaceHigh, AppColors.surface],
        ),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                scan == null ? 'GET STARTED' : 'LATEST SCAN',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              if (scan != null)
                Text(
                  scan.shortDate,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (scan == null) ...<Widget>[
            const Text(
              'Measure once, then measure again\nin a month.',
              style: TextStyle(
                fontSize: 19,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'One photo produces three scored measurements — eye symmetry, '
              'jawline angularity and facial thirds — all computed on this '
              'phone from 468 landmarks.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  scan.scoreText,
                  style: TextStyle(
                    fontSize: 54,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                    color: accent,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 2),
                  child: Text(
                    '/100',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    scan.bandLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onStart,
            child: Text(scan == null ? 'Start a scan' : 'Scan again'),
          ),
        ],
      ),
    );
  }
}

class HomeSectionLabel extends StatelessWidget {
  const HomeSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.textTertiary,
      ),
    );
  }
}
