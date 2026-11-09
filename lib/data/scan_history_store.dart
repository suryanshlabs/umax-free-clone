import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/image_store.dart';
import '../core/report.dart';
import '../core/user_profile.dart';
import 'scan_history.dart';

abstract interface class ScanHistoryStorage {
  Future<String?> read();

  Future<void> write(String contents);
}

class FileScanHistoryStorage implements ScanHistoryStorage {
  FileScanHistoryStorage({this.fileName = 'scan_history.json'});

  final String fileName;

  Future<File> _file() async {
    final Directory directory = await getApplicationSupportDirectory();
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

class MemoryScanHistoryStorage implements ScanHistoryStorage {
  MemoryScanHistoryStorage([this.contents]);

  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async => contents = value;
}

class ScanHistory extends ChangeNotifier {
  ScanHistory({ScanHistoryStorage? storage, this.maxEntries = 60})
    : _storage = storage ?? FileScanHistoryStorage();

  static const int version = 3;

  final ScanHistoryStorage _storage;
  final int maxEntries;

  List<SavedScan> _scans = <SavedScan>[];
  bool _loaded = false;
  bool _loading = false;
  UserProfile? _profile;

  List<SavedScan> get scans => List<SavedScan>.unmodifiable(_scans);

  bool get isLoaded => _loaded;

  bool get isLoading => _loading;

  bool get isEmpty => _scans.isEmpty;

  UserProfile? get profile => _profile;

  Future<void> load() async {
    if (_loaded || _loading) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final String? contents = await _storage.read();
      final List<SavedScan> scans = _decode(contents);
      _scans = scans;
      _profile = _decodeProfile(contents);

      // Prune prepared photos that no saved scan points at. Fire-and-forget:
      // a cleanup failure must not block the history from loading.
      await ImageStore.sweepUnreferenced(
        _scans.map((SavedScan scan) => scan.imagePath),
      );
    } on Exception catch (error) {
      debugPrint('Scan history could not be read: $error');
      _scans = <SavedScan>[];
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Stores the optional gender answer. Passing null clears it; the scan
  /// records themselves never reference it.
  Future<void> setProfile(UserProfile? profile) async {
    _profile = profile;
    await _persist();
    notifyListeners();
  }

  Future<void> add(AnalysisReport report) =>
      addSaved(SavedScan.fromReport(report));

  Future<void> addSaved(SavedScan scan) async {
    _scans = <SavedScan>[scan, ..._scans];
    if (_scans.length > maxEntries) {
      _scans = _scans.sublist(0, maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  /// Removes one scan and its photo.
  ///
  /// The photo is deleted only after the history has been rewritten, so a write
  /// failure cannot leave the history pointing at a file that is already gone.
  Future<void> remove(String id) async {
    String? removedPath;
    final List<SavedScan> kept = <SavedScan>[];
    for (final SavedScan scan in _scans) {
      if (scan.id == id) {
        removedPath = scan.imagePath;
      } else {
        kept.add(scan);
      }
    }
    _scans = kept;
    notifyListeners();
    await _persist();

    if (removedPath != null &&
        !_scans.any((SavedScan scan) => scan.imagePath == removedPath)) {
      await ImageStore.deleteManaged(removedPath);
    }
  }

  /// Removes every scan and every photo this app prepared for them.
  Future<void> clear() async {
    _scans = <SavedScan>[];
    notifyListeners();
    await _persist();
    await ImageStore.deleteAllPrepared();
  }

  Future<void> _persist() async {
    try {
      await _storage.write(
        jsonEncode(<String, Object?>{
          'version': version,
          'profile': _profile?.toJson(),
          'scans': <Object?>[
            for (final SavedScan scan in _scans) scan.toJson(),
          ],
        }),
      );
    } on Exception catch (error) {
      debugPrint('Scan history could not be saved: $error');
    }
  }

  /// Reads the optional profile from the file root.
  ///
  /// Version 2 and older stored age, height, weight and BMI next to the gender.
  /// Only the gender is kept: those body-composition fields are not part of the
  /// profile any more, so they stop being rewritten. Scan records are untouched
  /// by this and still load exactly as they were saved.
  UserProfile? _decodeProfile(String? contents) {
    if (contents == null || contents.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(contents);
      if (decoded is! Map) {
        return null;
      }
      return UserProfile.fromJson(decoded['profile']);
    } on FormatException {
      return null;
    }
  }

  List<SavedScan> _decode(String? contents) {
    if (contents == null || contents.trim().isEmpty) {
      return <SavedScan>[];
    }
    try {
      final Object? decoded = jsonDecode(contents);
      if (decoded is! Map) {
        return <SavedScan>[];
      }
      final Object? rawScans = decoded['scans'];
      if (rawScans is! List) {
        return <SavedScan>[];
      }
      final List<SavedScan> scans = <SavedScan>[];
      for (final Object? entry in rawScans) {
        final SavedScan? scan = SavedScan.fromJson(entry);
        if (scan != null) {
          scans.add(scan);
        }
      }
      scans.sort(
        (SavedScan a, SavedScan b) => b.createdAt.compareTo(a.createdAt),
      );
      return scans;
    } on FormatException {
      return <SavedScan>[];
    }
  }
}
