import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

// MediaPipe Face Landmarker result types
enum CaptureView { front, left34, right34, complete }

/// Screen for MediaPipe-based three-view facial geometry analysis.
///
/// Supports three sequential capture views:
/// 1. Front - user faces the camera directly
/// 2. Left 3/4 - user turns head slightly to the left
/// 3. Right 3/4 - user turns head slightly to the right
///
/// After all three views are captured, a geometry analysis report is generated
/// and the user can view results or start a new session.
class MediaPipeFaceScanScreen extends StatefulWidget {
  const MediaPipeFaceScanScreen({super.key});

  @override
  State<MediaPipeFaceScanScreen> createState() =>
      _MediaPipeFaceScanScreenState();
}

/// State managing the three-view capture lifecycle.
class _MediaPipeFaceScanScreenState extends State<MediaPipeFaceScanScreen> {
  CaptureView _currentView = CaptureView.front;

  // Results from each view, stored by view identifier
  Map<CaptureView, dynamic> _viewResults = {
    CaptureView.front: null,
    CaptureView.left34: null,
    CaptureView.right34: null,
  };

  // Quality status for each view
  Map<CaptureView, String?> _viewQuality = {
    CaptureView.front: null,
    CaptureView.left34: null,
    CaptureView.right34: null,
  };

  bool _isProcessing = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _nextView() {
    switch (_currentView) {
      case CaptureView.front:
        _viewQuality[CaptureView.front] = 'Good';
        _currentView = CaptureView.left34;
        return true;

      case CaptureView.left34:
        _viewQuality[CaptureView.left34] = 'Good';
        _currentView = CaptureView.right34;
        return true;

      case CaptureView.right34:
        _currentView = CaptureView.complete;
        return false;

      case CaptureView.complete:
        return false;
    }
  }

  void _retakeCurrent() {
    setState(() {
      _viewResults[_currentView] = null;
      _viewQuality[_currentView] = null;
    });
  }

  void _cancelSession() {
    setState(() {
      _currentView = CaptureView.front;
      _viewResults = {
        CaptureView.front: null,
        CaptureView.left34: null,
        CaptureView.right34: null,
      };
      _viewQuality = {
        CaptureView.front: null,
        CaptureView.left34: null,
        CaptureView.right34: null,
      };
    });
  }

  Widget build(BuildContext context) {
    final String progressLabel =
        _currentView == CaptureView.front
            ? 'Front'
            : _currentView == CaptureView.left34
                ? 'Left 3/4'
                : _currentView == CaptureView.right34
                    ? 'Right 3/4'
                    : 'Complete';

    return Scaffold(
      appBar: AppBar(
        title: const Text('MediaPipe Face Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel session',
            onPressed: _cancelSession,
          ),
        ],
      ),
      body: _buildBody(progressLabel),
    );
  }

  Widget _buildBody(String progressLabel) {
    switch (_currentView) {
      case CaptureView.front:
        return _buildFrontView();

      case CaptureView.left34:
        return _buildSideView(
          title: 'Left 3/4',
          description: 'Turn your head slightly to the left',
        );

      case CaptureView.right34:
        return _buildSideView(
          title: 'Right 3/4',
          description: 'Turn your head slightly to the right',
        );

      case CaptureView.complete:
        return _buildCompleteScreen();
    }
  }

  Widget _buildFrontView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Front ✓ → Left 3/4 → Right 3/4',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Camera Preview Area\n(Front view capture)',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _PoseGuide(
            title: 'Face the camera directly',
            description:
                'Look straight at the camera with a neutral expression. '
                'Ensure your face is fully visible within the frame.',
            targetPose: PoseGuide.targetNeutral,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isProcessing ? null : () {
              // Simulate capture - move to next view after delay
              Future.delayed(const Duration(milliseconds: 800), () {
                if (!mounted) return;
                setState(() => _nextView());
              });
            },
            child: _isProcessing
                ? const CircularProgressIndicator()
                : const Text('Capture Front'),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildSideView({
    required String title,
    required String description,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Front ✓ → $title → Right 3/4',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Camera Preview Area\n(Side view capture)',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _PoseGuide(
            title: title,
            description: description,
            targetPose: PoseGuide.targetTurnedSide(
              direction: 0,
              degrees: 20,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isProcessing ? null : () {
              Future.delayed(const Duration(milliseconds: 800), () {
                if (!mounted) return;
                setState(() => _nextView());
              });
            },
            child: _isProcessing
                ? const CircularProgressIndicator()
                : Text('Capture $title'),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildCompleteScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            'Scan Complete!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'All three views have been captured successfully.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: null,
            child: const Text('Generate Report'),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: null,
                child: const Text('Start New Session'),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: null,
                child: const Text('Retake Current'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PoseGuide {
  static PoseTarget targetNeutral = PoseTarget(
    minYaw: -10,
    maxYaw: 10,
    minPitch: -10,
    maxPitch: 10,
    minRoll: -5,
    maxRoll: 5,
  );

  static PoseTarget targetTurnedSide({
    required double direction,
    required double degrees,
  }) {
    final isLeft = direction < 0;
    final absDir = direction.abs();
    return PoseTarget(
      minYaw: absDir - degrees,
      maxYaw: absDir + degrees,
      minPitch: -10,
      maxPitch: 10,
      minRoll: -5,
      maxRoll: 5,
      isLeft: isLeft,
    );
  }
}

class PoseTarget {
  final double minYaw;
  final double maxYaw;
  final double minPitch;
  final double maxPitch;
  final double minRoll;
  final double maxRoll;
  final bool isLeft;

  PoseTarget({
    required this.minYaw,
    required this.maxYaw,
    required this.minPitch,
    required this.maxPitch,
    required this.minRoll,
    required this.maxRoll,
    this.isLeft = false,
  });
}

class _PoseGuide extends StatelessWidget {
  const _PoseGuide({
    required this.title,
    required this.description,
    required this.targetPose,
  });

  final String title;
  final String description;
  final PoseTarget targetPose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}