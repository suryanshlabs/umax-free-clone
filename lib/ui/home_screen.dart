import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/scan_history.dart';
import 'analyze_source_sheet.dart';
import 'compare_screen.dart';
import 'error_logs_screen.dart';
import 'home_widgets.dart';
import 'home_widgets_tiles.dart';
import 'multiangle_scan_sheet.dart';
import 'profile_input_sheet.dart';
import 'theme.dart';
import 'wiki/wiki_screen.dart';
import 'wiki_screen.dart';

/// The hub. Modules, one primary action, and the last score kept visible so
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
    // Optional profile first: saved when filled, skipped gracefully when not.
    // Either way the scan continues with baseline advice if BMI is unknown.
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
              subtitle: 'Capture one photo and score your geometry',
              accent: AppColors.accent,
              highlight: true,
              trailing: 'START',
              onTap: () => unawaited(_startAnalyze()),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.compare_arrows_rounded,
              title: 'Multi-Angle Profile Scan',
              subtitle: 'Front, left and right profiles in one flow',
              accent: AppColors.mint,
              onTap: () => _push(const MultiAngleScanSheet()),
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
              icon: Icons.sports_kabaddi_rounded,
              title: 'Friend VS Mode',
              subtitle: 'Two faces, head to head, same ruler',
              accent: AppColors.amber,
              onTap: () => _push(const CompareScreen(mode: CompareMode.versus)),
            ),
            const SizedBox(height: 12),
            HomeModuleTile(
              icon: Icons.menu_book_rounded,
              title: 'Profile Encyclopedia',
              subtitle: 'Four offline sections: growth, symmetry, body comp, skin & hair',
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
            const SizedBox(height: 30),
            const HomePrivacyFooter(),
          ],
        ),
      ),
    );
  }
}
