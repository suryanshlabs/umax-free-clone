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
