import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/error_logger.dart';
import '../core/facial_analysis_service.dart';
import '../core/metrics.dart';
import '../core/report.dart';
import '../core/scoring_engine.dart';
import '../data/scan_history.dart';
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
    ScanHistory? history,
    Duration timeout = pipelineTimeout,
  }) : _reader = reader ?? FaceMeshReader(),
       _service = service,
       _engine = engine,
       _history = history,
       _timeout = timeout;

  /// Hard ceiling on the whole detection step.
  ///
  /// The reader enforces its own 30 s deadline around ML Kit; this one also
  /// covers any other [FaceMeshSource] and the file read, so a wedged platform
  /// channel can never leave the scanning animation spinning with no way out.
  /// Forty-five seconds: the previous 8 s was shorter than a cold ML Kit
  /// model's first run on a busy mid-range phone, and every timeout was then
  /// reported as "Face not detected" — the false NO READING this fixes.
  static const Duration pipelineTimeout = Duration(seconds: 45);

  final FaceMeshSource _reader;
  final FacialAnalysisService _service;
  final ScoringEngine _engine;
  final ScanHistory? _history;
  final Duration _timeout;

  AnalysisPhase _phase = AnalysisPhase.idle;
  AnalysisReport? _report;
  String? _errorMessage;
  String? _imagePath;
  double? _imageAspectRatio;
  bool _isAnalysing = false;

  AnalysisPhase get phase => _phase;
  AnalysisReport? get report => _report;
  String? get errorMessage => _errorMessage;
  String? get imagePath => _imagePath;

  /// True while a pipeline run is in flight — the single flag that prevents a
  /// second concurrent run, a tap on "again", or a retry racing a scan.
  bool get isAnalysing => _isAnalysing;

  bool get isBusy => _isAnalysing;

  /// Marks a failure that happened *around* the pipeline (photo preparation,
  /// navigation) so those screens land on the failed state with a real message
  /// instead of spinning on "ANALYSING" forever.
  void failWithMessage(String message) {
    _fail(message);
  }

  /// Runs the full pipeline for the photo at [path].
  ///
  /// The processing animation is given a minimum on-screen time so a fast
  /// device does not flash a spinner for 200 ms — the analysis itself is
  /// unchanged by the delay.
  ///
  /// Whatever happens inside — detector fault, a plugin throwing an `Error`
  /// (which `on Exception` cannot catch), a timeout, a bug — the method always
  /// ends in either [AnalysisPhase.ready] or [AnalysisPhase.failed] with a
  /// message the UI can show, and always clears [isAnalysing].
  Future<void> analyse(
    String path, {
    double? imageAspectRatio,
    Duration minimumVisibleTime = const Duration(milliseconds: 1500),
  }) async {
    if (_isAnalysing) {
      return;
    }
    _isAnalysing = true;

    _phase = AnalysisPhase.analysing;
    _errorMessage = null;
    _imagePath = path;
    _imageAspectRatio = imageAspectRatio;
    notifyListeners();

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final FaceMeshReading? reading = await _reader
          .readFile(path, imageAspectRatio: imageAspectRatio)
          .timeout(_timeout);
      if (reading == null) {
        throw const FacialAnalysisException(faceNotDetectedMessage);
      }

      final RawFaceMetrics metrics = _service.measure(reading.points);
      final AnalysisReport report = _engine.build(metrics, imagePath: path);

      final List<String> warnings = List<String>.of(report.qualityWarnings);
      if (!reading.isLargeEnough) {
        warnings.add(
          'Your face filled only a small part of the frame. Move closer so the '
          'mesh has more pixels per feature; that alone can shift a '
          'measurement by several points.',
        );
      }
      if (reading.faceCount > 1) {
        warnings.add(
          '${reading.faceCount} faces were in frame. The largest one was '
          'measured; scan alone for a cleaner read.',
        );
      }

      await _holdAnimation(stopwatch, minimumVisibleTime);

      final AnalysisReport enriched = AnalysisReport(
        overallScore: report.overallScore,
        metrics: report.metrics,
        coreWeakness: report.coreWeakness,
        raw: report.raw,
        qualityWarnings: warnings,
        safetyNote: report.safetyNote,
        createdAt: report.createdAt,
        imagePath: report.imagePath,
      );
      _report = enriched;
      _phase = AnalysisPhase.ready;
      notifyListeners();

      // Saving must never turn a successful scan into an error screen; the
      // store logs its own write failures.
      await _history?.add(enriched);
    } on TimeoutException {
      ErrorLogger.instance.logWarning(
        'Analysis pipeline exceeded ${_timeout.inSeconds}s.',
        source: ErrorLogSource.analysis,
        context: <String, Object?>{'stage': 'pipeline-timeout'},
      );
      await _holdAnimation(stopwatch, minimumVisibleTime);
      _fail(detectionTimedOutMessage);
    } on FacialAnalysisException catch (error) {
      // A missing face is a normal user-facing outcome, not an error to log;
      // everything else (partial mesh, scoring faults) is worth a record.
      if (error.message != faceNotDetectedMessage) {
        ErrorLogger.instance.logWarning(
          error.message,
          source: ErrorLogSource.analysis,
        );
      }
      await _holdAnimation(stopwatch, minimumVisibleTime);
      _fail(error.message);
    } on Object catch (error, stackTrace) {
      // Catches Errors too (ArgumentError, StateError, ...), which `on
      // Exception` lets escape and freeze the UI mid-"ANALYSING". The real
      // error is shown to the user, not the generic face-not-detected text.
      ErrorLogger.instance.logError(
        error,
        stackTrace,
        source: ErrorLogSource.analysis,
      );
      debugPrint('Analysis failed: $error');
      debugPrint('$stackTrace');
      await _holdAnimation(stopwatch, minimumVisibleTime);
      _fail(_describe(error));
    } finally {
      _isAnalysing = false;
      // Last-resort guard: never leave the UI on "ANALYSING" without a result.
      if (_phase == AnalysisPhase.analysing) {
        _fail(faceNotDetectedMessage);
      }
    }
  }

  /// The text the failure panel shows for an unexpected fault: the error's
  /// runtime type and message, capped so a huge platform error cannot flood
  /// the screen. The full stack is still in the logs.
  String _describe(Object error) {
    final String text = error.toString();
    final String capped = text.length > 240
        ? '${text.substring(0, 240)}…'
        : text;
    return 'Analysis failed (${error.runtimeType}): $capped';
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
