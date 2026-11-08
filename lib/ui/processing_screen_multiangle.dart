import 'package:flutter/material.dart';

import '../core/profile_report.dart';
import '../state/profile_analysis_controller.dart';
import 'results_screen_multiangle.dart';
import 'theme.dart';

/// Runs [ProfileAnalysisController.analyse] and then shows the result.
/// A missing side photo yields a "no reading" report, never a hang.
class ProcessingScreenMultiAngle extends StatefulWidget {
  const ProcessingScreenMultiAngle({super.key, required this.scan});

  final MultiAngleScan scan;

  @override
  State<ProcessingScreenMultiAngle> createState() =>
      _ProcessingScreenMultiAngleState();
}

class _ProcessingScreenMultiAngleState
    extends State<ProcessingScreenMultiAngle> {
  Future<ProfileAnalysisReport>? _future;

  @override
  void initState() {
    super.initState();
    _future = ProfileAnalysisController().analyse(widget.scan);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FutureBuilder<ProfileAnalysisReport>(
            future: _future,
            builder: (BuildContext context,
                AsyncSnapshot<ProfileAnalysisReport> snapshot) {
              if (snapshot.hasData) {
                return ResultsScreenMultiAngle(report: snapshot.data!);
              }
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Analysing front, left and right profiles…',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    SizedBox(height: 8),
                    Text('On this device. Nothing uploads.',
                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
