import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../llm.dart';
import '../llm_settings.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Ustawienia trenera AI: własny klucz API Google Gemini.
/// Bez własnego klucza trener działa offline.
class AiKeyScreen extends StatefulWidget {
  const AiKeyScreen({super.key});

  @override
  State<AiKeyScreen> createState() => _AiKeyScreenState();
}

class _AiKeyScreenState extends State<AiKeyScreen> {
  final TextEditingController _key = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _message;
  bool _messageOk = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _show(String msg, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _messageOk = ok;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isNotEmpty) setState(() => _key.text = t);
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await Llm.testKey(key);
      if (r.error == null) {
        await LlmSettings.setCustomKey(key);
        _key.clear();
        _show('Klucz działa i został zapisany.', ok: true);
        return;
      }
      if (!r.networkError) {
        _show(r.error!, ok: false);
        return;
      }
      if (!mounted) return;
      final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nie udało się sprawdzić klucza'),
          content: Text('${r.error}\n\nZapisać klucz mimo to?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Zapisz'),
            ),
          ],
        ),
      );
      if (save == true) {
        await LlmSettings.setCustomKey(key);
        _key.clear();
        _show('Klucz zapisany (bez sprawdzenia).', ok: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testCurrent() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await Llm.testKey(LlmSettings.activeKey);
      _show(r.error ?? 'Obecny klucz działa.', ok: r.error == null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    await LlmSettings.clearCustomKey();
    _show('Usunięto klucz API. Trener działa offline.', ok: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final custom = LlmSettings.usingCustom;
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: 'Klucz API trenera AI',
            onClose: () => Navigator.of(context).pop(true),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- Obecny klucz ----------
                  Container(
                    padding: const EdgeInsets.all(Sp.lg),
                    decoration: BoxDecoration(
                      color: c.surfaceSecondary,
                      borderRadius: BorderRadius.circular(Rad.lg),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          custom ? Icons.vpn_key : Icons.vpn_key_outlined,
                          color: c.brandPrimary,
                        ),
                        const SizedBox(width: Sp.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                LlmSettings.hasKey
                                    ? 'Używasz własnego klucza'
                                    : 'Brak klucza - tryb offline',
                                style: manrope(
                                  size: 15,
                                  weight: FontWeight.w700,
                                  color: c.onSurface,
                                ),
                              ),
                              if (LlmSettings.hasKey)
                                Text(
                                  LlmSettings.mask(LlmSettings.activeKey),
                                  style: manrope(size: 12, color: c.muted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (LlmSettings.hasKey)
                    SecondaryButton(
                      label: 'Sprawdź klucz',
                      icon: Icons.wifi_tethering,
                      onTap: _busy ? null : _testCurrent,
                    ),
                  if (custom)
                    SecondaryButton(
                      label: 'Usuń klucz',
                      icon: Icons.restore,
                      onTap: _busy ? null : _reset,
                    ),
                  const SizedBox(height: Sp.xl),

                  // ---------- Nowy klucz ----------
                  const SectionTitle('WPISZ WŁASNY KLUCZ'),
                  const SizedBox(height: Sp.sm),
                  Text(
                    'Klucz Google Gemini utworzysz za darmo w Google AI Studio: '
                    'aistudio.google.com/app/apikey. Klucz jest zapisywany tylko '
                    'na tym telefonie i nie trafia do eksportowanej kopii zapasowej.',
                    style: manrope(
                        size: 12, height: 1.45, color: c.onSurfaceSecondary),
                  ),
                  const SizedBox(height: Sp.md),
                  TextField(
                    controller: _key,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    style: manrope(size: 15, color: c.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Klucz API (AQ... lub AIza...)',
                      hintStyle: manrope(size: 15, color: c.muted),
                      filled: true,
                      fillColor: c.surfaceSecondary,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: Sp.lg, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Rad.md),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Wklej',
                            icon: Icon(Icons.content_paste,
                                size: 20, color: c.muted),
                            onPressed: _paste,
                          ),
                          IconButton(
                            tooltip: _obscure ? 'Pokaż' : 'Ukryj',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: c.muted,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PrimaryButton(
                    label: _busy ? 'Sprawdzanie...' : 'Sprawdź i zapisz',
                    marginTop: Sp.md,
                    onTap: _busy || _key.text.trim().isEmpty ? null : _save,
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: Sp.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _messageOk ? Icons.check_circle : Icons.error_outline,
                          size: 18,
                          color: _messageOk
                              ? const Color(0xFF16A34A)
                              : c.brandSecondary,
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: Text(
                            _message!,
                            style: manrope(
                                size: 13, height: 1.4, color: c.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
