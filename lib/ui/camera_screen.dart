import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'processing_screen.dart';
import 'theme.dart';
import 'widgets/face_guide_painter.dart';

/// Live camera with a face-silhouette guide.
///
/// Stills, not video frames: one high-resolution photo gives MediaPipe far more
/// pixels per feature than a preview stream, and the maths is a one-shot
/// calculation. Live preview analysis would trade accuracy for motion feedback
/// this app does not need.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse;
  CameraController? _camera;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _cameraIndex = 0;
  bool _starting = true;
  bool _capturing = false;
  bool _torchOn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
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
    } on CameraException catch (error) {
      _fail(_friendlyError(error));
    } on Exception catch (error) {
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
    } on CameraException catch (error) {
      await controller.dispose();
      _fail(_friendlyError(error));
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _camera = controller;
      _starting = false;
      _torchOn = false;
    });
  }

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
    } on CameraException catch (error) {
      _fail(_friendlyError(error));
    }

    if (!mounted) {
      return;
    }

    if (capturedPath == null) {
      setState(() => _capturing = false);
      return;
    }

    final String path = capturedPath;

    // Release the camera while ML Kit works: two heavy camera-adjacent
    // pipelines at once is how mid-range phones start dropping frames.
    setState(() {
      _camera = null;
      _capturing = false;
      _starting = true;
    });
    await camera.dispose();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ProcessingScreen(imagePath: path),
      ),
    );

    if (mounted) {
      await _startCamera();
    }
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
    await previous?.dispose();
    await _startCamera();
  }

  Future<void> _toggleTorch() async {
    final CameraController? camera = _camera;
    if (camera == null) {
      return;
    }
    final bool next = !_torchOn;
    try {
      await camera.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() => _torchOn = next);
      }
    } on CameraException catch (error) {
      _fail(_friendlyError(error));
    }
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

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _starting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? camera = _camera;
    final bool ready = camera != null && camera.value.isInitialized;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (ready)
            _CameraPreview(controller: camera)
          else
            const _PreviewPlaceholder(),
          if (ready)
            AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: FaceGuidePainter(
                    pulse: Curves.easeInOut.transform(_pulse.value),
                    lineColor: AppColors.textPrimary,
                  ),
                );
              },
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: <Widget>[
                    _CircleButton(
                      icon: Icons.flip_camera_ios_rounded,
                      tooltip: 'Switch camera',
                      onPressed: ready && _cameras.length > 1
                          ? () => unawaited(_switchCamera())
                          : null,
                    ),
                    const Spacer(),
                    Column(
                      children: <Widget>[
                        const Text(
                          'FACE GEOMETRY',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          ready
                              ? 'ON-DEVICE  ·  NOTHING UPLOADED'
                              : 'PREPARING CAMERA',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.3,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _CircleButton(
                      icon: _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      tooltip: 'Torch',
                      onPressed: ready ? () => unawaited(_toggleTorch()) : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_error != null) ...<Widget>[
                      _ErrorBanner(
                        message: _error!,
                        onRetry: () => unawaited(_bootstrap()),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_error == null) ...<Widget>[
                      const _GuideHint(),
                      const SizedBox(height: 22),
                      _ShutterButton(
                        busy: _starting || !ready,
                        onPressed: ready && !_capturing && !_starting
                            ? () => unawaited(_capture())
                            : null,
                      ),
                    ],
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

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final Size preview = controller.value.previewSize ?? const Size(1080, 1920);
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

class _GuideHint extends StatelessWidget {
  const _GuideHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
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
