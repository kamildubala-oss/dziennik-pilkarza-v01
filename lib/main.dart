import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'llm_settings.dart';
import 'api.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  final themeController = ThemeController();
  await themeController.load();
  await LlmSettings.load();
  await Api.synchronizeCalendar();
  runApp(
    ChangeNotifierProvider<ThemeController>.value(
      value: themeController,
      child: const DziennikApp(),
    ),
  );
}

class DziennikApp extends StatelessWidget {
  const DziennikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    return MaterialApp(
      title: 'Dziennik Piłkarza',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AppColors.light, Brightness.light),
      darkTheme: buildTheme(AppColors.dark, Brightness.dark),
      themeMode: controller.themeMode,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const <Locale>[Locale('pl'), Locale('en')],
      builder: (context, child) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isLight ? Brightness.dark : Brightness.light,
            statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeShell(),
    );
  }
}
