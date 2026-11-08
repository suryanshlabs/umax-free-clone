# Changelog

## 1.2.2+5 — "NO READING" fix + on-device error log

### Fixed: false "NO READING" in release builds
- The face-mesh detection deadline was 8 seconds, and every timeout — on the
  reader and on the analysis pipeline — was reported to the user as
  "Face not detected" (the NO READING screen). A cold ML Kit model on a
  mid-range phone routinely needs longer than that for its first run, so a
  perfectly good selfie failed with a misleading message. Deadlines are now
  30 s (reader) and 45 s (pipeline), and a timeout shows its own honest
  message: "Analysis timed out…" instead of blaming the face.
- "NO READING" is now reserved for the one case it describes: the detector
  genuinely found no face. All other failures show "ANALYSIS FAILED" with the
  specific reason underneath.
- An incomplete mesh now tells the user how to fix it ("keep your face
  straight on, in bright light, with nothing covering it"), still including
  how many landmarks came back (e.g. "Only 412 of 468…").
- Verified by code inspection that the other suspects are not the cause:
  minification/R8 is off in `android/app/build.gradle.kts` (ProGuard keep
  rules for ML Kit / MediaPipe / GMS were added as insurance), no isolate or
  `compute` is used anywhere, and the APK bundles the ML Kit model assets.

### Added: on-device Error Logs screen
- New singleton `ErrorLogger` records only errors and warnings (never
  info/debug, never photos or personal data) as newline-delimited JSON in the
  app documents directory (`error_log.jsonl`), capped at 200 entries / ~200 KB
  with the oldest entries dropped first.
- Every entry carries an ISO timestamp, level, source (camera / facemesh /
  analysis / ui / app), error type, message, a stack trace truncated to ~1500
  characters, the app version, the Android version, the device model, and
  small context such as a landmark count.
- `FlutterError.onError`, `PlatformDispatcher.instance.onError`,
  `runZonedGuarded`, and the camera, face-mesh, photo-prep and analysis catch
  blocks all record into it. The logger itself is fully guarded and writes
  asynchronously, so it can never crash or stall the app.
- The home screen gains an "Error Logs" module: newest entries first, tap for
  full detail, with **Copy all**, **Share** (a plain-text file via the system
  sheet) and **Clear logs** buttons. An empty log shows "No errors logged".

### Tests
- `test/error_logger_test.dart`: entry cap, ~200 KB size rotation, entry
  fields, a throwing storage backend, and widget checks of the Error Logs
  screen (with a fake error, and empty).
- `test/fixed_face_ratios_test.dart`: exact expected symmetry, thirds and jaw
  angle for a fixed synthetic face, plus scale invariance.
