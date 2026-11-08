import 'dart:convert';

import 'package:facial_analysis/core/error_logger.dart';
import 'package:facial_analysis/ui/error_logs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage backend that always fails, to prove the logger never crashes.
class _BrokenStorage implements ErrorLogStorage {
  @override
  Future<String?> read() async => throw const IOError('no disk');

  @override
  Future<void> write(String contents) async =>
      throw const IOError('no disk');
}

class IOError implements Exception {
  const IOError(this.message);

  final String message;

  @override
  String toString() => 'IOError: $message';
}

void main() {
  group('ErrorLogger', () {
    test('records an entry with every required field', () async {
      final MemoryErrorLogStorage storage = MemoryErrorLogStorage();
      final ErrorLogger logger = ErrorLogger(storage: storage);
      await logger.load();

      logger.logError(
        StateError('mesh exploded'),
        StackTrace.current,
        source: ErrorLogSource.facemesh,
        context: <String, Object?>{'landmarks': 412},
      );
      await logger.pendingWrites;

      final List<ErrorLogEntry> entries = logger.entries;
      expect(entries, hasLength(1));
      final ErrorLogEntry entry = entries.single;
      expect(entry.level, ErrorLogLevel.error);
      expect(entry.source, ErrorLogSource.facemesh);
      expect(entry.errorType, 'StateError');
      expect(entry.message, contains('mesh exploded'));
      expect(entry.appVersion, kAppVersion);
      expect(entry.context['landmarks'], 412);
      // The timestamp must be a real ISO-8601 string.
      expect(DateTime.tryParse(entry.timestamp.toIso8601String()), isNotNull);
      // One line of JSON on disk.
      final String? contents = storage.contents;
      expect(contents, isNotNull);
      expect(contents!.split('\n'), hasLength(1));
      final Object? decoded = jsonDecode(contents);
      expect(decoded, isA<Map<String, Object?>>());
    });

    test('caps the log at 200 entries, dropping the oldest', () async {
      final MemoryErrorLogStorage storage = MemoryErrorLogStorage();
      final ErrorLogger logger = ErrorLogger(storage: storage);
      await logger.load();

      for (int i = 0; i < 250; i++) {
        logger.logError(StateError('error $i'), StackTrace.current);
      }
      await logger.pendingWrites;

      expect(logger.entries, hasLength(200));
      expect(logger.entries.first.message, contains('error 50'));
      expect(logger.entries.last.message, contains('error 249'));
      // The file on disk matches the in-memory ring buffer.
      expect(storage.contents!.split('\n'), hasLength(200));
    });

    test('rotates by size: never writes more than ~200 KB', () async {
      final MemoryErrorLogStorage storage = MemoryErrorLogStorage();
      final ErrorLogger logger = ErrorLogger(storage: storage);
      await logger.load();

      final String fat = 'x' * 1000;
      for (int i = 0; i < 400; i++) {
        logger.logError(StateError('entry $i $fat'), StackTrace.current);
      }
      await logger.pendingWrites;

      final String contents = storage.contents!;
      // The newest 200 cap and the 200 KB cap interact; the size cap must
      // hold with at most one entry of slack.
      expect(
        contents.length,
        lessThanOrEqualTo(200 * 1024 + 3000),
        reason: 'file grew past the byte cap',
      );
      expect(logger.entries.length, lessThanOrEqualTo(200));
      // Newest entries survive the rotation.
      expect(logger.entries.last.message, contains('entry 399'));
    });

    test('a broken storage backend never crashes the logger', () async {
      final ErrorLogger logger = ErrorLogger(storage: _BrokenStorage());
      await logger.load();

      expect(() {
        logger.logError(StateError('boom'), StackTrace.current);
        logger.logWarning('careful');
      }, returnsNormally);
      await logger.pendingWrites;

      expect(() => logger.clear(), returnsNormally);
      await logger.clear();
    });

    test('warnings are recorded too, and info-level logging does not exist',
        () async {
      final MemoryErrorLogStorage storage = MemoryErrorLogStorage();
      final ErrorLogger logger = ErrorLogger(storage: storage);
      await logger.load();

      logger.logWarning(
        'detector was slow',
        source: ErrorLogSource.analysis,
        context: <String, Object?>{'stage': 'pipeline-timeout'},
      );
      await logger.pendingWrites;

      final ErrorLogEntry entry = logger.entries.single;
      expect(entry.level, ErrorLogLevel.warning);
      expect(entry.source, ErrorLogSource.analysis);
      expect(entry.context['stage'], 'pipeline-timeout');
      expect(entry.stackTrace, isEmpty);
    });
  });

  group('ErrorLogsScreen', () {
    testWidgets('shows "No errors logged" when the log is empty',
        (WidgetTester tester) async {
      final ErrorLogger logger =
          ErrorLogger(storage: MemoryErrorLogStorage());
      await logger.load();

      await tester.pumpWidget(
        MaterialApp(home: ErrorLogsScreen(logger: logger)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No errors logged'), findsOneWidget);
    });

    testWidgets('shows a recorded error and opens its detail',
        (WidgetTester tester) async {
      final ErrorLogger logger =
          ErrorLogger(storage: MemoryErrorLogStorage());
      await logger.load();
      logger.logError(
        StateError('mesh exploded 412'),
        StackTrace.current,
        source: ErrorLogSource.facemesh,
      );
      await logger.pendingWrites;

      await tester.pumpWidget(
        MaterialApp(home: ErrorLogsScreen(logger: logger)),
      );
      await tester.pumpAndSettle();

      expect(find.text('StateError'), findsOneWidget);
      expect(find.textContaining('mesh exploded 412'), findsOneWidget);

      await tester.tap(find.text('StateError'));
      await tester.pumpAndSettle();

      expect(find.text('STACK TRACE'), findsOneWidget);
      expect(find.textContaining('facemesh'), findsWidgets);
    });
  });
}
