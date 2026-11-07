import 'dart:async';

import '../ml/face_mesh_reader.dart';
import '../ml/face_mesh_source.dart';
import '../ml/photo_prep.dart';
import 'facial_analysis_service.dart';
import 'metrics.dart';
import 'report.dart';
import 'scoring_engine.dart';

/// One photo, measured end to end.
class PhotoAnalysis {
  const PhotoAnalysis({required this.report, required this.imagePath});

  final AnalysisReport report;

  /// The prepared 1080x1080 square the mesh was read from.
  final String imagePath;
}

/// Measures a photo without touching the app's single-scan state.
///
/// The comparison screens need two independent results from one screen, and
/// neither should become "the" current analysis or appear as a duplicate in the
/// history. This runs the same four steps [AnalysisController] does — prepare,
/// detect, measure, score — and nothing else.
class PhotoAnalyzer {
  PhotoAnalyzer({
    FaceMeshSource? reader,
    FacialAnalysisService service = const FacialAnalysisService(),
    ScoringEngine engine = const ScoringEngine(),
    PhotoPreparer preparer = const PhotoPreparer(),
    Duration timeout = defaultTimeout,
  }) : _reader = reader ?? FaceMeshReader(),
       _service = service,
       _engine = engine,
       _preparer = preparer,
       _timeout = timeout;

  /// Two photos are measured one after the other, so each pass gets the same
  /// ceiling a single scan does.
  static const Duration defaultTimeout = Duration(seconds: 12);

  final FaceMeshSource _reader;
  final FacialAnalysisService _service;
  final ScoringEngine _engine;
  final PhotoPreparer _preparer;
  final Duration _timeout;

  /// Throws [PhotoPreparationException] when the file cannot be opened and
  /// [FacialAnalysisException] when no usable mesh comes back. Both carry
  /// sentences meant for the user.
  Future<PhotoAnalysis> analyse(String path) async {
    final PreparedPhoto prepared = await _preparer.preparePath(path);
    final reading = await _reader.readFile(prepared.path).timeout(_timeout);
    if (reading == null) {
      throw const FacialAnalysisException(faceNotDetectedMessage);
    }
    final RawFaceMetrics metrics = _service.measure(reading.points);
    final AnalysisReport report = _engine.build(
      metrics,
      imagePath: prepared.path,
    );
    return PhotoAnalysis(report: report, imagePath: prepared.path);
  }

  Future<void> dispose() => _reader.dispose();
}
