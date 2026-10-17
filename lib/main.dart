import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'llm_settings.dart';
import 'api.dart';
import 'screens/home_shell.dart';
import 'screens/export_screen.dart';
import 'theme.dart';
import 'widgets/startup_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  runApp(ChangeNotifierProvider<ThemeController>.value(
    value: themeController, child: const DziennikApp(),
  ));
}

class DatabaseStartupFailure implements Exception {
  const DatabaseStartupFailure();
}

Future<void> initializeApplication(ThemeController themeController) async {
  // Orientacja nie może zatrzymać pierwszego wyświetlenia interfejsu.
  try {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]).timeout(const Duration(seconds: 2));
  } catch (_) {
    debugPrint('DziennikStartup: orientation preference unavailable');
  }
  await themeController.load();
  await LlmSettings.load();
  try {
    await Api.synchronizeCalendar();
  } catch (_) {
    throw const DatabaseStartupFailure();
  }
}

class DziennikApp extends StatelessWidget {
  const DziennikApp({super.key, this.startupError});
  final Object? startupError;

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
      home: startupError == null
          ? StartupGate(
              initialize: () => initializeApplication(controller),
              failureBuilder: (context, error, retry) => error is DatabaseStartupFailure
                  ? _DatabaseRecoveryScreen(onRetry: retry)
                  : StartupErrorView(onRetry: retry, timedOut: error is TimeoutException),
              child: const HomeShell(),
            )
          : const _DatabaseRecoveryScreen(),
    );
  }
}

/// Gdy lokalna baza jest uszkodzona i nie ma kopii awaryjnej, nie otwieramy
/// interfejsu dodawania wpisów. Użytkownik może bezpiecznie przywrócić eksport.
class _DatabaseRecoveryScreen extends StatefulWidget {
  const _DatabaseRecoveryScreen({this.onRetry});
  final VoidCallback? onRetry;

  @override
  State<_DatabaseRecoveryScreen> createState() => _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<_DatabaseRecoveryScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ExportScreen()),
    );
    if (!mounted || restored != true) return;
    setState(() => _busy = true);
    try {
      await Api.synchronizeCalendar();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeShell()),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nie udało się przywrócić danych. Sprawdź plik kopii.'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bezpieczeństwo dziennika')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Nie można bezpiecznie odczytać zapisanych danych.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nie pozwalamy dodawać nowych wpisów, żeby nie nadpisać '
                'istniejących danych. Przywróć dziennik z wcześniej '
                'zapisanej kopii zapasowej.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (widget.onRetry != null) TextButton(onPressed: widget.onRetry, child: const Text('Spróbuj ponownie')),
              ElevatedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: Text(_busy ? 'Sprawdzanie...' : 'Przywróć dane z kopii'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
