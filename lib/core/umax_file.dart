import 'dart:convert';

import '../data/scan_history.dart';
import 'report.dart';

/// A `.umax` file that could not be read.
///
/// The message is written to be shown to the user verbatim, like the rest of the
/// app's failures.
class UmaxFormatException implements Exception {
  const UmaxFormatException(this.message);

  final String message;

  @override
  String toString() => 'UmaxFormatException: $message';
}

/// The shareable form of one report: a title the sender chooses, the timestamp
/// it was exported, and the scan itself with its raw measurements.
///
/// It is plain JSON with a format marker and a version, so a future change can
/// be detected rather than silently misread, and so anyone can open the file in
/// a text editor and see exactly what they are sharing — no image, no location,
/// no device identifier.
class UmaxDocument {
  const UmaxDocument({
    required this.title,
    required this.exportedAt,
    required this.scan,
  });

  /// File extension, without the dot.
  static const String extension = 'umax';

  /// The marker every file must carry.
  static const String formatId = 'umax';

  /// Bumped only when the reader would otherwise misread an older file.
  static const int formatVersion = 1;

  /// Longest title accepted. Long enough for a name and a label, short enough
  /// to stay a filename.
  static const int maxTitleLength = 60;

  final String title;
  final DateTime exportedAt;
  final SavedScan scan;

  factory UmaxDocument.fromReport(
    AnalysisReport report, {
    required String title,
  }) {
    return UmaxDocument(
      title: sanitiseTitle(title),
      exportedAt: DateTime.now(),
      scan: SavedScan.fromReport(report),
    );
  }

  factory UmaxDocument.fromScan(SavedScan scan, {required String title}) {
    return UmaxDocument(
      title: sanitiseTitle(title),
      exportedAt: DateTime.now(),
      scan: scan,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'format': formatId,
    'formatVersion': formatVersion,
    'title': title,
    'exportedAt': exportedAt.toIso8601String(),
    'scan': scan.toJson(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// The scan as it should enter this device's archive: titled by the sender and
  /// marked as a friend's report so the two can never be confused.
  SavedScan asImportedScan() {
    return scan.copyWith(
      id: 'friend-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      isFriend: true,
    );
  }

  /// `alex-jawline-check-2026-11-07.umax`
  static String suggestedFileName(String rawTitle) {
    final String cleaned = sanitiseTitle(rawTitle)
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    final String stem = cleaned.isEmpty ? 'report' : cleaned;
    final DateTime now = DateTime.now();
    final String stamp = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    return '$stem-$stamp.$extension';
  }

  /// Trims, collapses whitespace, caps the length, and refuses to return an
  /// empty name.
  static String sanitiseTitle(String raw) {
    final String collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) {
      return 'Shared report';
    }
    return collapsed.length <= maxTitleLength
        ? collapsed
        : collapsed.substring(0, maxTitleLength).trimRight();
  }

  /// Reads a `.umax` file. Throws [UmaxFormatException] with a sentence worth
  /// showing the user.
  static UmaxDocument decode(String contents) {
    if (contents.trim().isEmpty) {
      throw const UmaxFormatException('That file is empty.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const UmaxFormatException(
        'That file is not a .umax report. Choose the file the sender exported '
        'from Face Geometry.',
      );
    }
    if (decoded is! Map) {
      throw const UmaxFormatException(
        'That file is not a .umax report. Choose the file the sender exported '
        'from Face Geometry.',
      );
    }
    if (decoded['format'] != formatId) {
      throw const UmaxFormatException(
        'That file is not a .umax report. Choose the file the sender exported '
        'from Face Geometry.',
      );
    }
    final Object? version = decoded['formatVersion'];
    if (version is! int || version < 1) {
      throw const UmaxFormatException(
        'That report is missing its format version, so it cannot be trusted.',
      );
    }
    if (version > formatVersion) {
      throw const UmaxFormatException(
        'That report was made by a newer version of the app. Update Face '
        'Geometry and try again.',
      );
    }

    final SavedScan? scan = SavedScan.fromJson(decoded['scan']);
    if (scan == null) {
      throw const UmaxFormatException(
        'That report is missing its measurements, so there is nothing to '
        'compare.',
      );
    }

    final Object? rawTitle = decoded['title'];
    final Object? rawExported = decoded['exportedAt'];
    return UmaxDocument(
      title: sanitiseTitle(rawTitle is String ? rawTitle : 'Shared report'),
      exportedAt:
          DateTime.tryParse(rawExported is String ? rawExported : '') ??
          scan.createdAt,
      scan: scan,
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
