/// A minimal on-device user profile used to personalise body-composition
/// advice. Nothing here reaches the network; it lives in `ScanHistory` and is
/// optional, so the app still works when the user skips it.
class UserProfile {
  const UserProfile({
    this.gender = Gender.other,
    this.age = 0,
    this.heightCm,
    this.weightKg,
    this.heightKnown = true,
    this.weightKnown = true,
  });

  final Gender gender;
  final int age;
  final double? heightCm;
  final double? weightKg;
  final bool heightKnown;
  final bool weightKnown;

  /// Local BMI when both height and weight are provided and usable,
  /// otherwise 0 (meaning unknown / skipped).
  double get bmi => computeBmi();

  /// Returns the BMI when height and weight are present and positive, otherwise 0.
  double computeBmi() {
    if (!heightKnown || !weightKnown || heightCm == null || weightKg == null) {
      return 0.0;
    }
    return bmiFromMetrics(heightCm!, weightKg!);
  }

  /// Category string and band for advice personalisation.
  (String label, BmiCategory category) get bmiCategory {
    final double bmi = computeBmi();
    if (bmi <= 0) {
      return ('Unknown', BmiCategory.unknown);
    }
    if (bmi < 18.5) {
      return ('Underweight', BmiCategory.underweight);
    }
    if (bmi < 25) {
      return ('Normal', BmiCategory.normal);
    }
    if (bmi < 30) {
      return ('Overweight', BmiCategory.overweight);
    }
    return ('Obese', BmiCategory.obese);
  }

  @override
  String toString() {
    return 'UserProfile(gender: $gender, age: $age, height: ${heightCm ?? -1}, weight: ${weightKg ?? -1}, bmi: ${bmi.toStringAsFixed(1)})';
  }
}

enum Gender { male, female, other }

enum BmiCategory { underweight, normal, overweight, obese, unknown }

/// Body-mass index rounded to one decimal.
double bmiFromMetrics(double heightCm, double weightKg) {
  if (heightCm <= 0 || weightKg <= 0) {
    return 0.0;
  }
  final double heightM = heightCm / 100.0;
  if (heightM <= 0) {
    return 0.0;
  }
  return weightKg / (heightM * heightM);
}
