import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// The app version stamped into every log entry. Kept in sync with
/// `pubspec.yaml` by hand — it is only there so a shared log says which build
/// produced it, and a const keeps this file free of another plugin just for a
/// version string.
const String kAppVersion = '3.2.0+9';

/// Only real problems are recorded. Info and debug lines are never logged:
/// they would bury the failures that matter and grow the file for nothing.
enum ErrorLogLevel { warning, error }

extension on ErrorLogLevel {
  String get logName => name;
}

/// Which part of the app produced the entry.
enum ErrorLogSource { camera, facemesh, analysis, ui, app }

/// One recorded problem.
///
/// Deliberately contains no photo paths, no landmark coordinates and no other
/// personal data: a shared log must be safe to send to a developer, and
/// "which landmark was missing" (a count in [context]) is all the debugging
/// needs.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.errorType,
    required this.message,
    this.stackTrace = '',
    this.appVersion = kAppVersion,
    this.androidVersion,
    this.deviceModel,
    this.context = const <String, Object?>{},
  });

  final DateTime timestamp;
  final ErrorLogLevel level;
  final ErrorLogSource source;
  final String errorType;
  final String message;

  /// Already truncated to ~1500 characters at log time.
  final String stackTrace;
  final String appVersion;
  final String? androidVersion;
  final String? deviceModel;

  /// Small diagnostic extras, e.g. `{'landmarks': 412}`.
  final Map<String, Object?> context;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': timestamp.toIso8601String(),
    'level': level.logName,
    'source': source.name,
    'type': errorType,
    'message': message,
    'stack': stackTrace,
    'app': appVersion,
    'android': androidVersion,
    'device': deviceModel,
    'context': context,
  };

  static ErrorLogEntry? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? at = json['at'];
    final Object? level = json['level'];
    final Object? source = json['source'];
    final DateTime? timestamp = at is String ? DateTime.tryParse(at) : null;
    ErrorLogLevel? parsedLevel;
    for (final ErrorLogLevel candidate in ErrorLogLevel.values) {
      if (candidate.name == level) {
        parsedLevel = candidate;
        break;
      }
    }
    ErrorLogSource? parsedSource;
    for (final ErrorLogSource candidate in ErrorLogSource.values) {
      if (candidate.name == source) {
        parsedSource = candidate;
        break;
      }
    }
    if (timestamp == null || parsedLevel == null || parsedSource == null) {
      return null;
    }
    final Object? context = json['context'];
    return ErrorLogEntry(
      timestamp: timestamp,
      level: parsedLevel,
      source: parsedSource,
      errorType: json['type']?.toString() ?? 'Unknown',
      message: json['message']?.toString() ?? '',
      stackTrace: json['stack']?.toString() ?? '',
      appVersion: json['app']?.toString() ?? kAppVersion,
      androidVersion: json['android']?.toString(),
      deviceModel: json['device']?.toString(),
      context: context is Map
          ? <String, Object?>{for (final e in context.entries) e.key.toString(): e.value}
          : const <String, Object?>{},
    );
  }

  /// One-line summary for lists.
  String get summary => '${timestamp.toIso8601String()}  '
      '[${level.logName.toUpperCase()}/${source.name}] $errorType: $message';

  /// The full text used by "Copy all" and "Share".
  String get fullText {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Time: ${timestamp.toIso8601String()}')
      ..writeln('Level: ${level.logName}')
      ..writeln('Source: ${source.name}')
      ..writeln('Error: $errorType')
      ..writeln('Message: $message')
      ..writeln('App: $appVersion')
      ..writeln('Android: ${androidVersion ?? 'unknown'}')
      ..writeln('Device: ${deviceModel ?? 'unknown'}');
    if (context.isNotEmpty) {
      buffer.writeln('Context: ${jsonEncode(context)}');
    }
    if (stackTrace.isNotEmpty) {
      buffer
        ..writeln('Stack:')
        ..writeln(stackTrace);
    }
    return buffer.toString();
  }
}

/// Where entries live. Extracted so tests run against memory and the real
/// logger stays a thin singleton.
abstract interface class ErrorLogStorage {
  /// The whole file as text, or null when nothing was ever written.
  Future<String?> read();

  Future<void> write(String contents);
}

/// Newline-delimited JSON, one entry per line, in the app's documents
/// directory. Chosen over a single JSON array so an interrupted write loses at
/// most one entry and the oldest can be dropped without parsing the rest.
class FileErrorLogStorage implements ErrorLogStorage {
  FileErrorLogStorage({this.fileName = 'error_log.jsonl'});

  final String fileName;

  Future<File> _file() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$fileName');
  }

  @override
  Future<String?> read() async {
    final File file = await _file();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    final File file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  }
}

/// In-memory storage for tests.
class MemoryErrorLogStorage implements ErrorLogStorage {
  MemoryErrorLogStorage([this.contents]);

  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async => contents = value;
}

/// Records errors and warnings to an on-device, size-bounded file.
///
/// Contract, in order of importance:
///
/// 1. **Never crashes.** Every public method is wrapped in try/catch; a full
///    disk or a broken logger skips the entry and lets the app continue.
/// 2. **Never blocks the UI.** Logging is synchronous in memory; the file
///    write is queued and awaited by nobody (tests can await
///    [pendingWrites]).
/// 3. **Bounded.** At most [maxEntries] entries and roughly [maxBytes] of
///    text; the oldest entries are dropped first (ring buffer in memory, and
///    the file is rewritten from memory so the two never disagree).
class ErrorLogger {
  ErrorLogger({
    ErrorLogStorage? storage,
    this.maxEntries = 200,
    this.maxBytes = 200 * 1024,
    this.appVersion = kAppVersion,
  }) : _storage = storage ?? FileErrorLogStorage();

  /// The one the app uses. Tests build their own with memory storage.
  static final ErrorLogger instance = ErrorLogger();

  final ErrorLogStorage _storage;
  final int maxEntries;
  final int maxBytes;
  final String appVersion;

  final List<ErrorLogEntry> _entries = <ErrorLogEntry>[];
  bool _loaded = false;
  Future<void>? _loadFuture;
  Future<void> _writeQueue = Future<void>.value();
  String? _androidVersion;
  String? _deviceModel;
  bool _deviceInfoStarted = false;

  /// Loads the file into memory. Safe to call repeatedly and concurrently.
  Future<void> load() {
    if (_loaded) {
      return Future<void>.value();
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final String? contents = await _storage.read();
      _entries
        ..clear()
        ..addAll(_parse(contents));
    } on Object {
      _entries.clear();
    } finally {
      _loaded = true;
    }
    unawaited(_initDeviceInfo());
  }

  Future<void> _initDeviceInfo() async {
    if (_deviceInfoStarted) {
      return;
    }
    _deviceInfoStarted = true;
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      _androidVersion = info.version.release;
      _deviceModel = '${info.manufacturer} ${info.model}';
    } on Object {
      // No device info is better than a broken logger.
    }
  }

  /// Newest last. A copy, so callers cannot mutate the ring buffer.
  List<ErrorLogEntry> get entries => List<ErrorLogEntry>.unmodifiable(_entries);

  /// Records [error] with its stack. Never throws.
  void logError(
    Object error,
    StackTrace stack, {
    ErrorLogSource source = ErrorLogSource.app,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _add(
      ErrorLogEntry(
        timestamp: DateTime.now(),
        level: ErrorLogLevel.error,
        source: source,
        errorType: error.runtimeType.toString(),
        message: _cap(error.toString(), 2000),
        stackTrace: _cap(stack.toString(), 1500),
        appVersion: appVersion,
        androidVersion: _androidVersion,
        deviceModel: _deviceModel,
        context: context,
      ),
    );
  }

  /// Records a plain-text warning. Never throws.
  void logWarning(
    String message, {
    ErrorLogSource source = ErrorLogSource.app,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _add(
      ErrorLogEntry(
        timestamp: DateTime.now(),
        level: ErrorLogLevel.warning,
        source: source,
        errorType: 'Warning',
        message: _cap(message, 2000),
        appVersion: appVersion,
        androidVersion: _androidVersion,
        deviceModel: _deviceModel,
        context: context,
      ),
    );
  }

  void _add(ErrorLogEntry entry) {
    try {
      _entries.add(entry);
      _trim();
      _writeQueue = _writeQueue.then((_) => _persist());
    } on Object {
      // Logging must never take the app down with it.
    }
  }

  /// Removes the oldest entries until both bounds hold. The byte bound is
  /// measured on the serialized lines, which is what actually lands on disk.
  void _trim() {
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    while (_entries.length > 1) {
      int bytes = 0;
      for (final ErrorLogEntry entry in _entries) {
        bytes += utf8.encode(jsonEncode(entry.toJson())).length + 1;
      }
      if (bytes <= maxBytes) {
        break;
      }
      _entries.removeAt(0);
    }
  }

  Future<void> _persist() async {
    try {
      final String contents = _entries
          .map((ErrorLogEntry e) => jsonEncode(e.toJson()))
          .join('\n');
      await _storage.write(contents);
    } on Object {
      // A failed write is cosmetic; the next entry retries.
    }
  }

  /// Empties the log. Used by the UI's "Clear logs" button.
  Future<void> clear() async {
    _entries.clear();
    await _writeQueue;
    try {
      await _storage.write('');
    } on Object {
      // See above.
    }
  }

  /// Every queued write has finished. For tests and for screen code that
  /// needs the file settled before sharing it.
  Future<void> get pendingWrites => _writeQueue;

  List<ErrorLogEntry> _parse(String? contents) {
    if (contents == null || contents.trim().isEmpty) {
      return <ErrorLogEntry>[];
    }
    final List<ErrorLogEntry> parsed = <ErrorLogEntry>[];
    for (final String line in contents.split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final ErrorLogEntry? entry = ErrorLogEntry.fromJson(jsonDecode(line));
        if (entry != null) {
          parsed.add(entry);
        }
      } on FormatException {
        // One torn line must not sink the whole log.
      }
    }
    return parsed;
  }

  String _cap(String text, int limit) =>
      text.length > limit ? '${text.substring(0, limit)}…' : text;
}
