import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/report.dart';
import '../data/scan_history.dart';
import 'theme.dart';

/// One wiki entry: a claim, what it actually targets, and how strong the
/// evidence is. Written to be useful on its own and to never pretend a
/// measurement is a verdict about a person.
class _Entry {
  const _Entry({
    required this.title,
    required this.kicker,
    required this.evidence,
    required this.body,
  });

  final String title;
  final String kicker;
  final EvidenceStrength evidence;
  final String body;
}

const List<_Entry> _entries = <_Entry>[
  _Entry(
    title: 'What this app actually measures',
    kicker: 'Start here',
    evidence: EvidenceStrength.measurement,
    body:
        'Three geometric ratios from one 2D photo: the eye-line against the '
        'nose bridge, the angle of the jaw at the chin, and the balance of the '
        'hairline-to-brow, brow-to-nose and nose-to-chin spans. Nothing here is '
        'an attractiveness score, a ranking, or a prediction. A score of 74 '
        'means "these ratios sit near the middle of the reference band this app '
        'defines", not "you are a 74".',
  ),
  _Entry(
    title: 'The camera moves the numbers more than you do',
    kicker: 'Measurement factor',
    evidence: EvidenceStrength.measurement,
    body:
        'A phone camera at 20 cm stretches the centre of the face and shrinks '
        'the ears; at 1.5 m it flattens the nose. Tilting your head 10° changes '
        'measured symmetry about as much as a millimetre of real asymmetry. So '
        'hold the phone at arm\'s length, keep your eyes level, stand in the '
        'same spot with the same window light, and compare your scans with each '
        'other rather than with a stranger\'s.',
  ),
  _Entry(
    title: 'Body fat changes the jawline, slowly',
    kicker: 'Facial definition',
    evidence: EvidenceStrength.strong,
    body:
        'Subcutaneous fat sits over the jaw border and under the chin, so it '
        'blunts the angle this app measures. Losing fat at a sustainable rate '
        'is the single most reliable way to sharpen a jawline, and it takes '
        'months, not days. The honest caveat: where you store fat is largely '
        'genetic, and for some people the face never becomes angular at any '
        'healthy weight.',
  ),
  _Entry(
    title: 'Sleep and salt: a fast, temporary effect',
    kicker: 'Water retention',
    evidence: EvidenceStrength.moderate,
    body:
        'Short sleep and a high-salt evening both increase facial puffiness the '
        'next morning, which rounds the jaw and can shift a scan a few points. '
        'It is real but it is temporary — rescan after a normal night before '
        'concluding anything. Nothing here justifies a supplement.',
  ),
  _Entry(
    title: 'Mewing: what the evidence says',
    kicker: 'Posture',
    evidence: EvidenceStrength.emerging,
    body:
        'There is no good evidence that tongue posture remodels adult jaw bone; '
        'bone that has finished growing does not reshape under resting tongue '
        'pressure. What it can plausibly change is the resting position of the '
        'tongue and lips, which affects how the lower face looks in motion. '
        'Treat it as free and harmless, not as a treatment.',
  ),
  _Entry(
    title: 'Hair and grooming beat bone',
    kicker: 'Framing',
    evidence: EvidenceStrength.strong,
    body:
        'Hairline shape, hair volume, brow grooming and whether your jaw is '
        'clean-shaven or stubbled change the perceived shape of a face more '
        'than any realistic change to the bone underneath. Two scans with '
        'different hair are two different photographs — keep it consistent if '
        'you want the comparison to mean something.',
  ),
  _Entry(
    title: 'Skin and sunscreen',
    kicker: 'Ageing',
    evidence: EvidenceStrength.strong,
    body:
        'Daily sunscreen is the best-evidenced intervention for how facial skin '
        'ages, and it shows up decades later rather than in a month. Smoking '
        'and heavy drinking do the opposite. Neither is measurable by this '
        'app; both matter more than anything it can measure.',
  ),
  _Entry(
    title: 'When to see a professional',
    kicker: 'Medical',
    evidence: EvidenceStrength.strong,
    body:
        'A bite that does not meet, jaw pain, mouth breathing, snoring or a '
        'sudden change in facial symmetry are reasons to see a dentist, '
        'orthodontist or doctor — not to run another scan. This app can tell '
        'you two numbers moved; it cannot tell you why, and it is not a medical '
        'device.',
  ),
];

/// Two tabs: the evidence notes, and the scans saved on this device.
class WikiScreen extends StatelessWidget {
  const WikiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          title: const Text(
            'LIBRARY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: AppColors.textPrimary,
            ),
          ),
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textTertiary,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            tabs: <Widget>[
              Tab(text: 'Looksmaxing wiki'),
              Tab(text: 'Saved reports'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[_WikiList(), _SavedReports()],
        ),
      ),
    );
  }
}

class _WikiList extends StatelessWidget {
  const _WikiList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: <Widget>[
        const Text(
          'Everything here is about what a 2D photograph can and cannot tell '
          'you. Evidence labels match the ones on your results screen.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        for (final _Entry entry in _entries) _EntryTile(entry: entry),
        const SizedBox(height: 10),
        const Text(
          'Not medical advice. For anything about your bite, breathing, pain '
          'or a sudden change in symmetry, see a clinician.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final Color color = evidenceColor(entry.evidence);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.textTertiary,
          collapsedIconColor: AppColors.textTertiary,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            entry.title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                Text(
                  entry.kicker.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    entry.evidence.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          children: <Widget>[
            Text(
              entry.body,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedReports extends StatefulWidget {
  const _SavedReports();

  @override
  State<_SavedReports> createState() => _SavedReportsState();
}

class _SavedReportsState extends State<_SavedReports> {
  @override
  void initState() {
    super.initState();
    // The home screen loads this already; calling again is a no-op and covers
    // deep links straight into the library.
    final ScanHistory history = context.read<ScanHistory>();
    if (!history.isLoaded) {
      history.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScanHistory history = context.watch<ScanHistory>();
    final List<SavedScan> scans = history.scans;

    if (!history.isLoaded) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: AppColors.accent,
        ),
      );
    }

    if (scans.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'No saved reports yet. Finish a scan and it appears here, on this '
            'device only.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: <Widget>[
        for (final SavedScan scan in scans) _SavedTile(scan: scan),
        if (scans.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmClear(context, history),
            child: const Text('Delete all saved reports'),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, ScanHistory history) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Delete every saved report?'),
        content: const Text(
          'The scores are removed from this phone permanently. The originals '
          'stay in your camera folder.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await history.clear();
    }
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.scan});

  final SavedScan scan;

  @override
  Widget build(BuildContext context) {
    final Color color = scoreColor(scan.overallScore);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.textTertiary,
          collapsedIconColor: AppColors.textTertiary,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Text(
            scan.scoreText,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          title: Text(
            scan.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            scan.isFriend
                ? 'Shared report · ${scan.grade} · ${scan.shortDate}'
                : '${scan.grade} · ${scan.shortDate}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary,
            ),
          ),
          children: <Widget>[
            for (final SavedMetric metric in scan.metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        metric.title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${metric.rawValue}  ·  ${metric.score.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scoreColor(metric.score),
                      ),
                    ),
                  ],
                ),
              ),
            if (scan.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '${scan.warnings.length} capture note'
                  '${scan.warnings.length == 1 ? '' : 's'} on this scan',
                  style: const TextStyle(fontSize: 11, color: AppColors.amber),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.read<ScanHistory>().remove(scan.id),
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: const Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
