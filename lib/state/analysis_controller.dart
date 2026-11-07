import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/facial_analysis_service.dart';
import '../core/metrics.dart';
import '../core/report.dart';
import '../core/scoring_engine.dart';
import '../ml/face_mesh_reader.dart';
import '../ml/face_mesh_source.dart';

/// Where the pipeline currently is. The UI renders from this, never from
/// navigation state, so a slow detector cannot desynchronise the screens.
enum AnalysisPhase { idle, analysing, ready, failed }

/// Local state for one analysis run.
///
/// Deliberately a plain [ChangeNotifier]: one screen's worth of state, no
/// repositories, no serialisation. The heavy work (mesh detection + maths) is
/// injected so widget tests can run the whole pipeline against a fake reader.
class AnalysisController extends ChangeNotifier {
  AnalysisController({
    FaceMeshSource? reader,
    FacialAnalysisService service = const FacialAnalysisService(),
    ScoringEngine engine = const ScoringEngine(),
  }) : _reader = reader ?? FaceMeshReader(),
       _service = service,
       _engine = engine;

  final FaceMeshSource _reader;
  final FacialAnalysisService _service;
  final ScoringEngine _engine;

  AnalysisPhase _phase = AnalysisPhase.idle;
  AnalysisReport? _report;
  String? _errorMessage;
  String? _imagePath;
  double? _imageAspectRatio;

  AnalysisPhase get phase => _phase;
  AnalysisReport? get report => _report;
  String? get errorMessage => _errorMessage;
  String? get imagePath => _imagePath;

  bool get isBusy => _phase == AnalysisPhase.analysing;

  /// Runs the full pipeline for the photo at [path].
  ///
  /// The processing animation is given a minimum on-screen time so a fast
  /// device does not flash a spinner for 200 ms — the analysis itself is
  /// unchanged by the delay.
  Future<void> analyse(
    String path, {
    double? imageAspectRatio,
    Duration minimumVisibleTime = const Duration(milliseconds: 1500),
  }) async {
    if (_phase == AnalysisPhase.analysing) {
      return;
    }

    _phase = AnalysisPhase.analysing;
    _errorMessage = null;
    _imagePath = path;
    _imageAspectRatio = imageAspectRatio;
    notifyListeners();

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final FaceMeshReading? reading = await _reader.readFile(
        path,
        imageAspectRatio: imageAspectRatio,
      );
      if (reading == null) {
        throw const FacialAnalysisException(
          'No face was detected. Fill the guide with your face, keep your hair '
          'out of your eyes, and make sure the room is lit from the front.',
        );
      }

      final RawFaceMetrics metrics = _service.measure(reading.points);
      final AnalysisReport report = _engine.build(metrics, imagePath: path);

      final List<String> warnings = List<String>.of(report.qualityWarnings);
      if (!reading.isLargeEnough) {
        warnings.add(
          'Your face filled only a small part of the frame. Move closer so the '
          'mesh has more pixels per feature; that alone can shift a score by '
          'several points.',
        );
      }
      if (reading.faceCount > 1) {
        warnings.add(
          '${reading.faceCount} faces were in frame. The largest one was '
          'measured; scan alone for a cleaner read.',
        );
      }

      await _holdAnimation(stopwatch, minimumVisibleTime);

      _report = AnalysisReport(
        overallScore: report.overallScore,
        grade: report.grade,
        gradeBlurb: report.gradeBlurb,
        metrics: report.metrics,
        raw: report.raw,
        qualityWarnings: warnings,
        safetyNote: report.safetyNote,
        createdAt: report.createdAt,
        imagePath: report.imagePath,
      );
      _phase = AnalysisPhase.ready;
      notifyListeners();
    } on FacialAnalysisException catch (error) {
      await _holdAnimation(stopwatch, minimumVisibleTime);
      _fail(error.message);
    } on Exception catch (error) {
      await _holdAnimation(stopwatch, minimumVisibleTime);
      _fail(
        'The scan could not be completed. Try again with your face fully in '
        'frame and even lighting. ($error)',
      );
    }
  }

  /// Retries the last photo, if there is one.
  Future<void> retry() async {
    final String? path = _imagePath;
    if (path == null) {
      return;
    }
    await analyse(path, imageAspectRatio: _imageAspectRatio);
  }

  /// Clears the result and returns to the idle state.
  void reset() {
    _phase = AnalysisPhase.idle;
    _report = null;
    _errorMessage = null;
    _imagePath = null;
    _imageAspectRatio = null;
    notifyListeners();
  }

  Future<void> _holdAnimation(Stopwatch stopwatch, Duration minimum) async {
    final Duration remaining = minimum - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  void _fail(String message) {
    _errorMessage = message;
    _report = null;
    _phase = AnalysisPhase.failed;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_reader.dispose());
    super.dispose();
  }
}
