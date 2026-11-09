import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Owns the lifecycle of the photo files this app writes.
///
/// The app never uploads anything, but local files still deserve a cleanup
/// policy: a prepared square is ~1-2 MB, and a user who scans weekly should not
/// accumulate them forever after deleting the scan.
///
/// Everything here is deliberately conservative:
///
/// * it only ever touches files inside the app's own temporary directory;
/// * it only sweeps files whose names start with a prefix this app chose,
///   never a gallery original or another app's file;
/// * every failure is swallowed, because a cleanup problem must never break a
///   scan or a deletion the user asked for.
class ImageStore {
  const ImageStore._();

  /// Resolves the directory that owns this app's prepared photos.
  ///
  /// Overridable so tests can point it at a temporary directory without a
  /// platform channel; production always uses the app's temp directory.
  @visibleForTesting
  static Future<Directory> Function() directoryResolver = getTemporaryDirectory;

  /// Prefixes this app uses for files it owns.
  static const List<String> ownedPrefixes = <String>['analysis_square_'];

  /// True when [path] points at a file this app created.
  static Future<bool> isManaged(String? path) async {
    if (path == null || path.isEmpty) {
      return false;
    }
    try {
      final Directory temp = await directoryResolver();
      final String tempRoot = _normalise(temp.path);
      final String target = _normalise(path);
      return target.startsWith(tempRoot) &&
          ownedPrefixes.any(
            (String prefix) => target.split('/').last.startsWith(prefix),
          );
    } on Object {
      return false;
    }
  }

  /// Deletes one file if, and only if, this app owns it.
  static Future<void> deleteManaged(String? path) async {
    try {
      if (!await isManaged(path)) {
        return;
      }
      final File file = File(path!);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (error) {
      debugPrint('Could not delete a prepared photo: $error');
    }
  }

  /// Deletes prepared squares that are not referenced by any saved scan.
  ///
  /// [keep] is the set of image paths the history still points at. Running this
  /// on load means a crash between writing a scan and pruning its file cannot
  /// leak storage, and a deleted scan never leaves an orphan behind.
  static Future<void> sweepUnreferenced(Iterable<String?> keep) async {
    try {
      final Directory temp = await directoryResolver();
      final Set<String> referenced = <String>{
        for (final String? path in keep)
          if (path != null && path.isNotEmpty) _normalise(path),
      };
      await for (final FileSystemEntity entity in temp.list()) {
        if (entity is! File) {
          continue;
        }
        final String name = entity.path.split('/').last;
        if (!ownedPrefixes.any(name.startsWith)) {
          continue;
        }
        if (referenced.contains(_normalise(entity.path))) {
          continue;
        }
        try {
          await entity.delete();
        } on FileSystemException {
          // Another sweep or an open handle; harmless.
        }
      }
    } on Object catch (error) {
      debugPrint('Could not sweep unused photos: $error');
    }
  }

  /// Deletes every managed file, used when the user clears their history.
  static Future<void> deleteAllPrepared() async {
    try {
      final Directory temp = await directoryResolver();
      await for (final FileSystemEntity entity in temp.list()) {
        if (entity is! File) {
          continue;
        }
        final String name = entity.path.split('/').last;
        if (!ownedPrefixes.any(name.startsWith)) {
          continue;
        }
        try {
          await entity.delete();
        } on FileSystemException {
          // Ignore and continue.
        }
      }
    } on Object catch (error) {
      debugPrint('Could not clear prepared photos: $error');
    }
  }

  /// Deletes a picker/camera copy that lives in this app's temporary directory.
  ///
  /// Camera captures and gallery imports are copied into the app's cache by the
  /// plugins; once the prepared square exists they are redundant, and keeping
  /// them doubles the on-device footprint of a scan.
  static Future<void> deleteTemporarySource(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      final Directory temp = await directoryResolver();
      final String tempRoot = _normalise(temp.path);
      final String target = _normalise(path);
      if (!target.startsWith(tempRoot)) {
        return;
      }
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (error) {
      debugPrint('Could not delete a capture: $error');
    }
  }

  static String _normalise(String path) =>
      path.replaceAll('\\', '/').toLowerCase();
}
