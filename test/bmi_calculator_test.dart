import 'package:facial_analysis/core/bmi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('metric calculation', () {
    test('uses weight_kg / (height_m * height_m)', () {
      expect(
        BmiCalculator.valueFor(heightCm: 170, weightKg: 70)!,
        closeTo(24.221, 0.001),
      );
      expect(
        BmiCalculator.valueFor(heightCm: 180, weightKg: 90),
        closeTo(27.78, 0.01),
      );
      expect(
        BmiCalculator.valueFor(heightCm: 200, weightKg: 50),
        closeTo(12.5, 0.001),
      );
    });

    test('a person at 1.70 m and 53 kg reads under 18.5', () {
      final BmiEvaluation result = BmiCalculator.evaluate(
        heightCm: 170,
        weightKg: 53,
        ageYears: 30,
      );
      expect(result.isValid, isTrue);
      expect(result.value, closeTo(18.34, 0.01));
      expect(result.band, BmiBand.underweight);
    });
  });

  group('imperial conversion', () {
    test('feet and inches convert to centimetres', () {
      expect(
        BmiCalculator.cmFromFeetInches(feet: 5, inches: 7),
        closeTo(170.18, 0.01),
      );
      expect(
        BmiCalculator.cmFromFeetInches(feet: 6, inches: 0),
        closeTo(182.88, 0.01),
      );
    });

    test('pounds convert to kilograms', () {
      expect(BmiCalculator.kgFromPounds(154), closeTo(69.853, 0.001));
    });

    test('an imperial reading matches the metric equivalent', () {
      final double heightCm = BmiCalculator.cmFromFeetInches(
        feet: 5,
        inches: 7,
      )!;
      final double weightKg = BmiCalculator.kgFromPounds(154)!;
      final double imperialBmi = BmiCalculator.valueFor(
        heightCm: heightCm,
        weightKg: weightKg,
      )!;
      // 170 cm / 69.85 kg is the same body in metric units.
      final double metricBmi = BmiCalculator.valueFor(
        heightCm: 170.18,
        weightKg: 69.85,
      )!;
      expect(imperialBmi, closeTo(metricBmi, 0.05));
      expect(imperialBmi, closeTo(24.12, 0.05));
    });

    test('twelve inches is rejected rather than rolled into a foot', () {
      expect(BmiCalculator.cmFromFeetInches(feet: 5, inches: 12), isNull);
      expect(BmiCalculator.cmFromFeetInches(feet: -1, inches: 2), isNull);
      expect(BmiCalculator.cmFromFeetInches(feet: 5, inches: -2), isNull);
    });

    test('zero or negative pounds gives no number', () {
      expect(BmiCalculator.kgFromPounds(0), isNull);
      expect(BmiCalculator.kgFromPounds(-150), isNull);
    });
  });

  group('invalid input', () {
    test('blank height, weight or age is reported, not guessed', () {
      expect(BmiCalculator.validateHeightCm(null), 'Enter your height.');
      expect(BmiCalculator.validateWeightKg(null), 'Enter your weight.');
      expect(BmiCalculator.validateAge(null), 'Enter your age.');
    });

    test('zero and negative values are rejected', () {
      expect(BmiCalculator.validateHeightCm(0), isNotNull);
      expect(BmiCalculator.validateHeightCm(-170), isNotNull);
      expect(BmiCalculator.validateWeightKg(0), isNotNull);
      expect(BmiCalculator.validateWeightKg(-70), isNotNull);
      expect(BmiCalculator.valueFor(heightCm: 0, weightKg: 70), isNull);
      expect(BmiCalculator.valueFor(heightCm: 170, weightKg: 0), isNull);
      expect(BmiCalculator.valueFor(heightCm: -170, weightKg: 70), isNull);
      expect(BmiCalculator.valueFor(heightCm: 170, weightKg: -70), isNull);
    });

    test(
      'the evaluate entry point returns the first error, never a number',
      () {
        final BmiEvaluation result = BmiCalculator.evaluate(
          heightCm: 170,
          weightKg: 70,
          ageYears: 0,
        );
        expect(result.isValid, isFalse);
        expect(result.value, isNull);
        expect(result.error, isNotNull);
      },
    );

    test('physiologically impossible heights are out of range', () {
      expect(BmiCalculator.validateHeightCm(20), isNotNull);
      expect(BmiCalculator.validateHeightCm(300), isNotNull);
      expect(BmiCalculator.validateWeightKg(500), isNotNull);
      expect(BmiCalculator.validateAge(200), isNotNull);
      expect(BmiCalculator.validateAge(1), isNotNull);
    });

    test('not-a-number input never becomes a BMI', () {
      expect(
        BmiCalculator.valueFor(heightCm: double.nan, weightKg: 70),
        isNull,
      );
      expect(
        BmiCalculator.valueFor(heightCm: 170, weightKg: double.infinity),
        isNull,
      );
    });
  });

  group('adult bands', () {
    test('cut-offs are applied exactly at the boundaries', () {
      expect(
        BmiCalculator.bandFor(value: 18.49, ageYears: 30),
        BmiBand.underweight,
      );
      expect(BmiCalculator.bandFor(value: 18.5, ageYears: 30), BmiBand.healthy);
      expect(BmiCalculator.bandFor(value: 24.9, ageYears: 30), BmiBand.healthy);
      expect(BmiCalculator.bandFor(value: 25, ageYears: 30), BmiBand.above);
      expect(BmiCalculator.bandFor(value: 29.9, ageYears: 30), BmiBand.above);
      expect(BmiCalculator.bandFor(value: 30, ageYears: 30), BmiBand.wellAbove);
      expect(
        BmiCalculator.bandFor(value: 18, ageYears: 18),
        BmiBand.underweight,
      );
    });
  });

  group('under-18 safeguard', () {
    test('minors are never placed in an adult category', () {
      for (final double value in <double>[12, 17.9, 21, 27, 34]) {
        expect(
          BmiCalculator.bandFor(value: value, ageYears: 16),
          BmiBand.needsAgeSpecificReference,
          reason: 'BMI $value at 16 must not get an adult band',
        );
        expect(
          BmiCalculator.bandFor(value: value, ageYears: 17),
          BmiBand.needsAgeSpecificReference,
        );
      }
    });

    test('the evaluation keeps the number but refuses a category', () {
      final BmiEvaluation result = BmiCalculator.evaluate(
        heightCm: 160,
        weightKg: 55,
        ageYears: 15,
      );
      expect(result.isValid, isTrue);
      expect(result.value, closeTo(21.48, 0.01));
      expect(result.band, BmiBand.needsAgeSpecificReference);
      final String text = BmiCalculator.interpretationFor(result.band);
      expect(text.toLowerCase(), contains('age- and sex-specific'));
      expect(text.toLowerCase(), contains('does not assign a category'));
      expect(text.toLowerCase(), isNot(contains('normal weight')));
      expect(text.toLowerCase(), isNot(contains('overweight')));
    });

    test('the 18th birthday switches to the adult reference', () {
      expect(
        BmiCalculator.bandFor(value: 22, ageYears: 17),
        BmiBand.needsAgeSpecificReference,
      );
      expect(BmiCalculator.bandFor(value: 22, ageYears: 18), BmiBand.healthy);
    });
  });

  group('communication', () {
    test(
      'the limitations text carries no target weight or weight-loss plan',
      () {
        final String text = BmiCalculator.limitations.toLowerCase();
        expect(text, contains('not a diagnosis'));
        expect(text, contains('does not give targets'));
        expect(text, isNot(contains('lose')));
        expect(text, isNot(contains('calorie deficit')));
      },
    );

    test('uses the exact formula wording', () {
      expect(
        BmiCalculator.valueFor(heightCm: 175, weightKg: 70),
        closeTo(70 / (1.75 * 1.75), 1e-9),
      );
    });
  });
}
