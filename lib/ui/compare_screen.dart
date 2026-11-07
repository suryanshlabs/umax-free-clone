import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/scan_history.dart';
import 'theme.dart';

/// How two scans are framed: your own timeline, or two people.
enum CompareMode {
  progress('Compare My Progress', 'Two scans of you, measured the same way'),
  versus('Friend VS Mode', 'Two faces against the same ruler');

  const CompareMode(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Side-by-side comparison of two saved scans.
///
/// Both modules share this screen because the arithmetic is identical; only the
/// labels and the verdict wording change. Keeping one implementation means a
/// scoring change can never make progress and versus disagree.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.mode});

  final CompareMode mode;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String? _leftId;
  String? _rightId;

  /// Picks sensible defaults the first time the list is available: earliest vs
  /// latest for progress, the two newest scans for versus.
  void _seed(List<SavedScan> scans) {
    if (scans.length < 2) {
      return;
    }
    if (widget.mode == CompareMode.progress) {
      _leftId ??= scans.last.id;
      _rightId ??= scans.first.id;
    } else {
      _rightId ??= scans.first.id;
      _leftId ??= scans[1].id;
    }
  }

  SavedScan? _find(List<SavedScan> scans, String? id) {
    for (final SavedScan scan in scans) {
      if (scan.id == id) {
        return scan;
      }
    }
    return null;
  }

  Future<void> _pick({
    required bool left,
    required List<SavedScan> scans,
    required String? otherId,
  }) async {
    final SavedScan? chosen = await showModalBottomSheet<SavedScan>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 14),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                left
                    ? 'Choose the left scan'
                    : (widget.mode == CompareMode.versus
                          ? 'Choose the challenger'
                          : 'Choose the newer scan'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: scans.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SavedScan scan = scans[index];
                    final bool disabled = scan.id == otherId;
                    return ListTile(
                      enabled: !disabled,
                      onTap: disabled
                          ? null
                          : () => Navigator.of(context).pop(scan),
                      leading: Text(
                        scan.scoreText,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: scoreColor(scan.overallScore),
                        ),
                      ),
                      title: Text(
                        scan.grade,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        scan.shortDate,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      trailing: disabled
                          ? const Text(
                              'in use',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );

    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      if (left) {
        _leftId = chosen.id;
      } else {
        _rightId = chosen.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ScanHistory history = context.watch<ScanHistory>();
    final List<SavedScan> scans = history.scans;
    _seed(scans);

    final SavedScan? left = _find(scans, _leftId);
    final SavedScan? right = _find(scans, _rightId);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: !history.isLoaded
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.accent,
                ),
              )
            : scans.length < 2
            ? _NotEnoughScans(mode: widget.mode, count: scans.length)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: <Widget>[
                  _Header(mode: widget.mode),
                  const SizedBox(height: 18),
                  if (left != null && right != null) ...<Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: _SelectorCard(
                            caption: widget.mode == CompareMode.versus
                                ? 'YOU'
                                : 'EARLIER',
                            scan: left,
                            onTap: () => _pick(
                              left: true,
                              scans: scans,
                              otherId: right.id,
                            ),
                          ),
                        ),
                        const _VsBadge(),
                        Expanded(
                          child: _SelectorCard(
                            caption: widget.mode == CompareMode.versus
                                ? 'CHALLENGER'
                                : 'LATEST',
                            scan: right,
                            onTap: () => _pick(
                              left: false,
                              scans: scans,
                              otherId: left.id,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _OverallDelta(left: left, right: right, mode: widget.mode),
                    const SizedBox(height: 22),
                    const _SectionLabel('MEASUREMENT BY MEASUREMENT'),
                    const SizedBox(height: 10),
                    for (final SavedMetric metric in left.metrics)
                      _MetricCompare(
                        left: metric,
                        right: right.metric(metric.id),
                      ),
                    const SizedBox(height: 12),
                    _Verdict(left: left, right: right, mode: widget.mode),
                    if (left.warnings.isNotEmpty ||
                        right.warnings.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _Caveat(left: left, right: right),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.mode});

  final CompareMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                mode.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                mode.subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
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
        letterSpacing: 1.8,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _SelectorCard extends StatelessWidget {
  const _SelectorCard({
    required this.caption,
    required this.scan,
    required this.onTap,
  });

  final String caption;
  final SavedScan scan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = scoreColor(scan.overallScore);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.unfold_more_rounded,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                scan.scoreText,
                style: TextStyle(
                  fontSize: 32,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: accent,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                scan.grade,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                scan.shortDate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 34),
      child: Text(
        'VS',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _OverallDelta extends StatelessWidget {
  const _OverallDelta({
    required this.left,
    required this.right,
    required this.mode,
  });

  final SavedScan left;
  final SavedScan right;
  final CompareMode mode;

  @override
  Widget build(BuildContext context) {
    final double delta = right.overallScore - left.overallScore;
    final bool flat = delta.abs() < 1.5;
    final Color color = flat
        ? AppColors.textSecondary
        : (delta > 0 ? AppColors.mint : AppColors.danger);
    final String signed = flat
        ? 'no meaningful change'
        : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} points';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            flat
                ? Icons.horizontal_rule_rounded
                : (delta > 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded),
            color: color,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  mode == CompareMode.versus
                      ? 'SCORE DIFFERENCE'
                      : 'CHANGE SINCE THE EARLIER SCAN',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  signed,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCompare extends StatelessWidget {
  const _MetricCompare({required this.left, required this.right});

  final SavedMetric left;
  final SavedMetric? right;

  @override
  Widget build(BuildContext context) {
    final SavedMetric? other = right;
    final double? delta = other == null ? null : other.score - left.score;
    final Color deltaColor = delta == null || delta.abs() < 1.5
        ? AppColors.textTertiary
        : (delta > 0 ? AppColors.mint : AppColors.danger);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  left.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (delta != null)
                Text(
                  delta.abs() < 1.5
                      ? 'even'
                      : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: deltaColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _MiniScore(metric: left, label: 'A'),
              const SizedBox(width: 12),
              Expanded(
                child: _CompareBar(left: left.score, right: other?.score),
              ),
              const SizedBox(width: 12),
              _MiniScore(
                metric: other,
                label: 'B',
                alignment: CrossAxisAlignment.end,
              ),
            ],
          ),
          if (left.rawValue.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              other == null
                  ? left.rawValue
                  : '${left.rawValue}  vs  ${other.rawValue}',
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.2,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({
    required this.metric,
    required this.label,
    this.alignment = CrossAxisAlignment.start,
  });

  final SavedMetric? metric;
  final String label;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final SavedMetric? value = metric;
    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value == null ? '—' : value.score.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: value == null
                ? AppColors.textTertiary
                : scoreColor(value.score),
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({required this.left, required this.right});

  final double left;
  final double? right;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _bar(left, scoreColor(left)),
        const SizedBox(height: 4),
        _bar(
          right ?? 0,
          right == null ? AppColors.outline : scoreColor(right!),
        ),
      ],
    );
  }

  Widget _bar(double score, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: AppColors.surfaceHigh),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (score / 100).clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.left, required this.right, required this.mode});

  final SavedScan left;
  final SavedScan right;
  final CompareMode mode;

  String _text() {
    final double delta = right.overallScore - left.overallScore;
    if (mode == CompareMode.versus) {
      if (delta.abs() < 1.5) {
        return 'Even. Two faces this close on the same ruler means the '
            'difference is inside the noise of a single photo.';
      }
      final SavedScan winner = delta > 0 ? right : left;
      return '${winner.grade} takes it by '
          '${delta.abs().toStringAsFixed(1)} points. Still worth reading '
          'both: one photo, one angle, one lighting setup.';
    }
    if (delta > 1.5) {
      return 'Up ${delta.toStringAsFixed(1)} points. If the lighting and '
          'distance were similar, that is a real change; if not, repeat the '
          'scan in the same spot before trusting it.';
    }
    if (delta < -1.5) {
      return 'Down ${delta.abs().toStringAsFixed(1)} points. Check the capture '
          'notes first — head angle and lens distance move these numbers more '
          'than anything you can do in a week.';
    }
    return 'Holding steady. Two scans within noise of each other, which is '
        'exactly what consistent lighting and posture should produce.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'VERDICT',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _text(),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  const _Caveat({required this.left, required this.right});

  final SavedScan left;
  final SavedScan right;

  @override
  Widget build(BuildContext context) {
    final bool anyWarnings =
        left.warnings.isNotEmpty || right.warnings.isNotEmpty;
    if (!anyWarnings) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.straighten_rounded, size: 16, color: AppColors.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'At least one of these scans carried capture notes (head turned, '
              'tilted, too far away). Differences smaller than five points are '
              'usually capture differences, not you.',
              style: TextStyle(
                fontSize: 12,
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

class _NotEnoughScans extends StatelessWidget {
  const _NotEnoughScans({required this.mode, required this.count});

  final CompareMode mode;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(mode: mode),
          const Spacer(),
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: const Icon(
                    Icons.compare_arrows_rounded,
                    color: AppColors.textTertiary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  count == 0 ? 'No saved scans yet' : 'One more scan needed',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(width: 280, child: SizedBox.shrink()),
                const Text(
                  'Every finished analysis is saved automatically. Come back '
                  'here once two scans exist and they will line up side by '
                  'side, measurement by measurement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}
