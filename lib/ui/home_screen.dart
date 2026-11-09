import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/scan_history.dart';
import 'analyze_source_sheet.dart';
import 'bmi_calculator_screen.dart';
import 'compare_screen.dart';
import 'error_logs_screen.dart';
import 'home_widgets.dart';
import 'home_widgets_tiles.dart';
import 'profile_input_sheet.dart';
import 'theme.dart';
import 'media_pipe_face_scan_screen.dart';
import 'wiki/wiki_screen.dart';
import 'wiki_screen.dart';

/// The hub. Modules, one primary action, and the last score kept visible
/// so the app opens with something useful instead of a live camera view.
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
    // Optional gender first: answering or skipping changes nothing in the
    // measurement pipeline. The scan never asks for height, weight or age.
    await showProfileInputSheet(context);
    if (!mounted) {
      return;
    }
    final AnalyzeSource? source = await showAnalyzeSourceSheet(context);
    if (!mounted || source == null) {
      return;
    }
    await startFaceAnalyze(context, source);
  }

  /// The multi-angle flow used to collect three photos and then show "No
  /// reading" for every one of them, because the on-device detector only has a
  /// frontal landmark model. Rather than present that as a feature, the tile
  /// explains why it is unavailable.
  void _explainMultiAngle() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Multi-angle scan is not available'),
        content: const Text(
          'Measuring a profile angle needs a side-view landmark model, and the '
          'on-device face mesh only describes a frontal face. The earlier '
          'screen could only ever show "No reading", so it has been removed '
          'rather than report a guessed angle.\n\n'
          'Use Face Analyze for the '
          'three measurements this app can actually take.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
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
            const HomeWordmark(),
            const SizedBox(height: 24),
            HomeHeroCard(
              latest: latest,
              onStart: () => unawaited(_startAnalyze()),
            ),
            const SizedBox(height: 26),
            const HomeSectionLabel('MODULES'),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.center_focus_strong_rounded,
              title: 'Face Analyze',
              subtitle: 'Capture one photo and measure your geometry',
              accent: AppColors.accent,
              highlight: true,
              trailing: 'START',
              onTap: () => unawaited(_startAnalyze()),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.monitor_weight_outlined,
              title: 'BMI Calculator',
              subtitle:
                  'Separate tool: height, weight and age. Never used in face analysis',
              accent: AppColors.amber,
              onTap: () => _push(const BmiCalculatorScreen()),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.compare_arrows_rounded,
              title: 'Multi-Angle Profile Scan',
              subtitle: 'Not available: needs a profile landmark model',
              accent: AppColors.textTertiary,
              onTap: _explainMultiAngle,
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
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
            HomeModuleTile(
              icon: Icons.compare_rounded,
              title: 'Compare Reports',
              subtitle: 'Two saved or imported reports, side by side',
              accent: AppColors.amber,
              onTap: () => _push(const CompareScreen(mode: CompareMode.versus)),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.menu_book_rounded,
              title: 'Profile Encyclopedia',
              subtitle:
                  'Four offline sections: growth, symmetry, body comp, skin & hair',
              accent: AppColors.accentSoft,
              onTap: () => _push(const EncyclopaediaScreen()),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.menu_book_rounded,
              title: 'Looksmaxing Wiki & Saved Reports',
              subtitle: 'What the evidence says, and every scan you kept',
              accent: AppColors.accentSoft,
              trailing: count == 0 ? null : '$count',
              onTap: () => _push(const WikiScreen()),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.bug_report_rounded,
              title: 'Error Logs',
              subtitle: 'On-device crash and error log — copy, share or clear',
              accent: AppColors.danger,
              onTap: () => _push(const ErrorLogsScreen()),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.face_rounded,
              title: 'MediaPipe Face Scan',
              subtitle: 'Three-view facial geometry analysis',
              accent: AppColors.accentSoft,
              onTap: () => _push(const MediaPipeFaceScanScreen()),
            ),
            const SizedBox(height: 30),
            const HomePrivacyFooter(),
          ],
        ),
      ),
    );
  }
}