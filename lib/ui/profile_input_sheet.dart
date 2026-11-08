import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/user_profile.dart';
import '../data/scan_history.dart';
import 'theme.dart';

/// Bottom sheet asking for optional basic info before Face Analyze.
/// Returns the saved [UserProfile], or null when skipped/dismissed.
Future<UserProfile?> showProfileInputSheet(BuildContext context) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const ProfileInputSheet(),
  );
}

class ProfileInputSheet extends StatefulWidget {
  const ProfileInputSheet({super.key});

  @override
  State<ProfileInputSheet> createState() => _ProfileInputSheetState();
}

class _ProfileInputSheetState extends State<ProfileInputSheet> {
  Gender _gender = Gender.other;
  int _age = 28;
  double _heightCm = 170;
  double _weightKg = 70;
  bool _heightKnown = true;
  bool _weightKnown = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Basic info (optional)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Used only to personalise body-composition advice. Nothing leaves this device.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 18),
              const Text('GENDER',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textTertiary)),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                for (final Gender g in Gender.values) ...<Widget>[
                  Expanded(child: _GenderChip(
                    label: g.name[0].toUpperCase() + g.name.substring(1),
                    selected: _gender == g,
                    onTap: () => setState(() => _gender = g),
                  )),
                  if (g != Gender.values.last) const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 16),
              _NumberField(
                label: 'AGE',
                value: _age.toString(),
                onTap: () => _pickNumber('Age', _age.toDouble(), 10, 120,
                    (double v) => setState(() => _age = v.round())),
              ),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(child: _ToggleField(
                  label: 'HEIGHT (CM)',
                  known: _heightKnown,
                  value: _heightCm,
                  onChanged: (bool k) => setState(() => _heightKnown = k),
                  onTap: () => _pickNumber('Height (cm)', _heightCm, 100, 230,
                      (double v) => setState(() => _heightCm = v)),
                )),
                const SizedBox(width: 12),
                Expanded(child: _ToggleField(
                  label: 'WEIGHT (KG)',
                  known: _weightKnown,
                  value: _weightKg,
                  onChanged: (bool k) => setState(() => _weightKnown = k),
                  onTap: () => _pickNumber('Weight (kg)', _weightKg, 30, 250,
                      (double v) => setState(() => _weightKg = v)),
                )),
              ]),
              if (_heightKnown && _weightKnown) ...<Widget>[
                const SizedBox(height: 12),
                _BmiChip(bmi: bmiFromMetrics(_heightCm, _weightKg)),
              ],
              const SizedBox(height: 18),
              Row(children: <Widget>[
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip'),
                )),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save & continue'),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickNumber(String label, double value, double min, double max,
      ValueChanged<double> onChanged) async {
    double current = value;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          title: Text(label),
          content: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: current > min
                  ? () => setDialogState(() => current -= 1)
                  : null,
            ),
            const SizedBox(width: 16),
            Text(current.toStringAsFixed(0),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: current < max
                  ? () => setDialogState(() => current += 1)
                  : null,
            ),
          ]),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    onChanged(current);
  }

  Future<void> _save() async {
    final UserProfile profile = UserProfile(
      gender: _gender,
      age: _age,
      heightCm: _heightKnown ? _heightCm : null,
      weightKg: _weightKnown ? _weightKg : null,
      heightKnown: _heightKnown,
      weightKnown: _weightKnown,
    );
    await context.read<ScanHistory>().setProfile(profile);
    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.accent : AppColors.outline),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.accent : AppColors.textSecondary)),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textTertiary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          const Icon(Icons.edit, size: 14, color: AppColors.textTertiary),
        ]),
      ),
    );
  }
}

class _ToggleField extends StatelessWidget {
  const _ToggleField({
    required this.label,
    required this.known,
    required this.value,
    required this.onChanged,
    required this.onTap,
  });
  final String label;
  final bool known;
  final double value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(children: <Widget>[
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textTertiary)),
            const SizedBox(height: 4),
            Text(known ? value.toStringAsFixed(0) : "Don't know",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: known ? AppColors.textPrimary : AppColors.textTertiary)),
          ])),
          Switch(value: known, onChanged: onChanged),
        ]),
      ),
    );
  }
}

class _BmiChip extends StatelessWidget {
  const _BmiChip({required this.bmi});
  final double bmi;

  @override
  Widget build(BuildContext context) {
    final String category = bmi < 18.5
        ? 'Underweight'
        : bmi < 25
            ? 'Normal'
            : bmi < 30
                ? 'Overweight'
                : 'Obese';
    final Color color = bmi < 18.5
        ? AppColors.amber
        : bmi < 25
            ? AppColors.mint
            : bmi < 30
                ? AppColors.accentSoft
                : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: <Widget>[
        const Icon(Icons.monitor_weight, size: 15),
        const SizedBox(width: 8),
        Text('BMI ${bmi.toStringAsFixed(1)} · $category',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
