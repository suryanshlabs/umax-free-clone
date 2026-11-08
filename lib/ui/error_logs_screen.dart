import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/error_logger.dart';
import 'theme.dart';

/// The on-device error and warning log, for when something went wrong and the
/// failure panel's one line is not enough to go on.
///
/// Nothing here leaves the phone until the user presses Share, and even then
/// only the log text travels — no photos, no face data (see [ErrorLogEntry]).
class ErrorLogsScreen extends StatefulWidget {
  const ErrorLogsScreen({super.key, this.logger});

  /// Injectable for tests; the app always uses the singleton.
  final ErrorLogger? logger;

  @override
  State<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends State<ErrorLogsScreen> {
  List<ErrorLogEntry> _entries = <ErrorLogEntry>[];
  bool _loading = true;

  ErrorLogger get _logger => widget.logger ?? ErrorLogger.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      await _logger.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = _logger.entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = const <ErrorLogEntry>[];
        _loading = false;
      });
    }
  }

  Future<void> _copyAll() async {
    final String text = _entries
        .map((ErrorLogEntry e) => e.fullText)
        .join('\n---\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied all entries')));
    }
  }

  Future<void> _share() async {
    try {
      await _logger.pendingWrites;
      final Directory directory = await getTemporaryDirectory();
      final File file = File(
        '${directory.path}/face_geometry_error_log.txt',
      );
      final String text = _entries
          .map((ErrorLogEntry e) => e.fullText)
          .join('\n---\n');
      await file.writeAsString(
        'Face Geometry error log (app $kAppVersion)\n\n$text\n',
        flush: true,
      );
      if (!mounted) {
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: 'Face Geometry error log',
          text: 'Face Geometry error log (${_entries.length} entries)',
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sharing failed. Use "Copy all" instead.'),
          ),
        );
      }
    }
  }

  Future<void> _clear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear error logs?'),
        content: const Text(
          'Every recorded error and warning will be deleted from this phone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _logger.clear();
    await _refresh();
  }

  void _open(ErrorLogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _ErrorLogDetailScreen(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ErrorLogEntry> newestFirst = _entries.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Error Logs'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy all',
            onPressed: _entries.isEmpty ? null : () => unawaited(_copyAll()),
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: _entries.isEmpty ? null : () => unawaited(_share()),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: _entries.isEmpty ? null : () => unawaited(_clear()),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                itemCount: newestFirst.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final ErrorLogEntry entry = newestFirst[index];
                  final bool isError = entry.level == ErrorLogLevel.error;
                  return Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => _open(entry),
                      borderRadius: BorderRadius.circular(16),
                      child: Ink(
                        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isError
                                ? AppColors.danger.withValues(alpha: 0.35)
                                : AppColors.outline,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              isError
                                  ? Icons.error_outline_rounded
                                  : Icons.warning_amber_rounded,
                              size: 19,
                              color: isError
                                  ? AppColors.danger
                                  : AppColors.amber,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    entry.errorType,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.message,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${entry.timestamp.toLocal()} · '
                                    '${entry.source.name}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle_outline_rounded,
              size: 34,
              color: AppColors.mint,
            ),
            SizedBox(height: 14),
            Text(
              'No errors logged',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Only errors and warnings are recorded here, on this phone. '
              'If a scan ever fails, the details will appear in this list.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorLogDetailScreen extends StatelessWidget {
  const _ErrorLogDetailScreen({required this.entry});

  final ErrorLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entry.level == ErrorLogLevel.error ? 'Error' : 'Warning',
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy entry',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: entry.fullText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied entry')),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: <Widget>[
            Text(
              entry.errorType,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              entry.message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            _Field('Time', entry.timestamp.toLocal().toString()),
            _Field('Source', entry.source.name),
            _Field('App version', entry.appVersion),
            _Field('Android', entry.androidVersion ?? 'unknown'),
            _Field('Device', entry.deviceModel ?? 'unknown'),
            if (entry.context.isNotEmpty)
              _Field('Context', entry.context.toString()),
            if (entry.stackTrace.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              const Text(
                'STACK TRACE',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.outline),
                ),
                child: SelectableText(
                  entry.stackTrace,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
