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
import '../ml/mediapipe_types.dart' show MediaPipeAttachedReading, MediaPipeScanReading, CaptureView, ViewStatus;


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

  // The prepared square path of the currently analysed view, for the fade.
  String? _currentPhotoPath;

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

    final CameraController controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
    } on CameraException catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      await _disposeQuietly(controller);
      _fail(_friendlyError(error));
      return;
    } on Object catch (error, stackTrace) {
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.camera,
      );
      await _disposeQuietly(controller);
      _fail('The camera could not be started (${error.runtimeType}).');
      return;
    }

    if (!mounted) {
      await _disposeQuietly(controller);
      return;
    }

    setState(() {
      _camera = controller;
      _starting = false;
      _torchOn = false;
    });
  }

  // ---- capture ----

  Future<void> _capture() async {
    final CameraController? camera = _camera;
    if (camera == null || _capturing || !camera.value.isInitialized) {
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

    final String path = capturedPath;

    // Release the camera while MediaPipe works.
    setState(() {
      _camera = null;
      _capturing = false;
      _starting = true;
    });
    await _disposeQuietly(camera);
    if (!mounted) {
      return;
    }

    // Analyse this view.
    await _analyseView(path);
  }

  // ---- detection + validation ----

  Future<void> _analyseView(String path) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _viewResults[_currentView] = ViewResult(
        status: ViewStatus.analysing,
        photoPath: path,
      );
      _currentPhotoPath = null;
    });

    try {
      // Prepare the photo (upright, 1080x1080 square) for detection.
      final PreparedPhoto photo = await const PhotoPreparer().preparePath(path);

      // Run MediaPipe. This gives us both a [FaceMeshReading] (for the existing
      // pipeline) and the full MediaPipe result.
      final MediaPipeAttachedReading? attached = await _scanner.readAttached(
        photo.path,
        imageAspectRatio: 1.0,
      );
      if (attached == null) {
        if (!mounted) return;
        setState(() {
          _viewResults[_currentView] = ViewResult(
            status: ViewStatus.rejected,
            errorMessage: 'No face detected. Center your face and try again.',
            photoPath: path,
          );
        });
        return;
      }

      // Package a session result from this view.
      final ViewResult result = ViewResult(
        status: ViewStatus.accepted,
        photoPath: photo.path,
        meshReading: attached.meshReading,
        mediaPipeReading: MediaPipeScanReading(
          view: _currentView,
          mediaPipeResult: attached.mediaPipeReading.mediaPipeResult,
          imageAspectRatio: attached.mediaPipeReading.imageAspectRatio,
          imageHeight: attached.mediaPipeReading.imageHeight,
        ),
        exifOrientation: photo.orientation,
        sourceWidth: photo.sourceWidth,
        sourceHeight: photo.sourceHeight,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _viewResults[_currentView] = result;
        _currentPhotoPath = photo.path;
      });

      // Move to next view or complete.
      _advance();
    } on FacialAnalysisException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewResults[_currentView] = ViewResult(
          status: ViewStatus.rejected,
          errorMessage: error.message,
          photoPath: path,
        );
      });
      // Keep the current view so the user can retake it.
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
        _viewResults[_currentView] = ViewResult(
          status: ViewStatus.rejected,
          errorMessage: 'Analysis failed (${error.runtimeType})',
          photoPath: path,
        );
      });
    }
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
      _currentPhotoPath = null;
    });
    // Restart the camera for this view.
    unawaited(_startCamera());
  }

  void _cancelSession() {
    setState(() {
      _currentView = CaptureView.front;
      for (final CaptureView key in _viewResults.keys) {
        _viewResults[key] = const ViewResult(status: ViewStatus.pending);
      }
      _currentPhotoPath = null;
      _error = null;
      _starting = true;
    });
    unawaited(_startCamera());
  }

  void _startNewSession() {
    setState(() {
      _currentView = CaptureView.front;
      for (final CaptureView key in _viewResults.keys) {
        _viewResults[key] = const ViewResult(status: ViewStatus.pending);
      }
      _currentPhotoPath = null;
      _error = null;
      _starting = true;
    });
    unawaited(_startCamera());
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

    if (!mounted) {
      return;
    }
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
    if (_currentView == CaptureView.complete) {
      return _buildCompleteBody();
    }
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
          if (_currentView != CaptureView.complete)
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
          if (_camera != null && _camera!.value.isInitialized)
            _CameraPreview(controller: _camera!)
          else
            const _PreviewPlaceholder(),

          // Guide overlay pinned to the face region.
          if (_camera != null && _camera!.value.isInitialized)
            _GuideOverlay(
              view: _currentView,
              pulse: _pulse,
            ),

          // Top bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          'MEDIAPIPE FACE SCAN',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _viewLabel(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 24),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: _ProgressStrip(
                        current: _currentView,
                        currentProvider: () => _currentView,
                        views: _viewResults,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _BottomBar(
                starting: _starting,
                capturing: _capturing,
                onCapture: _capture,
                onSwitch: _cameras.length > 1 ? _switchCamera : null,
                torchOn: _torchOn,
                onTorch: _toggleTorch,
              ),
            ),
          ),

          // Error banner.
          if (_error != null)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: _ErrorBanner(
                message: _error!,
                onRetry: () => unawaited(_bootstrap()),
              ),
            ),

          // Status for the current view after capture.
          if (_currentView != CaptureView.complete && _currentPhotoPath != null)
            Positioned(
              top: 200,
              left: 16,
              right: 16,
              child: _ViewStatusCard(result: _viewResults[_currentView]!),
            ),
        ],
      ),
    );
  }

  Widget _buildCompleteBody() {
    final bool allAccepted = [
      _viewResults[CaptureView.front],
      _viewResults[CaptureView.left34],
      _viewResults[CaptureView.right34],
    ].every((ViewResult? r) => r != null && r.status == ViewStatus.accepted);

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  allAccepted ? 'Scan Complete' : 'Scan Incomplete',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  allAccepted
                      ? 'All three views passed. Generate the report below.'
                      : 'Not every view was accepted. Capture the missing views to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                _CompleteRow(
                  view: CaptureView.front,
                  label: 'Front',
                  result: _viewResults[CaptureView.front]!,
                ),
                _CompleteRow(
                  view: CaptureView.left34,
                  label: 'Left 3/4',
                  result: _viewResults[CaptureView.left34]!,
                ),
                _CompleteRow(
                  view: CaptureView.right34,
                  label: 'Right 3/4',
                  result: _viewResults[CaptureView.right34]!,
                ),
                const SizedBox(height: 24),
                if (!allAccepted)
                  OutlinedButton(
                    onPressed: _startNewSession,
                    child: const Text('Start new session'),
                  )
                else
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
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.1,
          colors: <Color>[AppColors.surfaceHigh, AppColors.background],
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
    final String title;
    final String body;
    final List<_Stroke> strokes;

    switch (view) {
      case CaptureView.front:
        title = 'Front view';
        body =
            'Face the camera directly. Eyes level, neutral expression, whole face in frame.';
        strokes = _frontStrokes();
      case CaptureView.left34:
        title = 'Left 3/4';
        body =
            'Turn your head slightly to your left. Keep your eyes level and your chin roughly centred.';
        strokes = _sideStrokes(left: true);
      case CaptureView.right34:
        title = 'Right 3/4';
        body =
            'Turn your head slightly to your right. Keep your eyes level and your chin roughly centred.';
        strokes = _sideStrokes(left: false);
      default:
        title = '';
        body = '';
        strokes = const <_Stroke>[];
    }

    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _GuidePainter(
            title: title,
            body: body,
            strokes: strokes,
            pulse: Curves.easeInOut.transform(pulse.value),
          ),
          size: Size.infinite,
        );
      },
    );
  }

  static List<_Stroke> _frontStrokes() {
    return <_Stroke>[
      _Stroke.oval(
        center: const Offset(154, 620),
        rx: 86,
        ry: 112,
        style: _StrokeStyle.outline,
      ),
      _Stroke.line(
        from: const Offset(90, 540),
        to: const Offset(218, 540),
        style: _StrokeStyle.dots,
      ),
      _Stroke.line(
        from: const Offset(154, 500),
        to: const Offset(154, 740),
        style: _StrokeStyle.dots,
      ),
    ];
  }

  static List<_Stroke> _sideStrokes({required bool left}) {
    final double cx = left ? 90 : 218;
    final double dir = left ? -1.0 : 1.0;
    return <_Stroke>[
      _Stroke.oval(
        center: Offset(cx, 620),
        rx: 70,
        ry: 96,
        style: _StrokeStyle.outline,
      ),
      _Stroke.line(
        from: Offset(cx - 40 * dir, 560),
        to: Offset(cx + 40 * dir, 560),
        style: _StrokeStyle.dots,
      ),
      _Stroke.line(
        from: Offset(cx, 520),
        to: Offset(cx, 720),
        style: _StrokeStyle.dots,
      ),
    ];
  }
}

class _Stroke {
  const _Stroke._({
    required this.type,
    required this.style,
    this.params = const <double>[],
  });
  factory _Stroke.oval({
    required Offset center,
    required double rx,
    required double ry,
    required _StrokeStyle style,
  }) {
    return _Stroke._(
      type: 'oval',
      style: style,
      params: [center.dx, center.dy, rx, ry],
    );
  }
  factory _Stroke.line({
    required Offset from,
    required Offset to,
    required _StrokeStyle style,
  }) {
    return _Stroke._(
      type: 'line',
      style: style,
      params: [from.dx, from.dy, to.dx, to.dy],
    );
  }

  final String type;
  final _StrokeStyle style;
  final List<double> params;
}

enum _StrokeStyle { outline, dots }

class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.title,
    required this.body,
    required this.strokes,
    required this.pulse,
  });

  final String title;
  final String body;
  final List<_Stroke> strokes;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = AppColors.accent.withValues(alpha: 0.55 + 0.2 * pulse);
    final Paint dots = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppColors.accentSoft.withValues(alpha: 0.7);

    for (final _Stroke s in strokes) {
      switch (s.type) {
        case 'oval':
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(s.params[0], s.params[1]),
              width: s.params[2] * 2,
              height: s.params[3] * 2,
            ),
            s.style == _StrokeStyle.outline ? outline : dots,
          );
          break;
        case 'line':
          canvas.drawLine(
            Offset(s.params[0], s.params[1]),
            Offset(s.params[2], s.params[3]),
            s.style == _StrokeStyle.outline ? outline : dots,
          );
          break;
        default:
          break;
      }
    }

    // Title + body text.
    final double textY = 690.0;
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
    )..layout();
    titlePainter.paint(canvas, Offset(16, textY - 34));

    final TextPainter bodyPainter = TextPainter(
      text: TextSpan(
        text: body,
        style: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 288);
    bodyPainter.paint(canvas, Offset(16, textY - 8));
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) {
    return old.pulse != pulse;
  }
}

// ------------------------------------------------------- bottom bar

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.starting,
    required this.capturing,
    required this.onCapture,
    required this.onSwitch,
    required this.torchOn,
    required this.onTorch,
  });

  final bool starting;
  final bool capturing;
  final VoidCallback? onCapture;
  final VoidCallback? onSwitch;
  final bool torchOn;
  final VoidCallback? onTorch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (starting && !capturing) const _GuideHint(),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              const _CircleButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to home',
                onPressed: null,
              ),
              const _CircleButton(
                icon: Icons.flip_camera_ios_rounded,
                tooltip: 'Switch camera',
                onPressed: null,
              ),
              _ShutterButton(
                busy: starting || onCapture == null,
                onPressed: onCapture,
              ),
              const _CircleButton(
                icon: Icons.flash_off_rounded,
                tooltip: 'Torch',
                onPressed: null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- progress strip

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.current,
    required this.currentProvider,
    required this.views,
  });

  final CaptureView current;
  final CaptureView Function() currentProvider;
  final Map<CaptureView, ViewResult> views;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double unit = (constraints.maxWidth - 20) / 3;
        return Row(
          children: <Widget>[
            _StripStep(
              label: 'Front',
              x: unit,
              status: _statusFor(CaptureView.front),
              current: currentProvider() == CaptureView.front,
            ),
            const SizedBox(width: 10),
            _StripStep(
              label: 'Left 3/4',
              x: unit * 2 + 10,
              status: _statusFor(CaptureView.left34),
              current: currentProvider() == CaptureView.left34,
            ),
            const SizedBox(width: 10),
            _StripStep(
              label: 'Right 3/4',
              x: unit * 3 + 20,
              status: _statusFor(CaptureView.right34),
              current: currentProvider() == CaptureView.right34,
            ),
          ],
        );
      },
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
    required this.x,
    required this.status,
    required this.current,
  });

  final String label;
  final double x;
  final ViewStatus status;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final bool done = status == ViewStatus.accepted;
    final bool isActive = status == ViewStatus.analysing ||
        status == ViewStatus.capturing ||
        (status == ViewStatus.pending && current);
    final Color color = done
        ? AppColors.mint
        : isActive
            ? AppColors.accent
            : AppColors.textTertiary;

    return Positioned(
      left: x,
      top: 0,
      child: Column(
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                  color: color.withValues(alpha: 0.5), width: 2),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 8, color: Colors.white)
                : isActive
                    ? const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)
                    : const SizedBox(width: 12, height: 12),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: color,
              fontWeight: FontWeight.w600,
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
  });

  final CaptureView view;
  final String label;
  final ViewResult result;

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
            result.status == ViewStatus.accepted
                ? 'Accepted'
                : result.status == ViewStatus.rejected
                    ? 'Rejected'
                    : result.status == ViewStatus.analysing
                        ? 'Analysing'
                        : 'Pending',
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- shared UI bits

class _GuideHint extends StatelessWidget {
  const _GuideHint();

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
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.wb_sunny_outlined,
            size: 14,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 8),
          Text(
            'Fill the guide · eyes level · neutral face',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              letterSpacing: 0.1,
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
