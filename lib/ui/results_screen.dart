import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/report.dart';
import '../state/analysis_controller.dart';
import 'camera_screen.dart';
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
                  const SizedBox(height: 16),
                  _PotentialCard(report: report),
                  const SizedBox(height: 16),
                  _WeaknessRoadmap(report: report),
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
                      final NavigatorState navigator = Navigator.of(context);
                      navigator.popUntil(
                        (Route<dynamic> route) => route.isFirst,
                      );
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              const CameraScreen(),
                        ),
                      );
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

/// Measured baseline against the projection, side by side.
///
/// The strict number is the headline everywhere else; this card is the only
/// place the projection appears, so it never masks what the geometry actually
/// measured.
class _PotentialCard extends StatelessWidget {
  const _PotentialCard({required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                'PROJECTION',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  report.potentialGainText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.mint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _ScoreColumn(
                label: 'OVERALL',
                value: report.overallText,
                caption: 'measured',
                color: scoreColor(report.overallScore),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 16, right: 16, bottom: 14),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: AppColors.textTertiary,
                ),
              ),
              _ScoreColumn(
                label: 'POTENTIAL',
                value: report.potentialText,
                caption: 'projected',
                color: scoreColor(report.potentialScore),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PotentialBar(
            overall: report.overallScore,
            potential: report.potentialScore,
          ),
          const SizedBox(height: 14),
          Text(
            'Overall is strict: it is what the landmarks say, with no allowance '
            'for a bad photo or a bad day. Potential adds '
            '${report.potentialGainText} points by assuming your two weakest '
            'measurements move into the band your strongest already sits in. It '
            'is a ceiling for the habits in the roadmap below, not a promise: '
            'bone structure does not change, but body composition, fluid, '
            'grooming, posture and the photo do.',
            style: const TextStyle(
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

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              value,
              style: TextStyle(
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.4,
                color: color,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 3, left: 2),
              child: Text(
                '/100',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          caption,
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// A 100-point track split into measured, projected and remaining headroom.
class _PotentialBar extends StatelessWidget {
  const _PotentialBar({required this.overall, required this.potential});

  final double overall;
  final double potential;

  @override
  Widget build(BuildContext context) {
    final int base = overall.clamp(0, 100).round();
    final int gain = (potential - overall).clamp(0, 100 - base).round();
    final int rest = (100 - base - gain).clamp(0, 100);

    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Row(
          children: <Widget>[
            if (base > 0)
              Expanded(
                flex: base,
                child: ColoredBox(color: scoreColor(overall)),
              ),
            if (gain > 0)
              Expanded(
                flex: gain,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[AppColors.mint, AppColors.accentSoft],
                    ),
                  ),
                  child: SizedBox.shrink(),
                ),
              ),
            if (rest > 0)
              Expanded(
                flex: rest,
                child: const ColoredBox(color: AppColors.surfaceHigh),
              ),
          ],
        ),
      ),
    );
  }
}

/// The lowest measurement, promoted out of the list, with its dated plan.
///
/// Deliberately the darkest surface in the app: this is the section the user is
/// meant to act on, and it should not look like another informative card.
class _WeaknessRoadmap extends StatelessWidget {
  const _WeaknessRoadmap({required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final WeaknessInsight insight = report.coreWeakness;
    final List<RoadmapStage> usedStages = <RoadmapStage>[
      for (final RoadmapStage stage in RoadmapStage.values)
        if (insight.stepsFor(stage).isNotEmpty) stage,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0A0B12), Color(0xFF141726)],
        ),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'CORE WEAKNESS AREA',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.amber,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${insight.scoreText}/100',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.amber,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            insight.title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            insight.isClearlyWeakest
                ? 'Your lowest measurement by '
                      '${insight.gapToNextBest.toStringAsFixed(0)} points.'
                : 'Effectively tied with your next measurement.',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            insight.why,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'CORRECTIVE ROADMAP',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          for (
            int stageIndex = 0;
            stageIndex < usedStages.length;
            stageIndex += 1
          ) ...<Widget>[
            Padding(
              padding: EdgeInsets.only(top: stageIndex == 0 ? 0 : 14),
              child: Text(
                usedStages[stageIndex].label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.amber,
                ),
              ),
            ),
            for (final RoadmapStep step in insight.stepsFor(
              usedStages[stageIndex],
            ))
              _RoadmapStepTile(
                index: insight.steps.indexOf(step) + 1,
                step: step,
              ),
          ],
        ],
      ),
    );
  }
}

class _RoadmapStepTile extends StatelessWidget {
  const _RoadmapStepTile({required this.index, required this.step});

  final int index;
  final RoadmapStep step;

  @override
  Widget build(BuildContext context) {
    final Color evidence = evidenceColor(step.evidence);
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceHigh,
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  step.detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: evidence,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      step.evidence.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: evidence,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
