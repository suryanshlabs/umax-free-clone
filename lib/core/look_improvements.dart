import 'report.dart';

/// One practical lever that changes how a face reads, with the area it acts on
/// and the strength of the evidence behind it.
///
/// Rules this file keeps, so that it stays useful without becoming a promise:
///
/// * Nothing here claims to change bone, and nothing claims a measurement will
///   improve by a stated number of points.
/// * No weight-loss, diet, supplement or "fat loss reveals the jaw" advice, and
///   no target weights. BMI stays in its own tool and never feeds back here.
/// * Surgery, filler, orthodontics and similar are named only as clinical
///   decisions for a professional, never as recommendations.
/// * Every item names its evidence level, because hair, light, grooming and
///   camera position genuinely move these readings more than anything else.
class LookImprovement {
  const LookImprovement({
    required this.area,
    required this.title,
    required this.detail,
    required this.evidence,
  });

  /// The part of the face this acts on, e.g. "Overall" or "Chin & lower face".
  final String area;

  final String title;
  final String detail;
  final EvidenceStrength evidence;
}

/// The "what can move this" plan: levers that apply to the whole face, plus a
/// short set aimed at the measurement with the lowest agreement.
class LookImprovementPlan {
  const LookImprovementPlan({
    required this.headline,
    required this.overall,
    required this.targetedArea,
    required this.targeted,
  });

  /// One sentence naming what this plan is and is not.
  final String headline;

  /// Levers that change the whole face at once.
  final List<LookImprovement> overall;

  /// The area the targeted list addresses.
  final String targetedArea;

  /// Levers aimed at [targetedArea].
  final List<LookImprovement> targeted;

  /// Build the plan from the measurements already on the report. Pure: no
  /// storage, no migration, and it can be recomputed for an old scan.
  factory LookImprovementPlan.forMetrics(List<MetricResult> metrics) {
    MetricResult? lowest;
    for (final MetricResult metric in metrics) {
      if (lowest == null || metric.score < lowest.score) {
        lowest = metric;
      }
    }
    final MetricId id = lowest?.id ?? MetricId.eyeSymmetry;
    return LookImprovementPlan(
      headline:
          'These change how a face reads in a photo and in person. None of them '
          'change bone, and none of them is required - take what is useful and '
          'ignore the rest.',
      overall: _overall,
      targetedArea: _areaFor(id),
      targeted: _targetedFor(id),
    );
  }

  static String _areaFor(MetricId id) => switch (id) {
    MetricId.eyeSymmetry => 'Eyes & brows',
    MetricId.jawline => 'Chin & lower face',
    MetricId.facialThirds => 'Hair, hairline & beard',
  };

  static const List<LookImprovement> _overall = <LookImprovement>[
    LookImprovement(
      area: 'Overall',
      title: 'Light is the single biggest change',
      detail:
          'Soft, even, front-facing light removes the shadows under the eyes, '
          'beside the nose and along the jaw that make a face read tired or '
          'heavy. A window in daytime, or a lamp at eye level rather than '
          'overhead, does more than any product. Harsh overhead light and a '
          'phone flash pointed straight on are the two worst cases.',
      evidence: EvidenceStrength.strong,
    ),
    LookImprovement(
      area: 'Overall',
      title: 'Grooming and haircut shape the silhouette',
      detail:
          'A haircut, a tidy beard line or clean eyebrows change the outline '
          'other people actually see, and they are reversible. Shape matters '
          'more than length: volume on top balances a longer face, width at the '
          'sides balances a rounder one. A barber who will look at your face '
          'straight on is a better guide than a photo of someone else.',
      evidence: EvidenceStrength.strong,
    ),
    LookImprovement(
      area: 'Overall',
      title: 'Sleep, water and skin, in that order',
      detail:
          'Puffiness under the eyes and dull skin are the two things a camera '
          'picks up first, and both respond to sleep and hydration within days. '
          'A plain moisturiser and sunscreen are the products with the most '
          'evidence behind them; everything else is optional. Skin quality '
          'changes how a face reads far more than a few percent of measured '
          'asymmetry.',
      evidence: EvidenceStrength.moderate,
    ),
    LookImprovement(
      area: 'Overall',
      title: 'Posture and where your head sits',
      detail:
          'A forward head and rounded shoulders shorten the neck and soften the '
          'jaw line in every photo and in person. Standing tall with the chin '
          'level, and holding the phone at eye level instead of looking down at '
          'it, is free and shows up in a week.',
      evidence: EvidenceStrength.moderate,
    ),
    LookImprovement(
      area: 'Overall',
      title: 'Expression and a relaxed jaw',
      detail:
          'A clenched jaw widens the lower face and a tight mouth flattens the '
          'lips. Resting with the teeth gently apart, lips closed and the '
          'tongue against the roof of the mouth is a comfort habit, not a '
          'treatment: it will not reshape bone, and anyone promising that is '
          'overstating it.',
      evidence: EvidenceStrength.emerging,
    ),
  ];

  static const List<LookImprovement> _symmetry = <LookImprovement>[
    LookImprovement(
      area: 'Eyes & brows',
      title: 'Brows do the most work here',
      detail:
          'Eyebrows frame the eyes and are read as symmetric even when they are '
          'not. Trimming stray hairs and keeping both brows the same shape and '
          'height - with a mirror straight on, not from an angle - is the '
          'cheapest change with a visible effect. Over-plucking reads worse than '
          'a little natural difference.',
      evidence: EvidenceStrength.strong,
    ),
    LookImprovement(
      area: 'Eyes & brows',
      title: 'Under-eye shadows are mostly light and sleep',
      detail:
          'Cool, thin under-eye skin shows the light through it, so shadows here '
          'are usually a lighting and fatigue signal rather than a shape '
          'problem. Sleep, water, and a light that comes from in front of you '
          'rather than above you do most of it. A concealer one shade lighter '
          'than the skin is the cosmetic option, and it is fine to skip it.',
      evidence: EvidenceStrength.moderate,
    ),
    LookImprovement(
      area: 'Eyes & brows',
      title: 'Glasses and hair parting',
      detail:
          'Frames that sit level and match the width of your face hide small '
          'differences between the two sides instead of advertising them. A '
          'centre parting emphasises symmetry, a side parting breaks it up. Both '
          'are styling choices, not corrections.',
      evidence: EvidenceStrength.moderate,
    ),
  ];

  static const List<LookImprovement> _jaw = <LookImprovement>[
    LookImprovement(
      area: 'Chin & lower face',
      title: 'A beard line is the most direct lever',
      detail:
          'Stubble or a trimmed beard along the jaw adds a visible edge to the '
          'lower face and can square a soft chin or soften a sharp one. Keep the '
          'neckline tidy and follow the jaw rather than the chin, and the effect '
          'is immediate. It is also completely reversible, which is why it beats '
          'every other option on this list.',
      evidence: EvidenceStrength.strong,
    ),
    LookImprovement(
      area: 'Chin & lower face',
      title: 'Camera distance changes this angle a lot',
      detail:
          'A phone held close widens the lower face and flattens the chin angle; '
          'the same face at arm\'s length reads narrower. If a measurement here '
          'bothers you, re-shoot at a constant distance first - it is often the '
          'lens, not the jaw.',
      evidence: EvidenceStrength.measurement,
    ),
    LookImprovement(
      area: 'Chin & lower face',
      title: 'Teeth and bite are a dentist question',
      detail:
          'How the teeth meet changes the lower face, and orthodontics can '
          'change it further. That is a decision for a dentist who can examine '
          'you, with real cost and months of treatment attached. It is not '
          'something to start because of a selfie measurement, and this app does '
          'not recommend it.',
      evidence: EvidenceStrength.moderate,
    ),
  ];

  static const List<LookImprovement> _thirds = <LookImprovement>[
    LookImprovement(
      area: 'Hair, hairline & beard',
      title: 'Hair volume moves the upper third',
      detail:
          'Height on top lengthens the upper section of the face; a fringe '
          'shortens the forehead and pulls the thirds closer to even. This is '
          'the one part of the proportion reading you can change today, with no '
          'risk at all.',
      evidence: EvidenceStrength.strong,
    ),
    LookImprovement(
      area: 'Hair, hairline & beard',
      title: 'Beard length moves the lower third',
      detail:
          'A short beard adds length under the chin; a clean shave keeps the '
          'lower third at its shortest. Pick one and keep it, because the '
          'measurement compares today with yesterday, not with anyone else.',
      evidence: EvidenceStrength.moderate,
    ),
    LookImprovement(
      area: 'Hair, hairline & beard',
      title: 'The hairline reading is an estimate',
      detail:
          'The top of the upper third comes from a landmark near the hairline, so '
          'a fringe, a receding hairline or a bright forehead highlight can move '
          'this number without your face changing. Treat a large shift here as a '
          'photograph before treating it as a face.',
      evidence: EvidenceStrength.measurement,
    ),
  ];

  static List<LookImprovement> _targetedFor(MetricId id) => switch (id) {
    MetricId.eyeSymmetry => _symmetry,
    MetricId.jawline => _jaw,
    MetricId.facialThirds => _thirds,
  };
}
