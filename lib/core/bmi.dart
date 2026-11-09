/// Body-mass index, kept completely separate from facial analysis.
///
/// Nothing in the geometry, scoring or scan-history code imports this file: a
/// BMI value never changes a facial measurement, and a facial scan never stores
/// a height, weight, age or BMI.
///
/// Everything here is pure Dart with no I/O, so the calculator can be tested
/// without a device and cannot accidentally persist anything.
library;

/// Which units the person is typing in.
enum BmiUnitSystem {
  metric('cm / kg'),
  imperial('ft, in / lb');

  const BmiUnitSystem(this.unitLabel);

  final String unitLabel;
}

/// Adult reference bands, plus the under-18 state where no band is applied.
///
/// The four adult bands are the widely used World Health Organization adult
/// cut-offs (18.5 / 25 / 30). They are screening bands for adults, not a
/// diagnosis and not a measurement of body fat.
enum BmiBand {
  underweight('Below the adult reference range'),
  healthy('Inside the adult reference range'),
  above('Above the adult reference range'),
  wellAbove('Well above the adult reference range'),
  needsAgeSpecificReference('Not classified'),
  unknown('Not calculated');

  const BmiBand(this.label);

  final String label;
}

/// The outcome of one calculation: either a number plus its band, or the first
/// problem with the input.
class BmiEvaluation {
  const BmiEvaluation._({this.value, this.band = BmiBand.unknown, this.error});

  const BmiEvaluation.valid(double value, BmiBand band)
    : this._(value: value, band: band);

  const BmiEvaluation.invalid(String error) : this._(error: error);

  final double? value;
  final BmiBand band;

  /// A sentence safe to show next to the input that caused it, or null.
  final String? error;

  bool get isValid => value != null;

  /// One decimal, the conventional way a BMI number is quoted.
  String get valueText => value == null ? '—' : value!.toStringAsFixed(1);
}

/// BMI arithmetic, unit conversion and input validation.
///
/// The formula is `weight_kg / (height_m * height_m)`. Inputs are checked
/// against generous physiological ranges so a misplaced decimal point is
/// rejected instead of producing a confident-looking number.
class BmiCalculator {
  const BmiCalculator._();

  static const double minHeightCm = 60;
  static const double maxHeightCm = 260;
  static const double minWeightKg = 10;
  static const double maxWeightKg = 400;
  static const int minAgeYears = 2;
  static const int maxAgeYears = 120;

  /// Below this age, adult bands are not applied.
  static const int adultAgeYears = 18;

  static const double cmPerInch = 2.54;
  static const double inchesPerFoot = 12;
  static const double kgPerPound = 0.45359237;

  /// Centimetres from feet and inches. Null when the combination is not a real
  /// height format (negative feet, or 12+ inches).
  static double? cmFromFeetInches({required int feet, required double inches}) {
    if (feet < 0 || inches < 0 || inches >= inchesPerFoot) {
      return null;
    }
    return (feet * inchesPerFoot + inches) * cmPerInch;
  }

  /// Kilograms from pounds.
  static double? kgFromPounds(double pounds) {
    if (!pounds.isFinite || pounds <= 0) {
      return null;
    }
    return pounds * kgPerPound;
  }

  /// The BMI itself, or null when the inputs cannot produce one.
  static double? valueFor({
    required double heightCm,
    required double weightKg,
  }) {
    if (!heightCm.isFinite || !weightKg.isFinite) {
      return null;
    }
    if (heightCm <= 0 || weightKg <= 0) {
      return null;
    }
    final double heightM = heightCm / 100.0;
    if (heightM <= 0) {
      return null;
    }
    return weightKg / (heightM * heightM);
  }

  /// Validation for the height field. The message names the accepted range so
  /// the person can correct the value rather than guess.
  static String? validateHeightCm(double? heightCm) {
    if (heightCm == null) {
      return 'Enter your height.';
    }
    if (!heightCm.isFinite || heightCm <= 0) {
      return 'Height must be a positive number.';
    }
    if (heightCm < minHeightCm || heightCm > maxHeightCm) {
      return 'Enter a height between ${minHeightCm.toInt()} and '
          '${maxHeightCm.toInt()} cm.';
    }
    return null;
  }

  static String? validateWeightKg(double? weightKg) {
    if (weightKg == null) {
      return 'Enter your weight.';
    }
    if (!weightKg.isFinite || weightKg <= 0) {
      return 'Weight must be a positive number.';
    }
    if (weightKg < minWeightKg || weightKg > maxWeightKg) {
      return 'Enter a weight between ${minWeightKg.toInt()} and '
          '${maxWeightKg.toInt()} kg.';
    }
    return null;
  }

  static String? validateAge(int? ageYears) {
    if (ageYears == null) {
      return 'Enter your age.';
    }
    if (ageYears < minAgeYears || ageYears > maxAgeYears) {
      return 'Enter an age between $minAgeYears and $maxAgeYears.';
    }
    return null;
  }

  /// The band for a value at a given age. Anyone under 18 is deliberately left
  /// unclassified: adult cut-offs do not apply to growing bodies.
  static BmiBand bandFor({required double value, required int ageYears}) {
    if (!value.isFinite || value <= 0) {
      return BmiBand.unknown;
    }
    if (ageYears < adultAgeYears) {
      return BmiBand.needsAgeSpecificReference;
    }
    if (value < 18.5) {
      return BmiBand.underweight;
    }
    if (value < 25) {
      return BmiBand.healthy;
    }
    if (value < 30) {
      return BmiBand.above;
    }
    return BmiBand.wellAbove;
  }

  /// Runs validation, the formula and the age rule in one place, so the screen
  /// cannot show a number the rules would not stand behind.
  static BmiEvaluation evaluate({
    required double? heightCm,
    required double? weightKg,
    required int? ageYears,
  }) {
    final String? ageError = validateAge(ageYears);
    if (ageError != null) {
      return BmiEvaluation.invalid(ageError);
    }
    final String? heightError = validateHeightCm(heightCm);
    if (heightError != null) {
      return BmiEvaluation.invalid(heightError);
    }
    final String? weightError = validateWeightKg(weightKg);
    if (weightError != null) {
      return BmiEvaluation.invalid(weightError);
    }
    final double? value = valueFor(heightCm: heightCm!, weightKg: weightKg!);
    if (value == null) {
      return const BmiEvaluation.invalid(
        'Those values cannot produce a BMI. Check the height and weight.',
      );
    }
    return BmiEvaluation.valid(
      value,
      bandFor(value: value, ageYears: ageYears!),
    );
  }

  /// A sentence for the result card. Under 18, it explains the missing band
  /// instead of inventing one.
  static String interpretationFor(BmiBand band) {
    return switch (band) {
      BmiBand.underweight =>
        'Below the adult reference range (under 18.5). BMI is a screening '
            'number for weight relative to height; it does not tell you what '
            'the number is made of, and it is not a diagnosis.',
      BmiBand.healthy =>
        'Inside the adult reference range (18.5 to under 25). A screening '
            'result, not a statement about body fat, fitness or health.',
      BmiBand.above =>
        'Above the adult reference range (25 to under 30). BMI does not '
            'distinguish muscle from fat, so an active person can land here.',
      BmiBand.wellAbove =>
        'Well above the adult reference range (30 and over). This is a '
            'screening band; only a clinician can interpret what it means for '
            'you.',
      BmiBand.needsAgeSpecificReference =>
        'This is the raw BMI number only. For anyone under 18, BMI has to be '
            'read against age- and sex-specific growth references (for example '
            'the WHO 5-19 BMI-for-age charts). Adult bands are not valid here, '
            'so this app does not assign a category.',
      BmiBand.unknown => 'No result yet.',
    };
  }

  /// Shown under every result, including the adult ones.
  static const String limitations =
      'What BMI is: a single ratio of weight to height, used as a screening '
      'tool at population level. What it is not: a measure of body fat, muscle, '
      'fitness or health, and not a diagnosis. It does not account for frame '
      'size, muscle mass, pregnancy, disability or age-related change, and it '
      'says nothing about where weight is carried. This calculator gives you a '
      'number and its adult screening band; it does not give targets, calorie '
      'plans or weight-loss advice. Talk to a qualified clinician about what a '
      'result means for you.';

  /// The adult cut-offs, named, so the bands are auditable rather than implied.
  static const String adultReference =
      'Adult bands (WHO cut-offs): under 18.5 below range; 18.5 to under 25 '
      'inside range; 25 to under 30 above range; 30 and over well above range.';

  /// Nothing typed here is stored; the screen says so too.
  static const String privacyNote =
      'Your height, weight and age stay in this screen. They are never saved '
      'and never used in facial analysis.';
}
