import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/scan_history.dart';
import 'state/analysis_controller.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  // Every async error anywhere in the app lands here (or in the two handlers
  // below) instead of dying silently on the "ANALYSING" screen, which is how
  // a crash used to present as a dead spinner or an unexplained "NO READING".
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('CRASH: ${details.exception}');
      debugPrint(details.stack?.toString() ?? '(no stack)');
      FlutterError.presentError(details);
    };
    ui.PlatformDispatcher.instance.onError =
        (Object error, StackTrace stack) {
          debugPrint('CRASH: $error');
          debugPrint(stack.toString());
          return true;
        };

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
  }, (Object error, StackTrace stack) {
    debugPrint('CRASH: $error');
    debugPrint(stack.toString());
  });
}

class FacialAnalysisApp extends StatelessWidget {
  const FacialAnalysisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ScanHistory>(
          create: (BuildContext context) => ScanHistory(),
        ),
        ChangeNotifierProvider<AnalysisController>(
          create: (BuildContext context) =>
              AnalysisController(history: context.read<ScanHistory>()),
        ),
      ],
      child: MaterialApp(
        title: 'Face Geometry',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
