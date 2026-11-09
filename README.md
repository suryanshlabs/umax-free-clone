# Face Geometry

An offline facial-geometry app. Google's MediaPipe Face Mesh (468 landmarks,
shipped through ML Kit's on-device face mesh detector) runs entirely inside the
app process; every distance, angle, agreement value and note is computed in Dart
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
Decoding is capped at 2× the 1080-pixel output, which keeps the peak bitmap
around 18 MB instead of ~48 MB on a 3 GB phone.
MediaPipe returns pixel coordinates; the reader divides by the upright pixel
height and detects (and aspect-corrects) SDK builds that return 0..1 instead.

| Metric | Landmarks | Formula |
| --- | --- | --- |
| **Symmetry residual** | midline `168` (nasion) → `152` (chin); pairs `33/263`, `133/362`, `61/291`, `234/454` | For every mirrored pair, the difference between the perpendicular distances to the face's own midline, divided by the interocular distance and averaged over the four pairs. Measuring against the face's own midline (instead of one nose point) removes the old errors: a large interpupillary distance no longer reads as asymmetry, and a turned head moves both points of a pair together, which cancels. |
| **Chin angle** | jaw edges `172` / `397`, chin `152` | The interior angle at the chin between the two jaw-contour vectors: `acos( (a·b) / (|a||b|) )`. It is a frontal lower-face contour measurement, not a clinical gonial angle. |
| **Facial thirds** | hairline `10` → glabella `9` → subnasale (midpoint of `94`/`195`) → chin `152` | Vertical spans `10→9`, `9→subnasale`, `subnasale→152`, each divided by the total, compared with an even `1 : 1 : 1` split. |

### Pose and landmark validation

The service refuses a measurement instead of scoring a broken mesh:

* **Completeness** — fewer than 468 points is an error; the reader only needs the
  landmarks the measurements read, so one duplicate index no longer turns a good
  face into "no reading".
* **Finite coordinates** — any NaN/Infinity landmark is rejected by index.
* **Scale** — a zero-length interocular reference is rejected.
* **Plausibility** — face width ÷ interocular distance must be `1.5-4.2`, and
  nasion-to-chin ÷ interocular `0.9-3.2`. Outside those, the mesh is distorted
  (occlusion, extreme angle, failed detection) and is refused with an explanation.
* **Vertical order** — glabella above subnasale above chin, within 2% of face
  height; otherwise the mesh is upside down and is refused.
* **Pose notes** — yaw index below `0.82` (head turned) and roll beyond `8°` are
  reported as capture notes; a partial mesh or odd spread ratio adds a note too.

## Scoring and calibration

Every score is `0–100` and every threshold lives in one place:
`lib/core/calibration.dart`. Nothing is hard-coded in the scoring engine.

| Agreement value | Definition | Defaults |
| --- | --- | --- |
| Symmetry | `100 − penalty × max(0, residual − tolerance)` | tolerance `0.6%`, penalty `12` per percent |
| Chin angle | linear from best angle (`100`) to worst angle (`0`) | best `95°`, worst `150°` |
| Facial thirds | `100 − penalty × max(0, deviation − freeBand)` | free band `0.16`, penalty `130` |
| Combined | weighted mean, shown as agreement only | symmetry `0.38`, jawline `0.34`, thirds `0.28` |

**These bands are heuristics, not clinical norms.** There is no peer-reviewed,
universally accepted scale for "symmetry from a selfie", and the app never claims
one. Landmarks `172`/`397` sit part-way along the jaw contour, so a typical
frontal adult face measures ~105–125°, which is why the best-angle reference is
95° rather than a textbook value.

There is **no potential score, no projection and no grade**. An earlier version
added 8–15 points of hypothetical headroom and labelled the result
"Excellent/Strong/Balanced"; both implied a rating the geometry cannot support.
The combined number is now labelled agreement with the references, and the
results screen says explicitly that it is not an attractiveness score.

## Advice generation

`lib/core/feedback_engine.dart` produces band-specific, actionable text — not a
template with the number pasted in — and labels every item with its evidence
strength so weak claims never look as solid as strong ones:

* **Measurement factor** — head tilt, lens distance, hairline placement, chin
  height and repeated scans: the things that actually move these numbers most.
* **Moderate** — that asymmetry is common and stable, that proportions are
  descriptive rather than a standard to meet, that surgery/fillers are clinical
  decisions.
* **Strong** — the one medical statement the app makes: a *new* one-sided facial
  change with drooping, numbness or weakness needs prompt medical assessment.

The advice contains no weight-loss or diet instructions, no target weights, no
attractiveness claims and no promise that a habit changes bone. BMI is a separate
tool and never feeds back into a facial measurement.

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
    scoring_engine.dart           0-100 agreement values, warnings
    feedback_engine.dart          research-informed advice
    report.dart                   agreement values + notes + share text
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
      score_ring.dart             animated agreement ring
      metric_card.dart            agreement bar + notes
```

## Tests

```bash
flutter test
```

The suite covers:

* each measurement against hand-computed geometry (midline residuals, angles,
  thirds with the subnasale boundary),
* scale invariance (same face, 137× larger, identical values),
* pose guards (turned head, tilted head) and the new plausibility gates
  (distorted width ratio, inverted vertical order),
* validation failures (short mesh, degenerate mesh) and tolerance of extra iris
  landmarks (`468`–`478`),
* agreement clamping, weighting, band labels and the safety-note threshold,
* removal of the potential score and grades (the report has no such fields),
* neutral comparison arithmetic (no winner, no "improved"/"declined" wording),
* BMI maths, imperial conversion, validation, under-18 safeguards and the
  absence of any BMI input in the face flow,
* scan-history compatibility: an old file keeps every scan, drops body fields,
  and new scans carry no `profile`, `age`, `bmi` or `height` keys,
* the full controller pipeline and the rendered results dashboard, using a fake
  detector.

`flutter analyze` runs clean with `strict-casts`, `strict-raw-types` and
dead-code/unused-import treated as errors. In this repository the suite is 135
tests and analysis reports no issues, on Flutter 3.47.9 / Dart 3.13.7.

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

Everything is computed on the device; the app has no `INTERNET` permission in its
release manifest. Photos are prepared into a private temporary directory, and the
app now cleans up after itself:

* deleting a saved scan deletes its prepared photo (once no other scan uses it),
* clearing history deletes every prepared photo,
* on load, prepared squares that no saved scan references are swept,
* the picker/camera copy is deleted once the prepared square exists, so one scan
  leaves one file rather than two.

`AnalysisReport.toShareText()` copies a text summary to the clipboard only when
you tap **Copy**; the photo is never shared by the app itself. The `.umax` export
contains measurements and capture notes, no image.

## License and building on this

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it inside a paid app, strip
the branding out, change every threshold. No attribution required, though a link
back is appreciated. It is a measurement tool, not medical software; the
"not a medical device" caveat in the app should stay.

Where to start if you want to change behaviour:

| I want to | Change |
| --- | --- |
| Make scoring stricter or looser | `lib/core/calibration.dart` — every threshold and weight lives there and nowhere else |
| Change the advice shown | `lib/core/feedback_engine.dart` — score bands map to text, each item carries an evidence label |
| Add a new measurement | `lib/core/facial_analysis_service.dart` (extend `RawFaceMetrics`), then score it in `scoring_engine.dart` and add a `MetricId` in `report.dart` |
| Restyle the app | `lib/ui/theme.dart`, then the painters in `lib/ui/widgets/` |
| Support another platform | implement `FaceMeshSource` in `lib/ml/` and hand it to `AnalysisController`; nothing in `lib/core/` changes |

Pull requests are welcome. `flutter test` and `flutter analyze` are expected to be
clean before a PR — the bundled CI workflow runs both on every push, and the
detector is isolated behind an interface so new features can be tested without a
phone.

## Download and install

A ready-to-install APK is attached to the [latest release](../../releases/latest):

* **app-release.apk** — universal build covering arm64-v8a, armeabi-v7a and x86_64
  (so it also runs in an emulator), roughly 80 MB, Android 5.0 and newer.
* The ML Kit model is bundled, so it works offline from the very first launch.
* It is signed with the debug key, which is fine for sideloading but not for
  Play Store distribution. Replace `signingConfig` in
  `android/app/build.gradle.kts` with your own keystore before publishing.

To install: download the APK on the phone, tap it, allow "install unknown apps"
for your browser or file manager when prompted, then install. Because it is not
signed for the Play Store, Android will show a warning — that is expected for
any sideloaded build.

Every push to `main` also builds the APK on GitHub's runners
(`.github/workflows/build-apk.yml`) and attaches it to the run as a downloadable
artifact, so a build is possible without a local Android toolchain.

## The modules

* **Face Analyze** — camera → 468-landmark mesh → three geometric measurements.
* **BMI Calculator** — an independent tool with metric/imperial input, the correct
  formula, validation, adult bands only for adults, and no connection to facial
  analysis. It saves nothing and gives no targets or diet plan.
* **Compare My Progress** — every finished scan is stored on the device; any two
  are compared measurement by measurement, oldest against newest by default.
* **Compare Reports** — the same neutral arithmetic for two reports, with no
  winner and no ranking. Differences inside the noise band are shown as even.
* **Looksmaxing Wiki & Saved Reports** — evidence-graded notes on what a 2D photo
  can and cannot tell you, plus every saved scan with per-entry delete.
* **Error Logs** — on-device crash log, copy/share/clear, never leaves the phone.

**Multi-Angle Profile Scan is unavailable in this build.** Measuring a profile
angle needs a side-view landmark model; the bundled detector is frontal only, so
the old screen could only ever print "No reading". The entry point now says so
instead of pretending, and the dead three-photo flow was removed.

## Failure handling

Detection has a 30-second deadline at two levels — around ML Kit itself in
`FaceMeshReader` and around the whole read in `AnalysisController` — so a wedged
platform channel lands on the readable error panel instead of a scanning
animation that never stops. Zero landmarks, a platform exception and a timeout
all produce the same copy, which lives in one constant
(`faceNotDetectedMessage`).

EXIF orientation is parsed straight out of the JPEG's APP1 segment
(`lib/ml/exif_orientation.dart`): the tag decides which side is the upright
height — the unit every measurement is divided by — and, if a detector ever hands
back sensor-space points, those are rotated upright too. The rotation is only
applied when the geometry proves it is needed, because rotating an already-upright
mesh would tilt every angle in the app.
