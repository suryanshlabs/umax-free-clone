import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/error_logger.dart';
import '../core/facial_analysis_service.dart';
import '../ml/exif_orientation.dart';
import '../ml/face_mesh_source.dart';
import '../ml/mediapipe_scan_source.dart';
import '../ml/mediapipe_types.dart';
import '../ml/photo_prep.dart';
import 'processing_screen.dart';
import 'theme.dart';
import '../ml/mediapipe_types.dart'
    show MediaPipeAttachedReading, MediaPipeScanReading, CaptureView, ViewStatus;


// ---------------------------------------------------------------------------
// Three-view MediaPipe Face Scan screen.
//
// Real camera flow on the same pattern as the existing ML Kit scanner:
//   1. Live camera preview with a view-specific guide overlay.
//   2. On "Capture": release the camera, save the high-res JPEG, run MediaPipe
//      detection on the prepared square, validate pose/quality.
//   3. Store the validated result in the three-view session.
//   4. When all three views are accepted, jump to the report.
//
// What is real here:
//   - A real [CameraController] at veryHigh JPEG resolution.
//   - One photo per view, with the camera disposed before detection.
//   - Real MediaPipe detection through [MediaPipeScanSource], which owns a
//     [MediapipeFaceLandmarkerWrapper].
//   - EXIF handling, orientation-correct geometry, square-crop prep.
//   - Per-view quality signals: face size, landmark count, pose, blendshapes.
//
// What is intentionally future work:
//   - The dedicated MediaPipe Simple/Advanced report screens. The session jumps
//     to the existing [ResultsScreen] using the [FaceMeshReading] the scanner
//     also produces, so a MediaPipe scan can already be scored by the existing
//     engine and shown in the existing results UI. The side views' MediaPipe data
//     is retained in this session object for a future MediaPipe report screen.
// ---------------------------------------------------------------------------

class MediaPipeFaceScanScreen extends StatefulWidget {
  const MediaPipeFaceScanScreen({super.key});

  @override
  State<MediaPipeFaceScanScreen> createState() =>
      _MediaPipeFaceScanScreenState();
}

class _MediaPipeFaceScanScreenState extends State<MediaPipeFaceScanScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse;

  CameraController? _camera;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _cameraIndex = 0;
  bool _starting = true;
  bool _capturing = false;
  bool _torchOn = false;
  String? _error;

  // ---- session state ----

  CaptureView _currentView = CaptureView.front;

  // One result object per view.
  final Map<CaptureView, ViewResult> _viewResults = <CaptureView, ViewResult>{
    CaptureView.front: const ViewResult(status: ViewStatus.pending),
    CaptureView.left34: const ViewResult(status: ViewStatus.pending),
    CaptureView.right34: const ViewResult(status: ViewStatus.pending),
  };

  // The scanner source, reused across all three views.
  late final MediaPipeScanSource _scanner = MediaPipeScanSource();
  bool _scannerDisposed = false;

  // True while the session is handing over to the analysis screen, so the
  // capture view is never swapped for the summary in between.
  bool _navigationPending = false;

  /// Where the session is: taking the three photos, reading them, or reporting
  /// what went wrong.
  _ScanPhase _phase = _ScanPhase.capturing;

  /// The order the views are photographed and read in.
  static const List<CaptureView> _captureOrder = <CaptureView>[
    CaptureView.front,
    CaptureView.left34,
    CaptureView.right34,
  ];

  /// Raw camera file per view. Filled while capturing, replaced by the prepared
  /// square once MediaPipe has read the view.
  final Map<CaptureView, String> _shots = <CaptureView, String>{};

  /// The view MediaPipe is reading right now, and how far the pass has got.
  CaptureView? _analysingView;
  int _analysedCount = 0;
  int _analyseTotal = 3;

  /// The view captured a moment ago, so the strip and the hint can confirm it
  /// before the guide asks for the next angle.
  CaptureView? _justCaptured;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    final CameraController? camera = _camera;
    _camera = null;
    unawaited(camera?.dispose());
    if (!_scannerDisposed) {
      _scannerDisposed = true;
      unawaited(_scanner.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final CameraController? camera = _camera;
      if (camera != null) {
        _camera = null;
        unawaited(camera.dispose());
        if (mounted) {
          setState(() => _starting = true);
        }
      }
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        _cameras.isNotEmpty) {
      unawaited(_startCamera());
    }
  }

  // ---- bootstrap ----

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('This device did not report any cameras.');
        return;
      }
      _cameras = cameras;
      final int front = cameras.indexWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = front >= 0 ? front : 0;
      await _startCamera();
    } on CameraException catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      _fail(_friendlyError(error));
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      _fail('The camera could not be started. $error');
    }
  }

  /// How many times [initialize] is tried before the camera is called broken.
  static const int _cameraAttempts = 3;

  Future<void> _startCamera() async {
    if (_cameras.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }

    // A failed first attempt is usually transient: on several Android builds
    // the previous screen's camera session is still being released when this
    // screen asks for the camera, so `initialize()` throws once and succeeds a
    // moment later. Retrying keeps the working camera the user sees from being
    // preceded by an error message, and only a failure that survives every
    // attempt is logged and shown.
    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 1; attempt <= _cameraAttempts; attempt++) {
      final CameraController controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await controller.initialize();
        if (!mounted) {
          await _disposeQuietly(controller);
          return;
        }
        setState(() {
          _camera = controller;
          _starting = false;
          _torchOn = false;
          _error = null;
        });
        return;
      } on Object catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        await _disposeQuietly(controller);
        if (attempt == _cameraAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 220 * attempt));
        if (!mounted) {
          return;
        }
      }
    }

    final Object error = lastError ?? 'The camera did not start.';
    ErrorLogger.instance.logError(
      error,
      lastStackTrace ?? StackTrace.current,
      source: ErrorLogSource.camera,
      context: <String, Object?>{'attempts': _cameraAttempts},
    );
    _fail(
      error is CameraException
          ? _friendlyError(error)
          : 'The camera could not be started (${error.runtimeType}).',
    );
  }

  // ---- capture ----

  Future<void> _capture() async {
    final CameraController? camera = _camera;
    final CaptureView view = _currentView;
    if (camera == null ||
        _capturing ||
        !camera.value.isInitialized ||
        view == CaptureView.complete) {
      return;
    }

    setState(() => _capturing = true);

    String? capturedPath;
    try {
      final XFile photo = await camera.takePicture();
      capturedPath = photo.path;
    } on CameraException catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      _fail(_friendlyError(error));
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      _fail('The photo could not be taken (${error.runtimeType}). Try again.');
    }

    if (!mounted) {
      return;
    }

    if (capturedPath == null) {
      setState(() => _capturing = false);
      return;
    }

    // The camera stays open: all three photos are taken first, and MediaPipe
    // only runs once the set is complete. That keeps the preview alive between
    // angles instead of dropping to a black screen after every shot.
    setState(() {
      _capturing = false;
      _error = null;
      _shots[view] = capturedPath!;
      _viewResults[view] = ViewResult(
        status: ViewStatus.captured,
        photoPath: capturedPath,
      );
      _justCaptured = view;
    });

    final bool haveAll = _captureOrder.every(
      (CaptureView v) => _shots.containsKey(v),
    );

    // Leave the confirmation on screen long enough to be seen before the guide
    // moves on.
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) {
      return;
    }
    setState(() => _justCaptured = null);

    if (haveAll) {
      await _startAnalysis();
      return;
    }

    _advance();
  }

  // ---- analysis pass ----

  /// Close the camera and read every captured view, one at a time, with visible
  /// progress. Called once all three photos exist.
  Future<void> _startAnalysis() async {
    final CameraController? camera = _camera;
    final int pending = _captureOrder
        .where((CaptureView v) => _viewResults[v]?.status != ViewStatus.accepted)
        .length;

    setState(() {
      _phase = _ScanPhase.analysing;
      _camera = null;
      _starting = true;
      _capturing = false;
      _error = null;
      _analysingView = null;
      _analysedCount = 0;
      _analyseTotal = pending == 0 ? 1 : pending;
    });

    await _disposeQuietly(camera);
    if (!mounted) {
      return;
    }
    await _analyseShots();
  }

  /// MediaPipe reads each view in turn. Views already accepted are skipped, so
  /// retaking one angle does not redo the other two.
  Future<void> _analyseShots() async {
    for (final CaptureView view in _captureOrder) {
      final String? path = _shots[view];
      if (path == null) {
        continue;
      }
      if (_viewResults[view]?.status == ViewStatus.accepted) {
        continue;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _analysingView = view;
        _viewResults[view] = ViewResult(
          status: ViewStatus.analysing,
          photoPath: path,
        );
      });
      await _analyseShot(view, path);
      if (!mounted) {
        return;
      }
      setState(() {
        _analysedCount += 1;
        _analysingView = null;
      });
    }

    if (!mounted) {
      return;
    }

    final bool allAccepted = _captureOrder.every(
      (CaptureView v) => _viewResults[v]?.status == ViewStatus.accepted,
    );

    if (allAccepted) {
      await _generateReport();
      return;
    }

    // Something was rejected: show what passed, what did not, and let the user
    // retake just that angle.
    setState(() => _phase = _ScanPhase.summary);
  }

  /// Read one captured view and store the result. Never throws: a rejected view
  /// is a state, not a crash.
  Future<void> _analyseShot(CaptureView view, String path) async {
    try {
      // Prepare the photo (upright, 1080x1080 square) for detection.
      final PreparedPhoto photo = await const PhotoPreparer().preparePath(path);

      // Run MediaPipe. This gives us both a [FaceMeshReading] (for the existing
      // pipeline) and the full MediaPipe result.
      final MediaPipeAttachedReading? attached = await _scanner.readAttached(
        photo.path,
        imageAspectRatio: 1.0,
      );
      if (!mounted) {
        return;
      }
      if (attached == null) {
        setState(() {
          _shots.remove(view);
          _viewResults[view] = ViewResult(
            status: ViewStatus.rejected,
            errorMessage:
                'No face in the ${_viewName(view)} view. Fill the guide and '
                'retake it in even light.',
            photoPath: path,
          );
        });
        return;
      }

      final ViewResult result = ViewResult(
        status: ViewStatus.accepted,
        photoPath: photo.path,
        meshReading: attached.meshReading,
        mediaPipeReading: MediaPipeScanReading(
          view: view,
          mediaPipeResult: attached.mediaPipeReading.mediaPipeResult,
          imageAspectRatio: attached.mediaPipeReading.imageAspectRatio,
          imageHeight: attached.mediaPipeReading.imageHeight,
        ),
        exifOrientation: photo.orientation,
        sourceWidth: photo.sourceWidth,
        sourceHeight: photo.sourceHeight,
      );

      setState(() {
        _viewResults[view] = result;
        _shots[view] = photo.path;
      });
    } on FacialAnalysisException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _shots.remove(view);
        _viewResults[view] = ViewResult(
          status: ViewStatus.rejected,
          errorMessage: error.message,
          photoPath: path,
        );
      });
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.facemesh,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _shots.remove(view);
        _viewResults[view] = ViewResult(
          status: ViewStatus.rejected,
          errorMessage: 'Analysis failed (${error.runtimeType})',
          photoPath: path,
        );
      });
    }
  }

  /// Take a single view again from the summary screen.
  void _retakeView(CaptureView view) {
    setState(() {
      _phase = _ScanPhase.capturing;
      _currentView = view;
      _viewResults[view] = const ViewResult(status: ViewStatus.pending);
      _shots.remove(view);
      _analysingView = null;
      _error = null;
      _starting = true;
    });
    unawaited(_startCamera());
  }

  void _advance() {
    switch (_currentView) {
      case CaptureView.front:
        setState(() => _currentView = CaptureView.left34);
        break;
      case CaptureView.left34:
        setState(() => _currentView = CaptureView.right34);
        break;
      case CaptureView.right34:
        setState(() => _currentView = CaptureView.complete);
        break;
      case CaptureView.complete:
        break;
    }
  }

  // ---- retake / cancel ----

  void _retakeCurrent() {
    setState(() {
      _viewResults[_currentView] = const ViewResult(status: ViewStatus.pending);
    });
    // Restart the camera for this view.
    unawaited(_startCamera());
  }

  void _cancelSession() {
    _resetSession();
    unawaited(_startCamera());
  }

  void _startNewSession() {
    _resetSession();
    unawaited(_startCamera());
  }

  void _resetSession() {
    setState(() {
      _phase = _ScanPhase.capturing;
      _currentView = CaptureView.front;
      for (final CaptureView key in _viewResults.keys) {
        _viewResults[key] = const ViewResult(status: ViewStatus.pending);
      }
      _shots.clear();
      _analysingView = null;
      _analysedCount = 0;
      _justCaptured = null;
      _navigationPending = false;
      _error = null;
      _starting = true;
    });
  }

  // ---- navigation ----

  Future<void> _generateReport() async {
    // Validate that all three views are accepted.
    final bool complete = [
      _viewResults[CaptureView.front],
      _viewResults[CaptureView.left34],
      _viewResults[CaptureView.right34],
    ].every((ViewResult? r) => r != null && r.status == ViewStatus.accepted);

    if (!complete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Capture all three views to generate a report.')),
      );
      return;
    }

    // The existing pipeline is driven by [AnalysisController.analyse(path)].
    // We hand it the front view's prepared square, which is enough for the
    // existing scoring engine to produce a report from the front view's
    // landmarks. The side views' MediaPipe data is retained in this session
    // object and can feed a future MediaPipe report screen.
    final ViewResult front = _viewResults[CaptureView.front]!;
    if (front.photoPath == null) {
      return;
    }

    if (!mounted || _navigationPending) {
      return;
    }
    setState(() => _navigationPending = true);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ProcessingScreen(imagePath: front.photoPath!),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _ScanPhase.analysing:
        return _buildAnalysingBody();
      case _ScanPhase.summary:
        return _buildCompleteBody();
      case _ScanPhase.capturing:
        break;
    }
    final CameraController? camera = _camera;
    final bool ready = camera != null && camera.value.isInitialized;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('MediaPipe Face Scan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel session',
          onPressed: _cancelSession,
        ),
        actions: [
          TextButton(
            onPressed:
                _camera != null && !_capturing && !_starting ? _retakeCurrent : null,
            child: const Text('Retake'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Live camera preview.
          if (ready)
            _CameraPreview(controller: camera)
          else
            const _PreviewPlaceholder(),

          // Guide overlay drawn over the whole preview.
          if (ready) _GuideOverlay(view: _currentView, pulse: _pulse),

          // Top bar: title, view counter and the three-view progress strip.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Flexible(
                          child: Text(
                            'MEDIAPIPE FACE SCAN',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _viewLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ProgressStrip(
                      current: _currentView,
                      views: _viewResults,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom stack: any message, then the capture controls.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _ErrorBanner(
                        message: _error!,
                        onRetry: () => unawaited(_bootstrap()),
                      ),
                    ),
                  if (_error == null &&
                      _viewResults[_currentView]?.status == ViewStatus.rejected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _ViewStatusCard(
                        result: _viewResults[_currentView] ??
                            const ViewResult(status: ViewStatus.pending),
                      ),
                    ),
                  _BottomBar(
                    starting: _starting,
                    capturing: _capturing,
                    ready: ready,
                    hint: _hintText(),
                    onCapture:
                        ready && !_capturing && !_starting ? _capture : null,
                    onCancel: _cancelSession,
                    onSwitch: _cameras.length > 1 ? _switchCamera : null,
                    torchOn: _torchOn,
                    onTorch: ready ? _toggleTorch : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Visible progress for the MediaPipe pass, so nobody is left looking at a
  /// frozen screen wondering whether anything is happening.
  Widget _buildAnalysingBody() {
    final double progress =
        (_analyseTotal == 0 ? 0.0 : _analysedCount / _analyseTotal)
            .clamp(0.0, 1.0);
    final CaptureView? view = _analysingView;
    final String label = view == null
        ? (_analysedCount >= _analyseTotal
            ? 'Finishing the report…'
            : 'Preparing the photos…')
        : 'Analysing ${_viewName(view).toLowerCase()} view'
            ' ${(_analysedCount + 1).clamp(1, _analyseTotal)} of $_analyseTotal';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'MEDIAPIPE FACE SCAN',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 132,
                  height: 132,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          backgroundColor: AppColors.surfaceHigh,
                          color: AppColors.accent,
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Reading 478 landmarks on each photo. This takes a few '
                    'seconds — keep the app open.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              for (final CaptureView view in _captureOrder)
                _CompleteRow(
                  view: view,
                  label: _viewName(view),
                  result: _viewResults[view] ??
                      const ViewResult(status: ViewStatus.pending),
                ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _startNewSession,
                  child: const Text('Start over'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompleteBody() {
    final bool allAccepted = _captureOrder.every(
      (CaptureView v) => _viewResults[v]?.status == ViewStatus.accepted,
    );
    final int rejected = _captureOrder
        .where((CaptureView v) => _viewResults[v]?.status != ViewStatus.accepted)
        .length;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.1,
              colors: <Color>[AppColors.surfaceHigh, AppColors.background],
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  allAccepted ? 'Scan Complete' : 'Scan Incomplete',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  allAccepted
                      ? 'All three views passed. Generate the report below.'
                      : rejected == 1
                          ? 'One view could not be read. Retake just that '
                              'angle and the report can be generated.'
                          : '$rejected views could not be read. Retake them and '
                              'the report can be generated.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                for (final CaptureView view in _captureOrder)
                  _CompleteRow(
                    view: view,
                    label: _viewName(view),
                    result: _viewResults[view] ??
                        const ViewResult(status: ViewStatus.pending),
                    onRetake: _viewResults[view]?.status == ViewStatus.accepted
                        ? null
                        : () => _retakeView(view),
                  ),
                const SizedBox(height: 24),
                if (allAccepted)
                  FilledButton(
                    onPressed: _generateReport,
                    child: const Text('Generate Report'),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _startNewSession,
                  child: const Text('Start new session'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _viewName(CaptureView view) {
    return switch (view) {
      CaptureView.front => 'Front',
      CaptureView.left34 => 'Left 3/4',
      CaptureView.right34 => 'Right 3/4',
      CaptureView.complete => 'All views',
    };
  }

  /// The one-line instruction under the preview: what to do right now.
  String _hintText() {
    final CaptureView? just = _justCaptured;
    if (just != null) {
      return '${_viewName(just)} captured · ${_nextPrompt(just)}';
    }
    return switch (_currentView) {
      CaptureView.front => 'Look straight ahead · fill the guide · eyes level',
      CaptureView.left34 => 'Turn your head slightly left · keep eyes level',
      CaptureView.right34 => 'Turn your head slightly right · keep eyes level',
      CaptureView.complete => 'All three views captured',
    };
  }

  String _nextPrompt(CaptureView captured) {
    return switch (captured) {
      CaptureView.front => 'now turn slightly to your left',
      CaptureView.left34 => 'now turn slightly to your right',
      CaptureView.right34 => 'analysing all three views…',
      CaptureView.complete => 'analysing all three views…',
    };
  }

  String _viewLabel() {
    return switch (_currentView) {
      CaptureView.front => 'View 1 of 3',
      CaptureView.left34 => 'View 2 of 3',
      CaptureView.right34 => 'View 3 of 3',
      CaptureView.complete => 'Complete',
    };
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      return;
    }
    final CameraController? previous = _camera;
    setState(() {
      _camera = null;
      _starting = true;
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    });
    await _disposeQuietly(previous);
    await _startCamera();
  }

  Future<void> _toggleTorch() async {
    final CameraController? camera = _camera;
    if (camera == null) {
      return;
    }
    final bool next = !_torchOn;
    try {
      await camera.setFlashMode(
          next ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() => _torchOn = next);
      }
    } on CameraException catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      _fail(_friendlyError(error));
    }
  }

  // ---- helpers (copied from existing camera_screen.dart) ----

  Future<void> _disposeQuietly(CameraController? controller) async {
    if (controller == null) {
      return;
    }
    try {
      await controller.dispose();
    } on Object catch (error) {
      ErrorLogger.instance.logWarning(
        'Camera dispose failed (ignored): $error',
        source: ErrorLogSource.camera,
      );
      debugPrint('Camera dispose failed (ignored): $error');
    }
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _starting = false;
    });
  }

  String _friendlyError(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera access is off. Open Settings → Apps → Face Geometry → '
            'Permissions, allow the camera, then come back.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return 'The camera could not start (${error.code}). Close any other '
            'app using the camera and try again.';
    }
  }
}

// ------------------------------------------------------- view result model

class ViewResult {
  const ViewResult({
    this.status = ViewStatus.pending,
    this.photoPath,
    this.meshReading,
    this.mediaPipeReading,
    this.exifOrientation = ExifOrientation.unknown,
    this.sourceWidth,
    this.sourceHeight,
    this.errorMessage,
  });

  final ViewStatus status;
  final String? photoPath;
  final FaceMeshReading? meshReading;
  final MediaPipeScanReading? mediaPipeReading;
  final ExifOrientation exifOrientation;
  final int? sourceWidth;
  final int? sourceHeight;
  final String? errorMessage;
}

// ------------------------------------------------------- camera preview widget

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final Size preview = controller.value.previewSize ??
        const Size(1080, 1920);
    // previewSize is reported in the sensor's landscape orientation while this
    // app runs portrait, so the axes are swapped before cover-fitting.
    final double width = math.max(preview.height, 1);
    final double height = math.max(preview.width, 1);
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: width,
            height: height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    // A black rectangle looks like a broken camera. Say what is happening
    // instead, so a slow start reads as loading rather than as a failure.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.1,
          colors: <Color>[AppColors.surfaceHigh, AppColors.background],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Starting the camera…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The first start can take a second.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- guide overlay

class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay({
    required this.view,
    required this.pulse,
  });

  final CaptureView view;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final (String title, String body, double shift) = switch (view) {
      CaptureView.front => (
          'Front view',
          'Face the camera directly. Eyes level, neutral expression, whole face inside the oval.',
          0.0,
        ),
      CaptureView.left34 => (
          'Left 3/4',
          'Turn your head slightly to your left. Eyes level, chin centred, ear still visible.',
          -0.12,
        ),
      CaptureView.right34 => (
          'Right 3/4',
          'Turn your head slightly to your right. Eyes level, chin centred, ear still visible.',
          0.12,
        ),
      CaptureView.complete => ('', '', 0.0),
    };

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: pulse,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _GuidePainter(
              title: title,
              body: body,
              shift: shift,
              pulse: Curves.easeInOut.transform(pulse.value),
            ),
          );
        },
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.title,
    required this.body,
    required this.shift,
    required this.pulse,
  });

  final String title;
  final String body;
  final double shift;
  final double pulse;

  /// The oval the user is asked to fill, derived from the preview size so it
  /// lands on the face on every screen instead of a fixed pixel position.
  static Rect guideRect(Size size, double shift) {
    final double width = math.min(size.width * 0.72, size.height * 0.42);
    final double height = width * 1.30;
    return Rect.fromCenter(
      center: Offset(
        size.width * (0.5 + shift),
        size.height * 0.40,
      ),
      width: width,
      height: height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final Rect guide = guideRect(size, shift);

    // Dim everything outside the oval. The face stays the brightest thing on
    // screen, and the instruction copy underneath stays readable whether the
    // camera is looking at a bright wall or a dark room.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(guide),
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );

    // Breathing outline.
    canvas.drawOval(
      guide,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = AppColors.accent.withValues(alpha: 0.55 + 0.25 * pulse),
    );

    // Eye line and vertical midline.
    _dash(
      canvas,
      Offset(guide.left + guide.width * 0.16, guide.top + guide.height * 0.40),
      Offset(guide.right - guide.width * 0.16, guide.top + guide.height * 0.40),
      Colors.white.withValues(alpha: 0.22),
    );
    _dash(
      canvas,
      Offset(guide.center.dx, guide.top + guide.height * 0.08),
      Offset(guide.center.dx, guide.bottom - guide.height * 0.10),
      Colors.white.withValues(alpha: 0.18),
    );

    // Instruction copy, pinned just under the oval and above the controls.
    final double maxTextWidth = math.max(size.width - 32, 120);
    final double textTop = math.min(
      guide.bottom + 16,
      size.height - 250,
    );

    if (title.isNotEmpty) {
      final TextPainter titlePainter = TextPainter(
        text: TextSpan(
          text: title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: AppColors.textPrimary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxTextWidth);
      titlePainter.paint(canvas, Offset(16, math.max(textTop, 0)));

      final TextPainter bodyPainter = TextPainter(
        text: TextSpan(
          text: body,
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxTextWidth);
      bodyPainter.paint(
        canvas,
        Offset(16, math.max(textTop, 0) + titlePainter.height + 4),
      );
    }
  }

  void _dash(Canvas canvas, Offset from, Offset to, Color color) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const double dash = 6;
    const double gap = 8;
    final double total = (to - from).distance;
    if (total <= 0) {
      return;
    }
    final Offset step = (to - from) / total;
    double travelled = 0;
    while (travelled < total) {
      final double end = math.min(travelled + dash, total);
      canvas.drawLine(from + step * travelled, from + step * end, paint);
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) {
    return old.pulse != pulse ||
        old.title != title ||
        old.body != body ||
        old.shift != shift;
  }
}

// ------------------------------------------------------- bottom bar

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.starting,
    required this.capturing,
    required this.ready,
    required this.hint,
    required this.onCapture,
    required this.onCancel,
    required this.onSwitch,
    required this.torchOn,
    required this.onTorch,
  });

  final bool starting;
  final bool capturing;
  final bool ready;
  final String hint;
  final VoidCallback? onCapture;
  final VoidCallback onCancel;
  final VoidCallback? onSwitch;
  final bool torchOn;
  final VoidCallback? onTorch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!capturing) _GuideHint(text: hint),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _CircleButton(
                icon: Icons.close_rounded,
                tooltip: 'Cancel session',
                onPressed: onCancel,
              ),
              _CircleButton(
                icon: Icons.flip_camera_ios_rounded,
                tooltip: 'Switch camera',
                onPressed: onSwitch,
              ),
              _ShutterButton(
                busy: starting || capturing || !ready,
                onPressed: onCapture,
              ),
              _CircleButton(
                icon: torchOn
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
                tooltip: 'Torch',
                onPressed: onTorch,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where a session is. The three photos are collected first, then MediaPipe
/// reads them in one visible pass, then anything rejected is reported for a
/// single-angle retake.
enum _ScanPhase { capturing, analysing, summary }

// ------------------------------------------------------- progress strip

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.current,
    required this.views,
  });

  final CaptureView current;
  final Map<CaptureView, ViewResult> views;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StripStep(
            label: 'Front',
            status: _statusFor(CaptureView.front),
            current: current == CaptureView.front,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StripStep(
            label: 'Left 3/4',
            status: _statusFor(CaptureView.left34),
            current: current == CaptureView.left34,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StripStep(
            label: 'Right 3/4',
            status: _statusFor(CaptureView.right34),
            current: current == CaptureView.right34,
          ),
        ),
      ],
    );
  }

  ViewStatus _statusFor(CaptureView view) {
    final ViewResult? r = views[view];
    if (r == null) return ViewStatus.pending;
    return r.status;
  }
}

class _StripStep extends StatelessWidget {
  const _StripStep({
    required this.label,
    required this.status,
    required this.current,
  });

  final String label;
  final ViewStatus status;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final bool accepted = status == ViewStatus.accepted;
    final bool captured = status == ViewStatus.captured;
    final bool done = accepted || captured;
    final bool busy = status == ViewStatus.analysing ||
        status == ViewStatus.capturing;
    final bool isActive = busy || ((status == ViewStatus.pending) && current);
    final Color color = accepted
        ? AppColors.mint
        : captured
            ? AppColors.accent
            : busy
                ? AppColors.accent
                : isActive
                    ? AppColors.accent
                    : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 12,
            height: 12,
            child: done
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accepted ? AppColors.mint : AppColors.accent,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 9,
                      color: AppColors.background,
                    ),
                  )
                : busy
                    ? CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: color,
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(alpha: 0.7),
                            width: 1.6,
                          ),
                        ),
                      ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.2,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- status card

class _ViewStatusCard extends StatelessWidget {
  const _ViewStatusCard({required this.result});

  final ViewResult result;

  @override
  Widget build(BuildContext context) {
    final Color tint;
    final String label;
    final String detail;

    switch (result.status) {
      case ViewStatus.accepted:
        tint = AppColors.mint;
        label = 'View accepted';
        final double fw = result.meshReading?.faceWidthFraction ?? 0;
        final double fh = result.meshReading?.faceHeightFraction ?? 0;
        detail =
            'Face filled ${_percent(fw * 100)} of frame width, '
            '${_percent(fh * 100)} of height.';
        break;
      case ViewStatus.analysing:
        tint = AppColors.accent;
        label = 'Analysing';
        detail = 'MediaPipe is reading the photo…';
        break;
      case ViewStatus.captured:
        tint = AppColors.accent;
        label = 'Captured';
        detail = 'Photo taken. MediaPipe reads all three views together at '
            'the end.';
        break;
      case ViewStatus.rejected:
        tint = AppColors.danger;
        label = 'View rejected';
        detail = result.errorMessage ?? 'Try again.';
        break;
      case ViewStatus.pending:
        tint = AppColors.textTertiary;
        label = 'Pending';
        detail = 'Capture to continue.';
        break;
      case ViewStatus.capturing:
        tint = AppColors.accent;
        label = 'Capturing';
        detail = 'Taking the photo…';
        break;
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
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

  static String _percent(double v) {
    if (!v.isFinite) return '—';
    return v.toStringAsFixed(0);
  }
}

// ------------------------------------------------------- complete rows

class _CompleteRow extends StatelessWidget {
  const _CompleteRow({
    required this.view,
    required this.label,
    required this.result,
    this.onRetake,
  });

  final CaptureView view;
  final String label;
  final ViewResult result;

  /// Present only when this view has to be taken again.
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final bool accepted = result.status == ViewStatus.accepted;
    final Color color = accepted ? AppColors.mint : AppColors.textTertiary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                  color: color.withValues(alpha: 0.5), width: 2),
            ),
            child: accepted
                ? const Icon(Icons.check_rounded, size: 7, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            switch (result.status) {
              ViewStatus.accepted => 'Accepted',
              ViewStatus.rejected => 'Rejected',
              ViewStatus.analysing => 'Analysing',
              ViewStatus.captured => 'Captured',
              ViewStatus.capturing => 'Capturing',
              ViewStatus.pending => 'Pending',
            },
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          if (onRetake != null) ...<Widget>[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onRetake,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'Retake',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------- shared UI bits

class _GuideHint extends StatelessWidget {
  const _GuideHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(99),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.wb_sunny_outlined,
            size: 14,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: onPressed == null
                  ? AppColors.textTertiary
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onPressed == null ? 0.6 : 1,
        child: SizedBox(
          width: 82,
          height: 82,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 2.5,
                  ),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Colors.white, Color(0xFFD8D9F0)],
                  ),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.background,
                        ),
                      )
                    : const Icon(
                        Icons.center_focus_strong_rounded,
                        color: AppColors.background,
                        size: 24,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.videocam_off_outlined,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}
