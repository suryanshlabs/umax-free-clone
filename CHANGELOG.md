# Changelog

## 1.3.0+6 — measurement honesty, BMI separation, cleanup

### Removed: the Potential Score and every grade
- The report used to add 8-15 hypothetical points of "headroom" and label the
  result Excellent / Strong / Balanced / Room to grow / Focus area. Neither is a
  defensible output of a 2D landmark measurement, so both are gone:
  `AnalysisReport` no longer has `potentialScore`, `potentialGain`, `grade` or
  `gradeBlurb`, and the results screen no longer has a projection card.
- What remains is a 0-100 **agreement** value per measurement (how close it is to
  a stated reference) plus their weighted mean. The UI calls it agreement
  everywhere and states it is not an attractiveness score.
- Old `scan_history.json` files that contain `grade`/`potential` still load; the
  keys are ignored and the band is derived from the score, so a retired rating
  cannot reappear in history. The bundled `potential_score_test.dart` was removed
  because the feature it tested no longer exists.

### Fixed: landmark mapping and measurement errors
- **Symmetry** now measures four mirrored landmark pairs (outer eyes, inner eyes,
  mouth corners, cheek edges) against the face's own midline through the nasion
  (`168`) and chin (`152`), instead of one nose point to two eye corners. The old
  formula counted a wide interpupillary distance as asymmetry and was highly
  sensitive to a single noisy landmark.
- **Facial thirds** now end the middle third at the subnasale (midpoint of the
  nostril wings `94`/`195`) instead of the radix (`2`). The old boundary made the
  middle third artificially short and pushed the error into the lower third.
- Landmark constants moved to documented names (`nasion`, `leftEyeOuter`,
  `mouthLeft`, ...) with the canonical MediaPipe topology recorded next to them,
  and the reader's "needed landmarks" set follows the new names.
- Added pose and quality validation: incomplete mesh, non-finite landmark,
  zero scale, implausible face-width/eye-span ratio, inverted vertical order,
  partial-mesh and odd-spread capture notes. A distorted mesh is refused with an
  explanation instead of producing a confident number.

### Rewritten: feedback
- No weight-loss or calorie-deficit instructions, no target weights, no
  "body composition is the lever" framing, no praise ("this is a defined, tapered
  jaw") and no attractiveness claims. Notes are now measurement notes, capture
  factors, the limits of what a frontal photo can show, and one honest medical
  caveat for a new one-sided change.
- Wiki body-composition and diet entries were rewritten the same way: they explain
  concepts and explicitly say the app gives no diet plan, calorie target or weight
  goal, and that BMI is a separate screening tool.

### BMI is a separate tool
- New independent **BMI Calculator** home module: metric/imperial input, the
  `weight_kg / (height_m²)` formula, validation, Calculate/Reset, result card and
  limitations. Adult bands apply only to adults; under-18 shows the raw value with
  an age-specific-reference explanation and no category. Nothing is saved and it
  has no path into facial analysis.
- Face onboarding asks only an optional gender (Male / Female / Another identity
  or prefer to self-describe / Prefer not to say / skip). Age, height, weight and
  BMI were removed from the face flow and from saved scans.

### Disabled: fake Multi-Angle Profile Scan
- The three-photo flow could never produce a reading: the bundled detector is
  frontal only, so every angle printed "No reading". The dead pipeline
  (`profile_report.dart`, `profile_analysis_controller.dart`,
  `multiangle_scan_sheet.dart`, `processing_screen_multiangle.dart`,
  `results_screen_multiangle.dart`) was deleted and the home tile now explains
  why the feature is unavailable.

### Neutral: comparison
- "Friend VS Mode" is now **Compare Reports**. The winner/leaderboard/verdict
  logic (`winsAfter`, `winsBefore`, `leader`, "A wins"/"B wins", trophy icon) is
  gone. Deltas report direction only ("higher"/"lower"), both directions use the
  same neutral colour, and the summary states that the app is comparing
  measurements from two photos, not ranking people.

### Privacy and cleanup
- Deleting a scan now deletes its prepared photo; clearing history deletes all of
  them; loading history sweeps prepared squares no saved scan references; the
  camera/gallery copy is deleted after the square is prepared. Previously the
  preparation step blindly deleted every prepared file, including the one the
  newest scan pointed at.
- New `lib/core/image_store.dart` only touches files inside the app's temporary
  directory whose names carry this app's prefix.

### Performance
- Image decode is capped at 2× the 1080 px output instead of decoding the full
  12 MP capture, cutting the peak bitmap allocation from roughly 48 MB to 18 MB -
  the case that matters on a 3 GB device.

### Other
- Home module tiles updated (BMI Calculator added, Compare Reports renamed,
  Multi-Angle marked unavailable).
- README rewritten for the new measurement definitions, validation gates, privacy
  behaviour and module list. Tests extended to 135.


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
