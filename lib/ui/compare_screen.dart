import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/comparison.dart';
import '../core/facial_analysis_service.dart';
import '../core/photo_analyzer.dart';
import '../core/umax_file.dart';
import '../data/scan_history.dart';
import '../ml/photo_prep.dart';
import 'camera_screen.dart';
import 'theme.dart';

/// What the comparison screen is for.
enum CompareMode {
  progress('Compare My Progress', 'Two scans of you, measured the same way'),
  versus('Compare Reports', 'Two reports measured the same way');

  const CompareMode(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Which two reports the comparison screen puts side by side.
enum VersusInput {
  photos('Photos', 'Measure two faces now'),
  reports('Reports', 'Two saved .umax reports');

  const VersusInput(this.label, this.hint);

  final String label;
  final String hint;
}

/// How a slot gets filled.
enum _SlotAction { saved, camera, gallery, importFile }

/// Side-by-side comparison of two entries, whatever their origin.
///
/// Both modules share one screen and one delta engine because the arithmetic is
/// identical; only the captions and the verdict wording change. A scoring change
/// can therefore never make progress and versus disagree.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.mode});

  final CompareMode mode;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final PhotoAnalyzer _analyzer = PhotoAnalyzer();

  String? _leftId;
  String? _rightId;
  ComparisonEntry? _leftPhoto;
  ComparisonEntry? _rightPhoto;

  VersusInput _input = VersusInput.photos;
  bool _seeded = false;
  bool _busy = false;
  String _busyLabel = '';
  String? _error;

  @override
  void dispose() {
    _analyzer.dispose();
    super.dispose();
  }

  /// Picks sensible defaults once: earliest vs latest for progress, the two
  /// newest scans for a versus between saved reports.
  void _seed(List<SavedScan> scans) {
    if (_seeded || scans.length < 2) {
      return;
    }
    _seeded = true;
    if (_leftId != null || _rightId != null) {
      return;
    }
    if (widget.mode == CompareMode.progress) {
      _leftId = scans.last.id;
      _rightId = scans.first.id;
    } else if (_input == VersusInput.reports) {
      _rightId = scans.first.id;
      _leftId = scans[1].id;
    }
  }

  ComparisonEntry? _entryFor(bool left, List<SavedScan> scans) {
    final ComparisonEntry? manual = left ? _leftPhoto : _rightPhoto;
    if (manual != null) {
      return manual;
    }
    final String? id = left ? _leftId : _rightId;
    if (id == null) {
      return null;
    }
    for (final SavedScan scan in scans) {
      if (scan.id == id) {
        return ComparisonEntry.fromScan(scan);
      }
    }
    return null;
  }

  Future<void> _choose(bool left) async {
    final _SlotAction? action = await showModalBottomSheet<_SlotAction>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext context) => _SlotSheet(
        mode: widget.mode,
        input: _input,
        side: left ? 'first' : 'second',
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _SlotAction.saved:
        await _pickSaved(left);
      case _SlotAction.camera:
        await _capture(left);
      case _SlotAction.gallery:
        await _pickGallery(left);
      case _SlotAction.importFile:
        await _importFriend(left);
    }
  }

  Future<void> _pickSaved(bool left) async {
    final List<SavedScan> scans = context.read<ScanHistory>().scans;
    if (scans.isEmpty) {
      _tell('No saved scans yet. Finish a scan first.');
      return;
    }
    final String? otherId = left ? _rightId : _leftId;
    final SavedScan? chosen = await showModalBottomSheet<SavedScan>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext context) => _ScanPickerSheet(
        scans: scans,
        otherId: otherId,
        left: left,
        mode: widget.mode,
      ),
    );
    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      if (left) {
        _leftId = chosen.id;
        _leftPhoto = null;
      } else {
        _rightId = chosen.id;
        _rightPhoto = null;
      }
      _error = null;
    });
  }

  Future<void> _capture(bool left) async {
    final String? path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) =>
            const CameraScreen(returnPathOnly: true),
      ),
    );
    if (path == null || !mounted) {
      return;
    }
    await _measure(left, path);
  }

  Future<void> _pickGallery(bool left) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: 4096,
        maxHeight: 4096,
      );
    } on PlatformException catch (error) {
      _tell('The gallery could not be opened (${error.code}).');
      return;
    } on Exception {
      _tell('A photo could not be read from the gallery.');
      return;
    }
    if (picked == null || !mounted) {
      return;
    }
    await _measure(left, picked.path);
  }

  /// Runs the on-device pipeline for one photo and drops the result into a slot.
  Future<void> _measure(bool left, String path) async {
    final ScanHistory history = context.read<ScanHistory>();
    setState(() {
      _busy = true;
      _busyLabel = left
          ? 'Measuring the first photo…'
          : 'Measuring the second photo…';
      _error = null;
    });
    try {
      final PhotoAnalysis analysis = await _analyzer.analyse(path);
      if (!mounted) {
        return;
      }
      if (widget.mode == CompareMode.progress) {
        // A photo used in your own timeline is one of your scans, so it joins the
        // archive like any other.
        await history.add(analysis.report);
      }
      if (!mounted) {
        return;
      }
      final String label = widget.mode == CompareMode.progress
          ? (left ? 'Before photo' : 'After photo')
          : (left ? 'You' : 'Friend');
      setState(() {
        final ComparisonEntry entry = ComparisonEntry.fromReport(
          analysis.report,
          label: label,
        );
        if (left) {
          _leftPhoto = entry;
          _leftId = null;
        } else {
          _rightPhoto = entry;
          _rightId = null;
        }
        _busy = false;
      });
    } on PhotoPreparationException catch (error) {
      _fail(error.message);
    } on FacialAnalysisException catch (error) {
      _fail(error.message);
    } on Exception {
      _fail(
        'That photo could not be measured. Try a different one with the face '
        'centred and lit from the front.',
      );
    }
  }

  /// Reads a friend's `.umax` file, files it in the archive, and drops it into
  /// the chosen slot. No image is processed in this path.
  Future<void> _importFriend(bool left) async {
    final ScanHistory history = context.read<ScanHistory>();
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        dialogTitle: 'Choose a .umax report',
        type: FileType.custom,
        allowedExtensions: const <String>[UmaxDocument.extension],
      );
    } on PlatformException catch (error) {
      _tell('The file picker could not be opened (${error.code}).');
      return;
    }
    if (file == null) {
      return;
    }

    final UmaxDocument document;
    try {
      final Uint8List bytes = await file.readAsBytes();
      document = UmaxDocument.decode(utf8.decode(bytes, allowMalformed: true));
    } on UmaxFormatException catch (error) {
      _tell(error.message);
      return;
    } on Exception {
      _tell('That file could not be read from the device.');
      return;
    }

    final SavedScan imported = document.asImportedScan();
    await history.addSaved(imported);
    if (!mounted) {
      return;
    }
    setState(() {
      if (left) {
        _leftId = imported.id;
        _leftPhoto = null;
      } else {
        _rightId = imported.id;
        _rightPhoto = null;
      }
      _error = null;
    });
    _tell('Imported “${imported.displayTitle}” into your archive.');
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  void _tell(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ScanHistory history = context.watch<ScanHistory>();
    final List<SavedScan> scans = history.scans;
    _seed(scans);

    final ComparisonEntry? left = _entryFor(true, scans);
    final ComparisonEntry? right = _entryFor(false, scans);
    final bool reportsMode =
        widget.mode == CompareMode.progress || _input == VersusInput.reports;

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
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: <Widget>[
                  _Header(mode: widget.mode),
                  if (widget.mode == CompareMode.versus) ...<Widget>[
                    const SizedBox(height: 16),
                    _InputToggle(
                      input: _input,
                      onChanged: (VersusInput value) {
                        if (_busy) {
                          return;
                        }
                        setState(() {
                          _input = value;
                          _error = null;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_busy) ...<Widget>[
                    _BusyCard(label: _busyLabel),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _SlotCard(
                          caption: _caption(true),
                          entry: left,
                          onTap: _busy ? null : () => _choose(true),
                        ),
                      ),
                      const _VsBadge(),
                      Expanded(
                        child: _SlotCard(
                          caption: _caption(false),
                          entry: right,
                          onTap: _busy ? null : () => _choose(false),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _ErrorCard(
                      message: _error!,
                      onDismiss: () => setState(() => _error = null),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (left != null && right != null)
                    ..._body(
                      ComparisonResult(before: left, after: right),
                      left,
                      right,
                    )
                  else
                    _EmptyHint(
                      mode: widget.mode,
                      input: _input,
                      haveLeft: left != null,
                      haveRight: right != null,
                    ),
                  if (reportsMode) ...<Widget>[
                    const SizedBox(height: 22),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _importFriend(true),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Import Friend File (.umax)'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  String _caption(bool left) {
    if (widget.mode == CompareMode.progress) {
      return left ? 'BEFORE' : 'AFTER';
    }
    return left ? 'YOU' : 'FRIEND';
  }

  List<Widget> _body(
    ComparisonResult result,
    ComparisonEntry left,
    ComparisonEntry right,
  ) {
    final bool versus = widget.mode == CompareMode.versus;
    return <Widget>[
      _OverallDelta(result: result, versus: versus),
      const SizedBox(height: 22),
      _SectionLabel(
        versus ? 'MEASUREMENT DIFFERENCES' : 'CHANGE SINCE EARLIER',
      ),
      const SizedBox(height: 4),
      Text(
        versus
            ? 'Every measurement, ordered by the size of the difference. A '
                  'difference inside the noise band is shown as even; the two '
                  'sides are not ranked.'
            : 'Agreement change first, then the same change in the measurement '
                  'itself.',
        style: const TextStyle(
          fontSize: 11,
          height: 1.5,
          color: AppColors.textTertiary,
        ),
      ),
      const SizedBox(height: 12),
      for (final MetricDelta delta in result.byChange)
        _DeltaCard(delta: delta, versus: versus),
      if (versus) ...<Widget>[
        const SizedBox(height: 10),
        _LeaderBoardSummary(result: result),
      ],
      const SizedBox(height: 12),
      _Verdict(result: result, versus: versus),
      if (result.hasCaptureNotes) ...<Widget>[
        const SizedBox(height: 16),
        const _CaptureCaveat(),
      ],
      if (result.before.isImported || result.after.isImported) ...<Widget>[
        const SizedBox(height: 16),
        const _ImportNote(),
      ],
    ];
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

class _InputToggle extends StatelessWidget {
  const _InputToggle({required this.input, required this.onChanged});

  final VersusInput input;
  final ValueChanged<VersusInput> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          for (final VersusInput option in VersusInput.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: option == input
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: option == input
                          ? AppColors.accent.withValues(alpha: 0.55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: option == input
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.hint,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
        letterSpacing: 1.8,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.caption,
    required this.entry,
    required this.onTap,
  });

  final String caption;
  final ComparisonEntry? entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ComparisonEntry? value = entry;
    final bool filled = value != null;
    final Color accent = filled
        ? scoreColor(value.overallScore)
        : AppColors.textTertiary;

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
            border: Border.all(
              color: filled
                  ? accent.withValues(alpha: 0.35)
                  : AppColors.outline,
            ),
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
                  Icon(
                    filled
                        ? Icons.unfold_more_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!filled) ...<Widget>[
                const Text(
                  'Tap to choose',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Saved scan or photo',
                  style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                ),
              ] else ...<Widget>[
                Text(
                  value.scoreText,
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
                  value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _date(value.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
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

class _BusyCard extends StatelessWidget {
  const _BusyCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 17,
                color: AppColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onDismiss,
              child: const Text('Dismiss'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.mode,
    required this.input,
    required this.haveLeft,
    required this.haveRight,
  });

  final CompareMode mode;
  final VersusInput input;
  final bool haveLeft;
  final bool haveRight;

  @override
  Widget build(BuildContext context) {
    final String body;
    if (mode == CompareMode.progress) {
      body =
          'Put your earlier scan or photo on the left and the later one on the '
          'right. Both are measured by the same pipeline, so the only thing '
          'that changes between them is you — as long as the light and the '
          'distance stay similar.';
    } else if (input == VersusInput.photos) {
      body =
          'Add two faces, one per side. Each photo is rotated upright, cropped '
          'to 1080 x 1080 and measured on this phone, one after the other. '
          'Nothing is uploaded and neither photo is added to your archive.';
    } else {
      body =
          'Pick your own saved report on the left, then import a friend\'s '
          '.umax file on the right. No photos are processed in this mode: the '
          'two reports already hold every number needed.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
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
              const Icon(
                Icons.compare_arrows_rounded,
                size: 17,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Text(
                haveLeft || haveRight ? 'One side to go' : 'Two sides needed',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverallDelta extends StatelessWidget {
  const _OverallDelta({required this.result, required this.versus});

  final ComparisonResult result;
  final bool versus;

  @override
  Widget build(BuildContext context) {
    final bool flat = result.overallFlat;
    final Color color = flat
        ? AppColors.textSecondary
        : (result.overallDelta > 0 ? AppColors.mint : AppColors.danger);

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
                : (result.overallDelta > 0
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
                  versus ? 'SCORE DIFFERENCE' : 'CHANGE SINCE THE EARLIER SIDE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      result.overallPointsText,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        result.overallPercentText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color.withValues(alpha: 0.85),
                        ),
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

class _DeltaCard extends StatelessWidget {
  const _DeltaCard({required this.delta, required this.versus});

  final MetricDelta delta;
  final bool versus;

  @override
  Widget build(BuildContext context) {
    // Both directions use the same neutral accent: a higher number means
    // closer agreement with a reference, not a better face.
    final Color color = delta.isFlat
        ? AppColors.textTertiary
        : AppColors.accentSoft;
    final String? raw = delta.rawChangeText;

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
                  delta.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: color.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  versus
                      ? (delta.isFlat
                            ? 'even'
                            : (delta.isHigher ? 'B higher' : 'B lower'))
                      : delta.percentText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _MiniScore(value: delta.before.score, label: 'A'),
              const SizedBox(width: 12),
              Expanded(
                child: _CompareBar(
                  before: delta.before.score,
                  after: delta.after.score,
                ),
              ),
              const SizedBox(width: 12),
              _MiniScore(
                value: delta.after.score,
                label: 'B',
                alignment: CrossAxisAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                '${delta.before.rawValue}  →  ${delta.after.rawValue}',
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.2,
                  color: AppColors.textTertiary,
                ),
              ),
              if (raw != null) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    raw,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  delta.pointsText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({
    required this.value,
    required this.label,
    this.alignment = CrossAxisAlignment.start,
  });

  final double value;
  final String label;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
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
          value.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: scoreColor(value),
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({required this.before, required this.after});

  final double before;
  final double after;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[_bar(before), const SizedBox(height: 4), _bar(after)],
    );
  }

  Widget _bar(double score) {
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
              child: ColoredBox(color: scoreColor(score)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderBoardSummary extends StatelessWidget {
  const _LeaderBoardSummary({required this.result});

  final ComparisonResult result;

  @override
  Widget build(BuildContext context) {
    final bool even = result.allWithinNoise;
    final Color color = even ? AppColors.textSecondary : AppColors.accentSoft;
    final String title = even
        ? 'No measurable difference'
        : 'How the two sides differ';
    final String detail = even
        ? 'All ${result.deltas.length} measurements sit inside the noise band '
              'for these photos, so this app cannot tell the two sides apart.'
        : '${result.higherCount} measurement(s) read higher on the second side, '
              '${result.lowerCount} lower, and ${result.unchangedCount} '
              'unchanged. That describes the measurements, not the people.';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            even ? Icons.handshake_outlined : Icons.straighten_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
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

class _Verdict extends StatelessWidget {
  const _Verdict({required this.result, required this.versus});

  final ComparisonResult result;
  final bool versus;

  String _text() {
    if (versus) {
      if (result.allWithinNoise) {
        return 'No measurement clears the noise band, so there is nothing here '
            'to compare. Two photos taken at different angles can differ by '
            'more than this on the same face.';
      }
      return 'These are two sets of measurements from two photos, not a '
          'ranking. Camera distance, head angle and lighting move every number '
          'on this screen, and the app cannot control for any of them. Read the '
          'raw values and their capture notes before drawing a conclusion.';
    }
    if (result.overallFlat) {
      return 'Holding steady. Two readings within noise of each other is '
          'exactly what consistent lighting and posture should produce.';
    }
    final MetricDelta? swing = result.biggestSwing;
    final String driver = swing == null
        ? ''
        : ' The largest move is ${swing.title.toLowerCase()}, '
              '${swing.percentText}.';
    if (result.overallDelta > 0) {
      return 'Up ${result.overallPercentText}.$driver If the light and the '
          'distance were similar in both photos, that is a real change; if not, '
          'repeat the scan in the same spot before trusting it.';
    }
    return 'Down ${result.overallPercentText}.$driver Check the capture '
        'conditions first: head angle and camera distance move these numbers '
        'more than anything you can do in a week.';
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

class _CaptureCaveat extends StatelessWidget {
  const _CaptureCaveat();

  @override
  Widget build(BuildContext context) {
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
              'At least one of these readings carried capture notes (head '
              'turned, tilted, too far away). Differences smaller than five '
              'points are usually capture differences, not a real change.',
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

class _ImportNote extends StatelessWidget {
  const _ImportNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'One side arrived as a .umax file, so it was measured on someone else\'s '
      'phone under their lighting. Scores are comparable because the pipeline '
      'and the 1080 x 1080 crop are identical, but the photo conditions are not.',
      style: TextStyle(
        fontSize: 11,
        height: 1.55,
        color: AppColors.textTertiary,
      ),
    );
  }
}

/// The bottom sheet that offers the ways to fill a slot.
class _SlotSheet extends StatelessWidget {
  const _SlotSheet({
    required this.mode,
    required this.input,
    required this.side,
  });

  final CompareMode mode;
  final VersusInput input;
  final String side;

  @override
  Widget build(BuildContext context) {
    final bool reportsOnly =
        mode == CompareMode.progress || input == VersusInput.reports;
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
          const SizedBox(height: 16),
          Text(
            'Choose the $side side',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mode == CompareMode.progress
                ? 'A saved scan, or a photo measured now'
                : 'A saved report, or a face measured now',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 12),
          _SheetRow(
            icon: Icons.history_rounded,
            title: 'Saved scan',
            subtitle: 'From this device\'s archive',
            onTap: () => Navigator.of(context).pop(_SlotAction.saved),
          ),
          if (!reportsOnly) ...<Widget>[
            _SheetRow(
              icon: Icons.photo_camera_rounded,
              title: 'Take a Photo',
              subtitle: 'Guided camera, measured immediately',
              onTap: () => Navigator.of(context).pop(_SlotAction.camera),
            ),
            _SheetRow(
              icon: Icons.photo_library_rounded,
              title: 'Upload from Gallery',
              subtitle: 'An existing photo on this device',
              onTap: () => Navigator.of(context).pop(_SlotAction.gallery),
            ),
          ],
          _SheetRow(
            icon: Icons.file_upload_outlined,
            title: 'Import Friend File',
            subtitle: 'A .umax report someone sent you',
            onTap: () => Navigator.of(context).pop(_SlotAction.importFile),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: AppColors.accentSoft),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
      ),
    );
  }
}

class _ScanPickerSheet extends StatelessWidget {
  const _ScanPickerSheet({
    required this.scans,
    required this.otherId,
    required this.left,
    required this.mode,
  });

  final List<SavedScan> scans;
  final String? otherId;
  final bool left;
  final CompareMode mode;

  @override
  Widget build(BuildContext context) {
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
            left ? 'Choose the first scan' : 'Choose the second scan',
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
                    scan.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    scan.isFriend
                        ? 'Shared report · ${scan.shortDate}'
                        : scan.shortDate,
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
  }
}

String _date(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
