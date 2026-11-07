import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/analysis_controller.dart';
import 'ui/camera_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FacialAnalysisApp());
}

class FacialAnalysisApp extends StatelessWidget {
  const FacialAnalysisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AnalysisController>(
      create: (BuildContext context) => AnalysisController(),
      child: MaterialApp(
        title: 'Face Geometry',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const CameraScreen(),
      ),
    );
  }
}
