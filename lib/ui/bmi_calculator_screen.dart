import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bmi.dart';
import 'theme.dart';

/// A standalone BMI calculator.
///
/// Kept deliberately away from the scan flow: nothing here is saved, nothing is
/// shared with a facial report, and nothing typed here can change a face score.
/// The result is drawn from [BmiCalculator] so the rules (unit conversion,
/// validation, the under-18 rule) are the same ones the tests cover.
class BmiCalculatorScreen extends StatefulWidget {
  const BmiCalculatorScreen({super.key});

  @override
  State<BmiCalculatorScreen> createState() => _BmiCalculatorScreenState();
}

class _BmiCalculatorScreenState extends State<BmiCalculatorScreen> {
  final TextEditingController _heightCm = TextEditingController();
  final TextEditingController _weightKg = TextEditingController();
  final TextEditingController _feet = TextEditingController();
  final TextEditingController _inches = TextEditingController();
  final TextEditingController _pounds = TextEditingController();
  final TextEditingController _age = TextEditingController();

  BmiUnitSystem _units = BmiUnitSystem.metric;
  BmiEvaluation? _result;

  @override
  void dispose() {
    _heightCm.dispose();
    _weightKg.dispose();
    _feet.dispose();
    _inches.dispose();
    _pounds.dispose();
    _age.dispose();
    super.dispose();
  }

  void _reset() {
    FocusScope.of(context).unfocus();
    _heightCm.clear();
    _weightKg.clear();
    _feet.clear();
    _inches.clear();
    _pounds.clear();
    _age.clear();
    setState(() => _result = null);
  }

  void _calculate() {
    FocusScope.of(context).unfocus();
    final int? age = int.tryParse(_age.text.trim());

    double? heightCm;
    double? weightKg;
    String? unitError;

    if (_units == BmiUnitSystem.metric) {
      heightCm = _parseNumber(_heightCm.text);
      weightKg = _parseNumber(_weightKg.text);
    } else {
      final int? feet = int.tryParse(_feet.text.trim());
      final String inchesText = _inches.text.trim();
      final double? inches = inchesText.isEmpty ? 0 : _parseNumber(inchesText);
      final double? pounds = _parseNumber(_pounds.text);
      if (feet == null || inches == null) {
        unitError = 'Enter your height in feet and inches.';
      } else {
        heightCm = BmiCalculator.cmFromFeetInches(feet: feet, inches: inches);
        if (heightCm == null) {
          unitError = 'Inches must be between 0 and 11.';
        }
      }
      weightKg = pounds == null ? null : BmiCalculator.kgFromPounds(pounds);
      if (unitError == null && weightKg == null) {
        unitError = 'Enter your weight in pounds.';
      }
    }

    final BmiEvaluation evaluation = unitError != null
        ? BmiEvaluation.invalid(unitError)
        : BmiCalculator.evaluate(
            heightCm: heightCm,
            weightKg: weightKg,
            ageYears: age,
          );
    setState(() => _result = evaluation);
  }

  double? _parseNumber(String raw) {
    final String cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) {
      return null;
    }
    return double.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final BmiEvaluation? result = _result;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('BMI Calculator'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: <Widget>[
            const Text(
              'A separate tool. Nothing here is used in face analysis, and '
              'nothing is saved.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 18),
            SegmentedButton<BmiUnitSystem>(
              segments: <ButtonSegment<BmiUnitSystem>>[
                for (final BmiUnitSystem system in BmiUnitSystem.values)
                  ButtonSegment<BmiUnitSystem>(
                    value: system,
                    label: Text(
                      system == BmiUnitSystem.metric ? 'Metric' : 'Imperial',
                    ),
                  ),
              ],
              selected: <BmiUnitSystem>{_units},
              onSelectionChanged: (Set<BmiUnitSystem> selection) {
                setState(() {
                  _units = selection.first;
                  _result = null;
                });
              },
            ),
            const SizedBox(height: 6),
            Text(
              _units == BmiUnitSystem.metric
                  ? 'Centimetres and kilograms'
                  : 'Feet, inches and pounds',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 18),
            if (_units == BmiUnitSystem.metric) ...<Widget>[
              _BmiField(
                controller: _heightCm,
                label: 'HEIGHT (CM)',
                hint: 'e.g. 170',
              ),
              const SizedBox(height: 12),
              _BmiField(
                controller: _weightKg,
                label: 'WEIGHT (KG)',
                hint: 'e.g. 70',
              ),
            ] else ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _BmiField(
                      controller: _feet,
                      label: 'HEIGHT (FT)',
                      hint: 'e.g. 5',
                      allowDecimal: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BmiField(
                      controller: _inches,
                      label: 'HEIGHT (IN)',
                      hint: 'e.g. 7',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _BmiField(
                controller: _pounds,
                label: 'WEIGHT (LB)',
                hint: 'e.g. 154',
              ),
            ],
            const SizedBox(height: 12),
            _BmiField(
              controller: _age,
              label: 'AGE (YEARS)',
              hint: 'e.g. 28',
              allowDecimal: false,
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: _calculate,
                    child: const Text('Calculate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
            if (result != null) ...<Widget>[
              const SizedBox(height: 20),
              if (result.isValid)
                _BmiResultCard(value: result.valueText, band: result.band)
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.error ?? 'Check the values and try again.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 22),
            const _BmiInfoCard(
              title: 'WHAT BMI IS, AND IS NOT',
              body: BmiCalculator.limitations,
            ),
            const SizedBox(height: 12),
            const _BmiInfoCard(
              title: 'ADULT BANDS',
              body: BmiCalculator.adultReference,
            ),
            const SizedBox(height: 12),
            const _BmiInfoCard(
              title: 'UNDER 18',
              body:
                  'BMI for children and teenagers depends on age and sex. This '
                  'calculator shows the raw number and does not place a minor '
                  'in an adult category; an age-specific growth reference is '
                  'needed for that.',
            ),
            const SizedBox(height: 12),
            const _BmiInfoCard(
              title: 'YOUR PRIVACY',
              body: BmiCalculator.privacyNote,
            ),
          ],
        ),
      ),
    );
  }
}

class _BmiField extends StatelessWidget {
  const _BmiField({
    required this.controller,
    required this.label,
    required this.hint,
    this.allowDecimal = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          allowDecimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
        ),
      ],
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.textTertiary,
        ),
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
      ),
    );
  }
}

class _BmiResultCard extends StatelessWidget {
  const _BmiResultCard({required this.value, required this.band});

  final String value;
  final BmiBand band;

  Color get _color => switch (band) {
    BmiBand.underweight => AppColors.amber,
    BmiBand.healthy => AppColors.mint,
    BmiBand.above => AppColors.accentSoft,
    BmiBand.wellAbove => AppColors.danger,
    BmiBand.needsAgeSpecificReference => AppColors.accent,
    BmiBand.unknown => AppColors.textTertiary,
  };

  @override
  Widget build(BuildContext context) {
    final bool isMinor = band == BmiBand.needsAgeSpecificReference;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'YOUR BMI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                value,
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  color: _color,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'kg/m²',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isMinor
                ? 'RAW VALUE — AGE-SPECIFIC INTERPRETATION NEEDED'
                : band.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            BmiCalculator.interpretationFor(band),
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BmiInfoCard extends StatelessWidget {
  const _BmiInfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
