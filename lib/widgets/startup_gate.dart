import 'dart:async';
import 'package:flutter/material.dart';

/// Pierwsza klatka nie zależy od pamięci telefonu ani synchronizacji bazy.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.initialize, required this.child,
    this.timeout = const Duration(seconds: 15), this.failureBuilder});
  final Future<void> Function() initialize;
  final Widget child;
  final Duration timeout;
  final Widget Function(BuildContext, Object, VoidCallback)? failureBuilder;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  Future<void>? _pending;
  Object? _error;
  bool _ready = false;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    // Pozwalamy najpierw narysować ekran startowy.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _run(); });
  }
  Future<void> _run() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    final pending = _pending ??= Future<void>.sync(widget.initialize);
    // Timeout nie anuluje operacji platformowej. Ponowienie czeka na ten sam
    // odczyt, zamiast uruchamiać kolejne operacje w zablokowanej kolejce.
    pending.then<void>((_) {
      if (identical(_pending, pending)) _pending = null;
    }, onError: (Object error, StackTrace stack) {
      if (identical(_pending, pending)) _pending = null;
    });
    try {
      await pending.timeout(widget.timeout);
      if (!mounted) return;
      setState(() { _ready = true; _loading = false; });
    } catch (error) {
      // Bez treści bazy, klucza API ani innych danych zawodnika w logu.
      debugPrint('DziennikStartup: initialization failed (${error.runtimeType})');
      if (mounted) setState(() { _error = error; _loading = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    final error = _error;
    if (!_loading && error != null) {
      return widget.failureBuilder?.call(context, error, _run) ??
          StartupErrorView(onRetry: _run, timedOut: error is TimeoutException);
    }
    return const Scaffold(body: SafeArea(child: Center(child: Padding(
      padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.sports_soccer, size: 48),
        SizedBox(height: 20),
        Text('Dziennik Piłkarza', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        CircularProgressIndicator(semanticsLabel: 'Uruchamianie aplikacji'),
        SizedBox(height: 16),
        Text('Przygotowuję Twój dziennik…', textAlign: TextAlign.center),
      ]),
    ))));
  }
}

class StartupErrorView extends StatelessWidget {
  const StartupErrorView({super.key, required this.onRetry, this.timedOut = false});
  final VoidCallback onRetry;
  final bool timedOut;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.refresh, size: 48), const SizedBox(height: 16),
        Text(timedOut ? 'Uruchamianie trwa zbyt długo' : 'Nie udało się uruchomić aplikacji',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Twoje zapisane dane nie zostały usunięte. Spróbuj ponownie. '
          'Jeśli problem się powtarza, zamknij i ponownie otwórz aplikację.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh),
          label: const Text('Spróbuj ponownie')),
      ]),
    ),
  )));
}
