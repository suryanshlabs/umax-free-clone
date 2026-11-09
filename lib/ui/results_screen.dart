import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/report.dart';
import '../core/umax_file.dart';
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
                  const SizedBox(height: 16),
                  _ShareFileCard(report: report),
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

/// Exports the report as a `.umax` file through Android's own save dialog, so
/// the user picks the folder (Downloads, Documents, a memory card) and no
/// storage permission is needed.
class _ShareFileCard extends StatelessWidget {
  const _ShareFileCard({required this.report});

  final AnalysisReport report;

  Future<void> _export(BuildContext context) async {
    final String? title = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _NameReportDialog(initial: report.bandLabel),
    );
    if (title == null || !context.mounted) {
      return;
    }

    final UmaxDocument document = UmaxDocument.fromReport(report, title: title);
    final String fileName = UmaxDocument.suggestedFileName(title);

    try {
      final Uri? saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(document.encode())),
        mimeType: 'application/json',
        dialogTitle: 'Save your .umax report',
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null
                ? 'Save cancelled. Nothing was written.'
                : 'Saved $fileName. Send it to a friend, then open Friend VS '
                      'Mode to import it.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The file could not be saved (${error.code}).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(
                Icons.ios_share_rounded,
                size: 16,
                color: AppColors.accentSoft,
              ),
              SizedBox(width: 10),
              Text(
                'SHARE DATA FILE',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Exports the scores and raw measurements as a small .umax file — a '
            'name, the numbers and the timestamp. No photo, no location. A '
            'friend imports it to compare faces without either phone talking '
            'to a server.',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _export(context),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Save .umax file'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(
                color: AppColors.accentSoft.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameReportDialog extends StatefulWidget {
  const _NameReportDialog({required this.initial});

  final String initial;

  @override
  State<_NameReportDialog> createState() => _NameReportDialogState();
}

class _NameReportDialogState extends State<_NameReportDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: 'My ${widget.initial.toLowerCase()} scan',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? 'My scan' : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceHigh,
      title: const Text('Name this report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'The name travels with the file, so whoever imports it sees what '
            'you called it.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: UmaxDocument.maxTitleLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (String _) => _submit(),
            decoration: const InputDecoration(hintText: 'e.g. Alex, November'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Choose location')),
      ],
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
                      report.bandLabel,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report.bandExplanation,
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
            'device and not an attractiveness rating. Each value is agreement '
            'with a reference band defined in this app\u2019s calibration, and '
            'the combined number is only their weighted mean. There is no '
            'potential score and no grade. Compare your scans with each other '
            'rather than with 100: lighting, lens distortion and head angle all '
            'move the result.',
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
                  'LOWEST AGREEMENT',
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
