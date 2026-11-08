import 'metrics.dart';
import 'report.dart';
import 'user_profile.dart';

class FeedbackEngine {
  const FeedbackEngine();

  List<AdviceItem> forEyeSymmetry(RawFaceMetrics metrics, double score) {
    final String worseSide = metrics.eyeDistanceRatio >= 1 ? 'left' : 'right';
    if (score >= 85) {
      return <AdviceItem>[
        const AdviceItem(
          title: 'Keep the conditions consistent',
          detail:
              'This reading is inside the mirrored band, so the useful next '
              'step is comparability: same room, same light, same distance, '
              'same time of day. Re-scan weekly and watch the trend, not the '
              'single number.',
          evidence: EvidenceStrength.measurement,
        ),
        const AdviceItem(
          title: 'Do not chase zero',
          detail:
              'Almost every face is a few percent asymmetric, and a perfect '
              '40/40 split is not the goal. Differences under about 3% are '
              'within the range that landmark detection itself can produce on '
              'two photos of the same unchanged face.',
          evidence: EvidenceStrength.moderate,
        ),
      ];
    }

    final List<AdviceItem> advice = <AdviceItem>[
      AdviceItem(
        title: 'Rule out the camera before the mirror',
        detail:
            'At this level the photo is usually the bigger variable. Holding '
            'the phone off-centre, tilting the head two degrees, or lighting '
            'one cheek more than the other moves this reading by more than any '
            'habit will. Your left-to-right eye-distance ratio came out at '
            '${metrics.eyeDistanceRatio.toStringAsFixed(2)} : 1 with the '
            '$worseSide side reading longer. Retake at eye level, 50–70 cm '
            'away, with even light.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Alternate sleep sides, or sleep on your back',
        detail:
            'Sustained pressure from one pillow side is the most commonly cited '
            'environmental contributor to soft-tissue facial asymmetry. The '
            'evidence is observational rather than experimental, so treat this '
            'as a free habit change rather than a guaranteed fix — but it costs '
            'nothing to rotate sides.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Chew on both sides',
        detail:
            'Habitual one-sided chewing loads one masseter and one '
            'temporomandibular joint harder, and dental research links it to '
            'measurable asymmetry in the lower face. Deliberately starting '
            'meals on the non-dominant side is the whole intervention.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Stop resting your chin in one hand',
        detail:
            'Repeated leaning puts steady pressure on one cheekbone and jaw '
            'edge for hours at a time. The effect per session is tiny; the '
            'cumulative effect of a decade of desk posture is the reason it '
            'shows up in photos.',
        evidence: EvidenceStrength.emerging,
      ),
    ];
    return advice;
  }

  List<AdviceItem> forJawline(RawFaceMetrics metrics, double score,
      {double? bmi, BmiCategory? bmiCategory}) {
    final bool prioritiseFat = bmiCategory == BmiCategory.overweight ||
        bmiCategory == BmiCategory.obese;
    final bool prioritiseFluid = prioritiseFat || (bmi ?? 0) >= 25;

    if (score >= 85) {
      return <AdviceItem>[
        const AdviceItem(
          title: 'This is a defined, tapered jaw',
          detail:
              'The jaw edges converge sharply towards the chin, which is the '
              'geometry people read as "angular". Nothing needs fixing. If you '
              'want a stronger front profile, the only lever left is leaning '
              'out further, and that is a body-composition decision, not a '
              'facial one.',
          evidence: EvidenceStrength.strong,
        ),
        AdviceItem(
          title: 'Protect it from puffiness',
          detail:
              'The jaw–neck border is the first thing a salty meal, alcohol or '
              'a short night blurs. If you are photographing something, keep '
              'the evening before low-sodium and get the sleep.',
          evidence: prioritiseFluid
              ? EvidenceStrength.strong
              : EvidenceStrength.moderate,
        ),
      ];
    }

    final bool isObtuse = metrics.jawAngleDegrees > 105;
    final String bmiNote = (bmi ?? 0) > 25
        ? ' With your BMI around ${(bmi ?? 0).toStringAsFixed(1)}, the face '
          'is one of the first places a body-composition change shows up.'
        : '';
    final String fluidNote =
        (bmiCategory == BmiCategory.overweight ||
                bmiCategory == BmiCategory.obese) &&
            (bmi ?? 0) > 0
        ? ' For you this is especially worth dialling in before a photo, '
          'because fluid reads as jaw softness more than it does at a lower BMI.'
        : '';
    final List<AdviceItem> advice = <AdviceItem>[
      AdviceItem(
        title: isObtuse
            ? (prioritiseFat
                ? 'Body composition is the main, immediate lever'
                : 'Body composition is the main lever')
            : 'Define the border before chasing the angle',
        detail:
            'What reads as a jawline is mostly the fat layer sitting over the '
            'mandible, and that layer is not spot-reducible. A modest calorie '
            'deficit, adequate protein and resistance training lowers fat '
            'everywhere, and the face usually shows it early because the fat '
            'layer there is thin. Your chin-to-jaw-edge angle measured '
            '${metrics.jawAngleDegrees.toStringAsFixed(0)}°.$bmiNote',
        evidence: EvidenceStrength.strong,
      ),
      AdviceItem(
        title: 'Drop the fluid, temporarily',
        detail:
            'High sodium, alcohol and short sleep all increase facial fluid '
            'retention, which blurs the jaw–neck border for a day or two. '
            'Water, sleep and an easy evening make a visible difference to a '
            'photo. It is cosmetic and it reverses; do not read it as progress.$fluidNote',
        evidence: prioritiseFluid
            ? EvidenceStrength.strong
            : EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Fix posture and camera angle',
        detail:
            'Forward head posture flattens the angle between jaw and neck. '
            'Stand tall, push the chin slightly forward and down, and hold the '
            'phone at eye level or a touch above. This is the single largest '
            'difference between a soft and a defined jaw in a photo, and it '
            'costs nothing.',
        evidence: EvidenceStrength.strong,
      ),
      const AdviceItem(
        title: 'Tongue posture is a habit, not a treatment',
        detail:
            'Resting the whole tongue against the palate with lips sealed '
            '("mewing") is reasonable posture and helps if you mouth-breathe. '
            'Claims that it remodels an adult mandible are not supported by '
            'good clinical evidence. Do it because it is better resting '
            'posture, not because it will move bone.',
        evidence: EvidenceStrength.emerging,
      ),
      const AdviceItem(
        title: 'Hard chewing cuts both ways',
        detail:
            'Chewing gum or tough food can grow the masseter, which widens the '
            'lower face. From the front that can look powerful, but it also '
            'spreads the two jaw-edge points this score is built from, so the '
            'number moves down. Decide which look you want before you train it.',
        evidence: EvidenceStrength.moderate,
      ),
    ];
    return advice;
  }

  List<AdviceItem> forFacialThirds(RawFaceMetrics metrics, double score) {
    final String dominant = metrics.dominantThird;
    final List<AdviceItem> advice = <AdviceItem>[
      AdviceItem(
        title: 'Level the camera first',
        detail:
            'A few degrees of chin lift or tilt moves the apparent thirds more '
            'than anything structural about your face. Your split reads '
            '${(metrics.upperThirdFraction * 100).round()} / '
            '${(metrics.middleThirdFraction * 100).round()} / '
            '${(metrics.lowerThirdFraction * 100).round()} percent '
            '(forehead / midface / lower), with the $dominant the largest. '
            'Keep the phone vertical and level with your eyes, and shoot the '
            'same way each time.',
        evidence: EvidenceStrength.measurement,
      ),
      const AdviceItem(
        title: 'Hair is the upper third’s dial',
        detail:
            'The top third is bounded by the hairline, not by bone, which makes '
            'it the easiest third to change. More volume at the crown lengthens '
            'it; a flatter, closer cut shortens it. If your lower third '
            'dominates, volume up top is the cheapest rebalance available.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Brows set the upper boundary',
        detail:
            'Brow height and shape are how most people read where the forehead '
            'ends and the midface begins. Grooming to tidy the existing line is '
            'low risk; aggressively reshaping or over-plucking moves the '
            'boundary and rarely looks better than what you started with.',
        evidence: EvidenceStrength.emerging,
      ),
      const AdviceItem(
        title: 'Facial hair and jaw framing',
        detail:
            'A short beard adds visual length to the lower third, while a clean '
            'neckline sharpens its edge without changing the proportion. If '
            'your lower third already dominates, keep the beard short at the '
            'chin rather than building volume on the jaw corners.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Structural change is a clinical decision',
        detail:
            'Orthodontics, orthognathic surgery and dermal filler can change '
            'these proportions, and each carries real cost and real risk. That '
            'conversation belongs with a qualified professional who can examine '
            'you in person. No app measurement should decide it.',
        evidence: EvidenceStrength.moderate,
      ),
      const AdviceItem(
        title: 'Why this score is strict',
        detail:
            'In the canonical MediaPipe mesh, landmark 2 sits at the top of the '
            'nose bridge (the radix), not at the base of the nose, so the '
            'middle third here runs glabella-to-radix and reads shorter than a '
            'textbook brow-to-subnasale third. The ideal is a reference, not a '
            'pass mark — compare your own scans to each other, not to 100.',
        evidence: EvidenceStrength.measurement,
      ),
    ];
    return advice;
  }

  WeaknessInsight coreWeakness(List<MetricResult> metrics) {
    if (metrics.isEmpty) {
      throw ArgumentError.value(metrics, 'metrics', 'needs one metric');
    }
    final List<MetricResult> ranked = List<MetricResult>.of(metrics)
      ..sort((MetricResult a, MetricResult b) => a.score.compareTo(b.score));
    final MetricResult weakest = ranked.first;
    final MetricResult runnerUp = ranked.length > 1 ? ranked[1] : ranked.first;

    return WeaknessInsight(
      metricId: weakest.id,
      title: weakest.title,
      score: weakest.score,
      rawValue: weakest.rawValue,
      gapToNextBest: (runnerUp.score - weakest.score).clamp(0.0, 100.0),
      why: _whyWeakest(weakest, runnerUp),
      steps: _roadmapFor(weakest),
    );
  }

  String _whyWeakest(MetricResult weakest, MetricResult runnerUp) {
    final String gap = (runnerUp.score - weakest.score) <= 0.5
        ? 'it is effectively tied with ${runnerUp.title} '
              '(${runnerUp.score.toStringAsFixed(0)}/100), so treat this as one '
              'of two equal limits rather than a single flaw'
        : 'it sits ${(runnerUp.score - weakest.score).toStringAsFixed(0)} points '
              'below your next measurement, ${runnerUp.title} '
              '(${runnerUp.score.toStringAsFixed(0)}/100), which makes it the '
              'single biggest drag on the total';
    return '${weakest.title} is your lowest score at '
        '${weakest.score.toStringAsFixed(0)}/100, and $gap. Because the overall '
        'number is a weighted mean, this is the measurement where the smallest '
        'real change moves the total the most. It is worth saying plainly: '
        'nothing in the plan below changes bone. It changes the soft tissue, the '
        'fluid, the posture and the photo, which is where the headroom actually '
        'is.';
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
        title: 'Shoot one comparison-grade photo today',
        detail:
            'Same room, same window light, phone vertical at eye level, 50-70 '
            'cm away, neutral face, hair off the forehead. This is your baseline '
            'frame, and every later step is judged against it. Today your reading '
            'is $raw.',
        evidence: EvidenceStrength.measurement,
      ),
      ...habits,
      const RoadmapStep(
        stage: RoadmapStage.week5plus,
        title: 'Re-scan and compare, same light',
        detail:
            'Open Compare My Progress and put this scan against the new one. '
            'Read the three measurements, not the overall number: an overall '
            'point or two of movement inside a single metric is indistinguishable '
            'from capture noise. Three scans a week apart is a trend; one scan is '
            'a snapshot.',
        evidence: EvidenceStrength.measurement,
      ),
    ];
  }

  static const List<RoadmapStep> _symmetryHabits = <RoadmapStep>[
    RoadmapStep(
      stage: RoadmapStage.weeks1to2,
      title: 'Sleep on your back, or rotate sides nightly',
      detail:
          'Sustained pressure from the same pillow side is the most commonly '
          'cited environmental contributor to soft-tissue asymmetry. The evidence '
          'is observational, so this is a free habit rather than a guaranteed '
          'fix - but rotating sides costs nothing and removes one variable.',
      evidence: EvidenceStrength.moderate,
    ),
    RoadmapStep(
      stage: RoadmapStage.weeks3to4,
      title: 'Chew on the non-dominant side first',
      detail:
          'Habitual one-sided chewing loads one masseter and one '
          'temporomandibular joint harder, and dental research links it to '
          'measurable lower-face asymmetry. Start every meal on the weaker side '
          'for two weeks; that is the entire intervention.',
      evidence: EvidenceStrength.moderate,
    ),
  ];

  static List<RoadmapStep> _jawlineHabits = <RoadmapStep>[
    RoadmapStep(
      stage: RoadmapStage.weeks1to2,
      title: 'Hold a small deficit with enough protein',
      detail:
          'A jawline is mostly the fat layer over the mandible, and that layer '
          'is not spot-reducible. A modest calorie deficit with adequate protein '
          'and resistance training lowers fat everywhere; the face shows it early '
          'because the layer there is thin. Aim for slow - about 0.5 percent of '
          'bodyweight a week - so the face does not read as gaunt instead.',
      evidence: EvidenceStrength.strong,
    ),
    RoadmapStep(
      stage: RoadmapStage.weeks3to4,
      title: 'Sleep 7-9 hours and keep sodium steady',
      detail:
          'Short sleep, alcohol and a salty evening all increase facial fluid '
          'retention, which blurs the jaw-neck border for a day or two. This is '
          'cosmetic and it reverses, so read it as photo hygiene rather than '
          'progress: it is the difference between a soft and a clean border in a '
          'picture taken tomorrow morning.',
      evidence: EvidenceStrength.moderate,
    ),
  ];

  static const List<RoadmapStep> _thirdsHabits = <RoadmapStep>[
    RoadmapStep(
      stage: RoadmapStage.weeks1to2,
      title: 'Rebalance with hair volume, not surgery',
      detail:
          'The upper third is bounded by the hairline, not by bone, which makes '
          'it the one third you can move this month. Volume at the crown '
          'lengthens it; a flatter, closer cut shortens it. Photograph the same '
          'cut for two weeks before judging it.',
      evidence: EvidenceStrength.moderate,
    ),
    RoadmapStep(
      stage: RoadmapStage.weeks3to4,
      title: 'Set the hairline and jaw framing deliberately',
      detail:
          'Tidy the existing brow line rather than reshaping it, and keep a beard '
          'short at the chin with a clean neckline: that sharpens the lower '
          'third edge without adding width at the jaw corners. Both are '
          'reversible, which is the point.',
      evidence: EvidenceStrength.moderate,
    ),
  ];
}
