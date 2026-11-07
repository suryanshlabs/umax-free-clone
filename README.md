# Face Geometry

An offline facial-geometry app. Google's MediaPipe Face Mesh (468 landmarks,
shipped through ML Kit's on-device face mesh detector) runs entirely inside the
app process; every distance, angle, score and piece of advice is computed in Dart
on the phone. There is no backend, no account, no analytics and no upload.

Built with **Flutter** and the **`google_mlkit_face_mesh_detection`** plugin,
which is Google's production packaging of MediaPipe Face Mesh for mobile.

---

## Why Flutter, and why Android

* Flutter gives one codebase, a native 60 fps camera preview and canvas-drawn
  animation for the guide and the scan, with no web view in the loop.
* The mesh runs through ML Kit, which is the only supported way to get
  MediaPipe's 468-point model on a phone without hand-writing JNI/C++ bindings.
* **The mesh detector is Android-only today.** Google's Face Mesh Detection API
  is still in beta and ML Kit has not shipped the iOS implementation; the Flutter
  plugin therefore includes an iOS stub that throws. This project is configured
  for Android only. If you need iOS later, the replacement is MediaPipe Tasks
  Vision's `FaceLandmarker` through a native Swift module — the entire analysis
  layer of this app (`lib/core/`) is pure Dart and portable as-is, because it
  only consumes a `List<Vec2>`.

Requirements: Flutter 3.44+ / Dart 3.12+ (developed and tested on Flutter
3.47.9 / Dart 3.13.7), an Android device or emulator with a camera, `minSdk` 21+
(Flutter's default already satisfies this).

## Run it

```bash
cd facial_analysis_app
flutter pub get
flutter run          # with an Android device or emulator attached
```

Release build for personal installs:

```bash
flutter build apk --release
```

The generated `android/app/build.gradle.kts` signs release builds with the debug
key so a personal install works out of the box. Replace that with your own
signing config before distributing through a store.

### Permissions

`android/app/src/main/AndroidManifest.xml` declares exactly one dangerous
permission:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

There is deliberately **no `INTERNET` permission** in the main manifest, so the
app cannot phone home even if a dependency tried to. Note that Flutter's debug
and profile manifests add `INTERNET` automatically for the hot-reload socket;
that permission is absent from release builds.

The detector ships inside the APK: the plugin links
`com.google.mlkit:face-mesh-detection`, ML Kit's **bundled** variant, so the
468-point model needs no first-run download and no Play Services. A fresh install
works in airplane mode.

## How the pipeline works

```
CameraScreen  ──takePicture──▶  ProcessingScreen  ──▶  ResultsScreen
   │                                   │                    │
   │ camera plugin preview             │ AnalysisController  │ AnalysisReport
   │ + FaceGuidePainter overlay        │ (ChangeNotifier)    │
   ▼                                   ▼                    ▼
 still photo  ──▶  FaceMeshReader  ──▶  FacialAnalysisService  ──▶  ScoringEngine
                   (ML Kit, 468 pts)     (pure geometry)            (+ FeedbackEngine)
```

* **Stills, not streams.** One high-resolution photo gives MediaPipe far more
  pixels per feature than a preview stream, and the measurement is a one-shot
  calculation. The camera is released while ML Kit works so the two pipelines
  never compete for the same hardware.
* **`lib/core/` has no Flutter imports** except where it must (nothing, in fact —
  it is plain Dart), which is why the maths is unit-testable without a device.
* **`FaceMeshSource`** is the seam between ML Kit and the app. The analysis
  controller depends on that interface, so the whole pipeline runs in tests
  against a fake detector.

## The three measurements

All coordinates are converted to fractions of image height before the maths runs,
so a 12 MP photo and a 1080p photo of the same face produce the same numbers.
MediaPipe returns pixel coordinates; the reader divides by the upright pixel
height and detects (and aspect-corrects) SDK builds that return 0..1 instead.

| Metric | Landmarks | Formula |
| --- | --- | --- |
| **Eye symmetry** | nose bridge `1`, outer eye corners `33` / `263` | `d_left = |1−33|`, `d_right = |1−263|`, asymmetry `= |d_left − d_right| / mean(d_left, d_right) × 100`. The ratio `d_left/d_right` is reported alongside it. |
| **Jawline angularity** | jaw edges `172` / `397`, chin `152` | The interior angle at the chin between the two jaw-edge vectors: `acos( (a·b) / (|a||b|) )`. Smaller angle = the edges converge more sharply = a more tapered jaw. |
| **Facial thirds** | hairline `10` → glabella `9` → nose base `2` → chin `152` | Vertical spans `10→9`, `9→2`, `2→152`, each divided by the total. Reported as ratios against the middle third (`1.00`), compared with the ideal `1 : 1 : 1`. |

Pose guards are computed from the same mesh and reported as capture notes rather
than silently ignored:

* **Yaw index** — `min(d_left, d_right) / max(d_left, d_right)` using the nose
  bridge's distance to face edges `234` / `454`; below `0.82` the head was turned.
* **Roll** — the signed tilt of the `33 → 263` line; beyond `8°` the vertical
  thirds are unreliable.

### An honest note about landmark `2`

In the canonical MediaPipe mesh, index `2` sits at the top of the nose bridge
(the radix), not at the base of the nose. The middle third therefore measures
glabella-to-radix, which reads shorter than a textbook brow-to-subnasale third.
This is implemented exactly as specified, and the app says so in the thirds card
under "Why this score is strict". If you would rather measure the true subnasale,
`FaceLandmarks` already exposes `noseWingLeft` (`94`) and `noseWingRight` (`195`);
swap the `noseBase` lookup in `FacialAnalysisService` for their midpoint.

## Scoring and calibration

Every score is `0–100` and every threshold lives in one place:
`lib/core/calibration.dart`. Nothing is hard-coded in the scoring engine.

| Score | Definition | Defaults |
| --- | --- | --- |
| Eye symmetry | `100 − penalty × max(0, asymmetry − tolerance)` | tolerance `0.3%`, penalty `12` per percent |
| Jawline | linear from best angle (`100`) to worst angle (`0`) | best `90°`, worst `150°` |
| Facial thirds | `100 − penalty × max(0, deviation − freeBand)` | free band `0.12`, penalty `130` |
| Overall | weighted mean | symmetry `0.38`, jawline `0.34`, thirds `0.28` |

**These bands are heuristics, not clinical norms.** There is no peer-reviewed,
universally accepted scale for "jawline angularity from a selfie", and the app
never claims one. Landmarks `172`/`397` sit roughly halfway along the jawline, so
a typical frontal adult face measures ~105–125°, which is why the best-angle
reference is 90° rather than some textbook value. Recalibrate against photos you
trust and the rest of the pipeline stays untouched.

Because the thirds score compares against a true `1 : 1 : 1` measured with the
radix landmark, most faces land in the 40–60 range on that metric. That is
expected, and the results screen explains it: compare your scans with each
other, not with 100.

## Advice generation

`lib/core/feedback_engine.dart` produces band-specific, actionable text — not a
template with the number pasted in — and labels every item with its evidence
strength so weak claims never look as solid as strong ones:

* **Strong** — body composition revealing the jawline, camera angle and posture.
* **Moderate** — sleep position and chewing side for asymmetry, sodium/alcohol
  puffiness, orthodontic options.
* **Limited** — tongue posture ("mewing"): framed as better resting posture,
  explicitly *not* as a way to remodel an adult mandible.
* **Measurement factor** — things like head tilt, lens distance and hairline
  placement that move the number without changing the face.

When asymmetry is at or above `6%` the report adds a safety note: most asymmetry
is normal, but a *new* one-sided change with drooping, numbness or weakness needs
a doctor, not a skincare routine.

## Project layout

```
lib/
  main.dart                       app entry, theme, provider
  core/                           pure Dart, no Flutter
    vector.dart                   2D point maths
    landmarks.dart                MediaPipe indices used
    metrics.dart                  RawFaceMetrics value object
    facial_analysis_service.dart  the three measurements + validation
    calibration.dart              every threshold in one place
    scoring_engine.dart           0-100 normalisation, grades, warnings
    feedback_engine.dart          research-informed advice
    report.dart                   scores + advice + share text
  ml/
    face_mesh_source.dart         FaceMeshReading + detector interface
    face_mesh_reader.dart         ML Kit adapter, coordinate normalisation
  state/
    analysis_controller.dart      idle → analysing → ready/failed
  ui/
    theme.dart                    dark palette, bands, typography
    camera_screen.dart            preview, guide, shutter, torch, errors
    processing_screen.dart        scan animation over the captured photo
    results_screen.dart           dashboard, notes, disclaimer, copy summary
    widgets/
      face_guide_painter.dart     camera silhouette overlay
      scanning_painter.dart       canvas mesh + sweep animation
      score_ring.dart             animated score ring
      metric_card.dart            score bar + advice tiles
```

## Tests

```bash
flutter test
```

The suite covers:

* each measurement against hand-computed geometry (angles, percentages, thirds),
* scale invariance (same face, 137× larger, identical scores),
* pose guards (turned head, tilted head),
* validation failures (short mesh, degenerate mesh) and tolerance of extra iris
  landmarks (`468`–`478`),
* score clamping, weighting, grade bands and the safety-note threshold,
* the full controller pipeline and the rendered results dashboard, using a fake
  detector.

`flutter analyze` runs clean with `strict-casts`, `strict-raw-types` and
dead-code/unused-import treated as errors. In this repository: 24 tests pass,
analysis reports no issues, on Flutter 3.47.9 / Dart 3.13.7. The Android APK is
not built here (the build environment has no Android SDK), so the first
`flutter run` on a real phone is still yours to do — the camera path and the
native ML Kit call are the parts that only a device can confirm.

## Known limitations

* **2D geometry only.** A selfie is a perspective projection. Lens distance,
  focal length and head rotation all change measured angles, which is why capture
  notes are shown instead of being swallowed.
* **Landmark noise.** ML Kit's own jitter is roughly ±0.3% on the symmetry
  metric; the calibration free bands absorb it.
* **Small faces.** Below ~15% of frame height the landmark spacing is too coarse
  to score reliably; the controller adds a capture note when that happens.
* **No iOS build.** See the platform note above.
* **Not a medical device.** No diagnosis, no attractiveness rating, and the
  advice is general information rather than personal medical or dermatological
  guidance.

## Privacy

Everything is computed on the device. Photos live in the app's cache directory
because the camera plugin writes them there; the app never deletes them, so clear
the app cache if you want them gone. `AnalysisReport.toShareText()` copies a text
summary to the clipboard only when you tap **Copy** — the photo is never shared
by the app itself.
