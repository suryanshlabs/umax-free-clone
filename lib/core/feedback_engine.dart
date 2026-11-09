import 'metrics.dart';
import 'report.dart';

/// Informational notes attached to each measurement.
///
/// Rules this file follows, and which any edit should keep:
///
/// * No attractiveness claims. A geometric agreement value says how close a
///   measurement is to a stated reference, not how someone looks.
/// * No weight-loss, diet, supplement or "fat loss reveals the jaw" advice, and
///   no target weights. BMI lives in its own tool and never feeds back here.
/// * No structural promises. Bone does not change in response to a habit, and
///   surgery/filler are framed as clinical decisions, not improvements.
/// * No "fix your asymmetry" framing. Most asymmetry is normal and stable.
/// * The strongest lever on every one of these numbers is the photograph.
class FeedbackEngine {
  const FeedbackEngine();

  List<AdviceItem> forEyeSymmetry(RawFaceMetrics metrics, double score) {
    if (score >= 85) {
      return <AdviceItem>[
        const AdviceItem(
          title: 'Nothing here is unusual',
          detail:
              'All four mirrored pairs sat close to the midline in this photo. '
              'Re-scan under the same light if you want a comparable number; '
              'small differences between scans are normal and are more often '
              'the camera than the face.',
          evidence: EvidenceStrength.measurement,
        ),
        const AdviceItem(
          title: 'Perfect mirror symmetry is not a target',
          detail:
              'Nobody is exactly mirrored, and landmark detection on two '
              'photos of an unchanged face already varies by a fraction of a '
              'percent. A reading near zero is not better than a reading a '
              'little above it; both describe normal faces.',
          evidence: EvidenceStrength.moderate,
        ),
      ];
    }

    final List<AdviceItem> advice = <AdviceItem>[
      AdviceItem(
        title: 'Check the capture before reading anything into this',
        detail:
            'Your mirrored pairs averaged '
            '${metrics.eyeAsymmetryPercent.toStringAsFixed(1)}% away from the '
            'midline. A head turned a few degrees, a phone held to one side, or '
            'uneven light moving the detected face edge will produce that on a '
            'perfectly symmetrical face. Retake at eye level, 50-70 cm away, '
            'with the phone square to your face and even light.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Asymmetry is common and usually stable',
        detail:
            'Facial asymmetry of a few percent is typical across populations '
            'and generally changes slowly. This app cannot tell you whether a '
            'difference is new: only a comparison with older photos, or an '
            'examination, can do that.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'If the difference is new, it is a medical question',
        detail:
            'A sudden change in one side of the face - drooping, weakness, '
            'numbness, or a change in speech - needs prompt medical assessment '
            'and is not something to track in an app. Long-standing, stable '
            'differences are a different matter and are usually not a health '
            'concern at all.',
        evidence: EvidenceStrength.strong,
      ),
    ];
    return advice;
  }

  /// Notes for the chin angle. Body composition, weight, height and age are
  /// deliberately not inputs: the BMI tool is separate and can never reword a
  /// facial measurement.
  List<AdviceItem> forJawline(RawFaceMetrics metrics, double score) {
    final String reading = metrics.jawAngleDegrees.toStringAsFixed(0);
    if (score >= 85) {
      return <AdviceItem>[
        AdviceItem(
          title: 'This is a narrow chin angle',
          detail:
              'Your jaw contour converges sharply towards the chin ($reading'
              '\u00B0 between landmarks 172 and 397). That is one geometric '
              'shape among many, not a better one. The measurement is a '
              'front-view chin angle, and it moves with head pitch, so compare '
              'it only against your own scans taken the same way.',
          evidence: EvidenceStrength.measurement,
        ),
        const AdviceItem(
          title: 'Keep the pose identical to compare',
          detail:
              'A few degrees of chin lift changes this angle more than anything '
              'else you could do between scans. Photograph at eye level with '
              'your face relaxed and your teeth lightly together.',
          evidence: EvidenceStrength.measurement,
        ),
      ];
    }

    return <AdviceItem>[
      AdviceItem(
        title: 'What this angle does and does not measure',
        detail:
            'The two jaw-contour landmarks made a $reading\u00B0 angle at your '
            'chin in this photo. That describes the front silhouette of your '
            'lower face. It is not a gonial angle (those need a true side view '
            'and a clinical landmark set), and it is not a measure of jaw '
            'strength, bite or health.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Pose, lens and expression move it most',
        detail:
            'Chin height, camera distance and focal length all change the '
            'apparent angle: a phone held close widens the lower face, and a '
            'raised chin flattens it. For a comparable reading, use the same '
            'distance and eye level every time.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Structural options are a clinical decision',
        detail:
            'Orthodontics and jaw surgery can change the lower face, and both '
            'carry real cost and risk. Whether either is appropriate is a '
            'question for a dentist or maxillofacial specialist who can examine '
            'you in person. A photo measurement is not a basis for that '
            'decision, and this app does not recommend one.',
        evidence: EvidenceStrength.moderate,
      ),
    ];
  }

  List<AdviceItem> forFacialThirds(RawFaceMetrics metrics, double score) {
    final String dominant = metrics.dominantThird;
    return <AdviceItem>[
      AdviceItem(
        title: 'The hairline is the least reliable point',
        detail:
            'Your split reads ${(metrics.upperThirdFraction * 100).round()} / '
            '${(metrics.middleThirdFraction * 100).round()} / '
            '${(metrics.lowerThirdFraction * 100).round()} percent '
            '(hairline-brow / brow-nose base / nose base-chin), with the '
            '$dominant the largest. The upper boundary is estimated from a '
            'landmark near the hairline, so a fringe, a receding hairline or '
            'bright light on the forehead can move this reading without '
            'anything about the face changing.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Keep the head level',
        detail:
            'A few degrees of head tilt or chin lift shifts the vertical thirds '
            'more than any other measurement in this app. Keep the phone '
            'vertical, your eyes level with the lens, and a neutral expression.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Proportions are descriptive, not a standard to meet',
        detail:
            'The 1 : 1 : 1 split is a classical convention, not a health '
            'threshold, and real faces vary widely around it. Nothing in this '
            'measurement indicates a problem with how your face works, bites or '
            'ages.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Surgery and fillers are not an app decision',
        detail:
            'These proportions can be changed clinically, but each option '
            'carries cost, risk and irreversible outcomes. That conversation '
            'belongs with a qualified professional who can examine you in '
            'person, not with a selfie measurement.',
        evidence: EvidenceStrength.moderate,
      ),
    ];
  }

  /// The lowest-agreement measurement, with observation steps.
  WeaknessInsight coreWeakness(List<MetricResult> metrics) {
    if (metrics.isEmpty) {
      throw ArgumentError.value(metrics, 'metrics', 'needs one metric');
    }
    final List<MetricResult> ranked = List<MetricResult>.of(metrics)
      ..sort((MetricResult a, MetricResult b) => a.score.compareTo(b.score));
    final MetricResult lowest = ranked.first;
    final MetricResult runnerUp = ranked.length > 1 ? ranked[1] : ranked.first;

    return WeaknessInsight(
      metricId: lowest.id,
      title: lowest.title,
      score: lowest.score,
      rawValue: lowest.rawValue,
      gapToNextBest: (runnerUp.score - lowest.score).clamp(0.0, 100.0),
      why: _whyLowest(lowest, runnerUp),
      steps: _roadmapFor(lowest),
    );
  }

  String _whyLowest(MetricResult lowest, MetricResult runnerUp) {
    final String gap = (runnerUp.score - lowest.score) <= 0.5
        ? 'it is effectively tied with ${runnerUp.title} '
              '(${runnerUp.score.toStringAsFixed(0)}/100 agreement), so there '
              'is no single lowest measurement in this scan'
        : 'it sits ${(runnerUp.score - lowest.score).toStringAsFixed(0)} points '
              'below ${runnerUp.title} '
              '(${runnerUp.score.toStringAsFixed(0)}/100 agreement)';
    return '${lowest.title} has the lowest agreement with its reference in this '
        'scan at ${lowest.score.toStringAsFixed(0)}/100, and $gap. Read that as '
        'a property of one measurement in one photo, not as a defect: the '
        'capture conditions below usually move it more than anything else, and '
        'a low value is not a health finding.';
  }

  List<RoadmapStep> _roadmapFor(MetricResult metric) {
    final List<RoadmapStep> habits = switch (metric.id) {
      MetricId.eyeSymmetry => _symmetryHabits,
      MetricId.jawline => _jawlineHabits,
      MetricId.facialThirds => _thirdsHabits,
    };
    final String raw = metric.rawValue;
    return <RoadmapStep>[
      RoadmapStep(
        stage: RoadmapStage.now,
        title: 'Take one baseline photo the same way',
        detail:
            'Same room, same window light, phone vertical at eye level, 50-70 '
            'cm away, neutral face, hair off the forehead. Every later scan is '
            'judged against this frame. Today your reading is $raw.',
        evidence: EvidenceStrength.measurement,
      ),
      ...habits,
      const RoadmapStep(
        stage: RoadmapStage.week5plus,
        title: 'Re-scan and compare with the same light',
        detail:
            'Open Compare and put this scan next to the new one. Read the three '
            'measurements rather than the combined number: a point or two of '
            'movement in one measurement is indistinguishable from capture '
            'noise. Three scans a week apart is a trend; one scan is a '
            'snapshot.',
        evidence: EvidenceStrength.measurement,
      ),
    ];
  }

  static const List<RoadmapStep> _symmetryHabits = <RoadmapStep>[
    RoadmapStep(
      stage: RoadmapStage.weeks1to2,
      title: 'Hold the camera square to your face',
      detail:
          'The largest error in this measurement is a phone held slightly to '
          'one side or a face turned a few degrees. A small tripod or a stack '
          'of books at eye level is the most reliable improvement you can make.',
      evidence: EvidenceStrength.measurement,
    ),
    RoadmapStep(
      stage: RoadmapStage.weeks3to4,
      title: 'Repeat the scan instead of changing a habit',
      detail:
          'Take three scans on different days with the same setup. If the '
          'readings agree, the difference is real for this measurement; if they '
          'swing by several percent, the variation is the camera and the number '
          'should not be tracked at all.',
      evidence: EvidenceStrength.measurement,
    ),
  ];

  static const List<RoadmapStep> _jawlineHabits = <RoadmapStep>[
    RoadmapStep(
      stage: RoadmapStage.weeks1to2,
      title: 'Standardise chin height',
      detail:
          'Rest your eyes level with the lens and keep your teeth lightly '
          'together. Raising or lowering the chin changes the measured angle '
          'more than any habit will, and it is the easiest thing to control.',
      evidence: EvidenceStrength.measurement,
    ),
    RoadmapStep(
      stage: RoadmapStage.weeks3to4,
      title: 'Keep camera distance constant',
      detail:
          'A phone held close widens the lower face and changes the apparent '
          'jaw contour. Pick a distance (about an arm\'s length) and use it for '
          'every scan so the comparison is like for like.',
      evidence: EvidenceStrength.measurement,
    ),
  ];

  static const List<RoadmapStep> _thirdsHabits = <RoadmapStep>[
    RoadmapStep(
      stage: RoadmapStage.weeks1to2,
      title: 'Expose the hairline for the scan',
      detail:
          'The upper third is bounded by a landmark near the hairline, so hair '
          'over the forehead or a strong highlight hides the boundary and '
          'shortens the reading. Push hair back and use soft, even light.',
      evidence: EvidenceStrength.measurement,
    ),
    RoadmapStep(
      stage: RoadmapStage.weeks3to4,
      title: 'Compare trends, not single scans',
      detail:
          'Facial proportions change little in weeks. If three scans a week '
          'apart agree, that is your baseline; a single scan that disagrees '
          'with them is more likely a different camera position.',
      evidence: EvidenceStrength.measurement,
    ),
  ];
}
