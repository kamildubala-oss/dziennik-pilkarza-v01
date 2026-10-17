import 'package:flutter/material.dart';

/// Chroni zarówno przycisk zamknięcia, jak i systemowe cofnięcie.
class FormExitGuard extends StatefulWidget {
  const FormExitGuard({
    super.key,
    required this.fingerprint,
    required this.listenables,
    required this.child,
  });
  final String Function() fingerprint;
  final List<Listenable> listenables;
  final Widget child;
  @override
  State<FormExitGuard> createState() => FormExitGuardState();
}

class FormExitGuardState extends State<FormExitGuard> {
  late String _initial;
  bool _leaving = false;
  bool _asking = false;
  bool get dirty => widget.fingerprint() != _initial;
  @override
  void initState() {
    super.initState();
    _initial = widget.fingerprint();
    for (final item in widget.listenables) {
      item.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final item in widget.listenables) {
      item.removeListener(_changed);
    }
    super.dispose();
  }

  Future<void> finish([bool? result]) async {
    if (!mounted || _leaving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> close() async {
    if (_asking || _leaving) return;
    if (!dirty) {
      await finish();
      return;
    }
    _asking = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Odrzucić zmiany?'),
        content: const Text(
          'Masz niezapisane zmiany. Możesz wrócić do formularza i je zapisać.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Wróć do formularza'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Odrzuć'),
          ),
        ],
      ),
    );
    _asking = false;
    if (discard == true) await finish();
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _leaving || !dirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) close();
    },
    child: widget.child,
  );
}
