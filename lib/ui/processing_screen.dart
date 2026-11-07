import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ml/photo_prep.dart';
import '../state/analysis_controller.dart';
import 'results_screen.dart';
import 'theme.dart';
import 'widgets/scanning_painter.dart';

/// The scan that covers the real work: mesh detection, the geometry pass and
/// scoring all happen while this animation runs.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _steps = <String>[
    'Detecting 468 landmarks',
    'Measuring proportions',
    'Scoring against reference bands',
  ];

  late final AnimationController _scan;
  int _step = 0;
  Timer? _stepTimer;

  /// The prepared square, once it exists. Empty until [PhotoPreparer] has run.
  String _displayPath = '';

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 540), (_) {
      if (mounted) {
        setState(() => _step = (_step + 1) % _steps.length);
      }
    });
    unawaited(_run());
  }

  Future<void> _run() async {
    final AnalysisController controller = context.read<AnalysisController>();

    // Every input — camera or gallery — is rotated upright and cropped to a
    // fixed 1080x1080 square before detection, so two scans of the same face
    // are measured by the same ruler.
    final String path = await _prepare(widget.imagePath);
    if (!mounted) {
      return;
    }
    if (path != widget.imagePath) {
      setState(() => _displayPath = path);
    }

    await controller.analyse(path);
    if (!mounted) {
      return;
    }
    _stepTimer?.cancel();
    if (controller.phase == AnalysisPhase.ready) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const ResultsScreen(),
        ),
      );
    }
  }

  /// Returns the prepared square, or the original file if preparation fails.
  ///
  /// Falling back rather than failing is deliberate: the reader already reports
  /// unreadable images with its own readable message, and a second error path
  /// here would only add a way for the screen to break.
  Future<String> _prepare(String path) async {
    try {
      final PreparedPhoto photo = await const PhotoPreparer().preparePath(path);
      return photo.path;
    } on Exception catch (error) {
      debugPrint('Photo preparation failed, using the original: $error');
      return path;
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AnalysisController controller = context.watch<AnalysisController>();
    final bool failed = controller.phase == AnalysisPhase.failed;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    failed ? 'NO READING' : 'ANALYSING',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.6,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const Spacer(flex: 2),
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _PhotoBackdrop(
                        path: _displayPath.isEmpty
                            ? widget.imagePath
                            : _displayPath,
                      ),
                      AnimatedBuilder(
                        animation: _scan,
                        builder: (BuildContext context, Widget? child) {
                          return CustomPaint(
                            painter: ScanningPainter(
                              progress: _scan.value,
                              meshOpacity: failed ? 0.35 : 1,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 2),
              if (failed)
                _FailurePanel(
                  message:
                      controller.errorMessage ?? 'The scan could not finish.',
                  onRetake: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            ProcessingScreen(imagePath: widget.imagePath),
                      ),
                    );
                  },
                  onBack: () => Navigator.of(context).maybePop(),
                )
              else
                _ProgressPanel(step: _steps[_step]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoBackdrop extends StatelessWidget {
  const _PhotoBackdrop({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.file(
          File(path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[AppColors.surfaceHigh, AppColors.surface],
                    ),
                  ),
                );
              },
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.46)),
      ],
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.step});

  final String step;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            step,
            key: ValueKey<String>(step),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: const LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: AppColors.surfaceHigh,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Everything runs on this phone.\nNo photo leaves the device.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.6,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.message,
    required this.onRetake,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetake;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Icon(
          Icons.face_retouching_off_rounded,
          size: 26,
          color: AppColors.amber,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onRetake,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
