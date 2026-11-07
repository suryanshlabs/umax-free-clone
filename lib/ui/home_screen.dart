import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/scan_history.dart';
import 'analyze_source_sheet.dart';
import 'compare_screen.dart';
import 'theme.dart';
import 'wiki_screen.dart';

/// The hub. Four modules, one primary action, and the last score kept visible so
/// the app opens with something useful instead of a live camera view.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(context.read<ScanHistory>().load());
  }

  void _push(Widget screen) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));
  }

  /// Every entry point into Face Analyze goes through the same sheet, so the
  /// camera is a deliberate choice rather than the only way in.
  Future<void> _startAnalyze() async {
    final AnalyzeSource? source = await showAnalyzeSourceSheet(context);
    if (!mounted || source == null) {
      return;
    }
    await startFaceAnalyze(context, source);
  }

  @override
  Widget build(BuildContext context) {
    final ScanHistory history = context.watch<ScanHistory>();
    final int count = history.scans.length;
    final SavedScan? latest = count == 0 ? null : history.scans.first;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: <Widget>[
            const _Wordmark(),
            const SizedBox(height: 24),
            _HeroCard(
              latest: latest,
              onStart: () => unawaited(_startAnalyze()),
            ),
            const SizedBox(height: 26),
            const _SectionLabel('MODULES'),
            const SizedBox(height: 12),
            _ModuleTile(
              icon: Icons.center_focus_strong_rounded,
              title: 'Face Analyze',
              subtitle: 'Capture one photo and score your geometry',
              accent: AppColors.accent,
              highlight: true,
              trailing: 'START',
              onTap: () => unawaited(_startAnalyze()),
            ),
            const SizedBox(height: 12),
            _ModuleTile(
              icon: Icons.insights_rounded,
              title: 'Compare My Progress',
              subtitle: count >= 2
                  ? '$count saved scans · earlier against latest'
                  : 'Needs two saved scans',
              accent: AppColors.mint,
              trailing: count >= 2 ? '$count' : null,
              onTap: () =>
                  _push(const CompareScreen(mode: CompareMode.progress)),
            ),
            const SizedBox(height: 12),
            _ModuleTile(
              icon: Icons.sports_kabaddi_rounded,
              title: 'Friend VS Mode',
              subtitle: 'Two faces, head to head, same ruler',
              accent: AppColors.amber,
              onTap: () => _push(const CompareScreen(mode: CompareMode.versus)),
            ),
            const SizedBox(height: 12),
            _ModuleTile(
              icon: Icons.menu_book_rounded,
              title: 'Looksmaxing Wiki & Saved Reports',
              subtitle: 'What the evidence says, and every scan you kept',
              accent: AppColors.accentSoft,
              trailing: count == 0 ? null : '$count',
              onTap: () => _push(const WikiScreen()),
            ),
            const SizedBox(height: 30),
            const _PrivacyFooter(),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

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
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.latest, required this.onStart});

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
                    scan.grade,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

/// One navigation module. [highlight] promotes the primary action to a tinted
/// card so the eye lands there first.
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
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

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

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
