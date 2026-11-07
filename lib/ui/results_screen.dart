import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/report.dart';
import '../state/analysis_controller.dart';
import 'theme.dart';
import 'widgets/metric_card.dart';
import 'widgets/score_ring.dart';

/// The dashboard: overall score, the three measurements with their raw numbers,
/// and the advice generated for each of them.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AnalysisController controller = context.watch<AnalysisController>();
    final AnalysisReport? report = controller.report;

    if (report == null) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('No analysis to show'),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              sliver: SliverList.list(
                children: <Widget>[
                  _Header(report: report),
                  const SizedBox(height: 20),
                  _ScoreCard(report: report),
                  if (report.qualityWarnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    _WarningCard(warnings: report.qualityWarnings),
                  ],
                  if (report.safetyNote != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _SafetyCard(note: report.safetyNote!),
                  ],
                  const SizedBox(height: 28),
                  const Text(
                    'YOUR MEASUREMENTS',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final MetricResult metric in report.metrics)
                    MetricCard(metric: metric),
                  const SizedBox(height: 6),
                  const _DisclaimerCard(),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      controller.reset();
                      Navigator.of(
                        context,
                      ).popUntil((Route<dynamic> route) => route.isFirst);
                    },
                    child: const Text('Scan again'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const Expanded(
          child: Text(
            'Analysis complete',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          _formatTimestamp(report.createdAt),
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  static String _formatTimestamp(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}  '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final AnalysisReport report;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: report.toShareText()));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary copied to the clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color color = scoreColor(report.overallScore);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
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
        children: <Widget>[
          Row(
            children: <Widget>[
              ScoreRing(score: report.overallScore),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      report.grade,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report.gradeBlurb,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              if (report.imagePath != null)
                _PhotoThumb(path: report.imagePath!),
              if (report.imagePath != null) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '468 landmarks · '
                  '${report.isReliable ? 'clean capture' : 'read the notes'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (!File(path).existsSync()) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 34,
        height: 34,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return const ColoredBox(color: AppColors.surfaceHigh);
              },
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.straighten_rounded, size: 16, color: AppColors.amber),
              SizedBox(width: 8),
              Text(
                'CAPTURE NOTES',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final String warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                warning,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.health_and_safety_outlined,
            size: 17,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'HOW TO READ THIS',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppColors.textTertiary,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'These are geometric measurements from one 2D photo, not a medical '
            'device and not an attractiveness rating. Scores are mapped onto '
            'reference bands defined in this app\u2019s calibration, so compare '
            'your scans with each other rather than with the number 100. '
            'Lighting, lens distortion and head angle all move the result.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
