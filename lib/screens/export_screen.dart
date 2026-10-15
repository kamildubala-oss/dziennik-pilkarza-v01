import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../file_bridge.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';

/// Eksport danych (CSV / pełna kopia JSON) - zapis na telefonie lub
/// udostępnienie - oraz przywracanie danych z kopii.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _busy = false;
  bool _restored = false;

  String get _stamp => todayIso();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(
    Future<String> Function() build,
    String name,
    String mime, {
    required bool share,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(await build()));
      if (share) {
        await FileBridge.shareFile(name, mime, bytes);
      } else {
        final saved = await FileBridge.saveFile(name, mime, bytes);
        if (saved) _toast('Zapisano plik $name');
      }
    } on MissingPluginException {
      _toast('Zapis plików działa w aplikacji na Androidzie.');
    } catch (e) {
      _toast('Nie udało się wykonać eksportu: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await FileBridge.openFile();
      if (bytes == null) return; // anulowano
      final json = utf8.decode(bytes, allowMalformed: true);
      final counts = Api.inspectBackup(json);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Przywrócić dane z kopii?'),
          content: Text(
            'Kopia zawiera: ${counts['trainings']} treningów, '
            '${counts['matches']} meczów i ${counts['events']} wpisów w kalendarzu.\n\n'
            'Obecne dane w aplikacji zostaną zastąpione. '
            'Jeśli chcesz je zachować, najpierw zapisz ich kopię.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Przywróć'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await Api.importBackup(json);
      _restored = true;
      _toast('Przywrócono dane z kopii.');
    } on MissingPluginException {
      _toast('Przywracanie działa w aplikacji na Androidzie.');
    } on ApiException catch (e) {
      _toast(e.body);
    } catch (e) {
      _toast('Nie udało się przywrócić danych: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: 'Eksport i kopia zapasowa',
            onClose: () => Navigator.of(context).pop(_restored),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Wszystkie wpisy są zapisywane na tym telefonie automatycznie. '
                    'Zrób kopię do pliku, żeby nie stracić danych po odinstalowaniu '
                    'aplikacji lub zmianie telefonu.',
                    style: manrope(
                        size: 13, height: 1.45, color: c.onSurfaceSecondary),
                  ),
                  const SizedBox(height: Sp.lg),
                  _card(
                    c,
                    icon: Icons.backup_outlined,
                    title: 'Pełna kopia zapasowa',
                    subtitle:
                        'Treningi, mecze, kalendarz, profil i plany (plik JSON). '
                        'Można ją przywrócić w aplikacji.',
                    onSave: () => _run(Api.exportBackup,
                        'dziennik-kopia-$_stamp.json', 'application/json',
                        share: false),
                    onShare: () => _run(Api.exportBackup,
                        'dziennik-kopia-$_stamp.json', 'application/json',
                        share: true),
                  ),
                  _card(
                    c,
                    icon: Icons.table_chart_outlined,
                    title: 'Treningi (CSV)',
                    subtitle:
                        'Treningi własne i klubowe: data, obszary, czas, ocena i notatki. '
                        'Otwiera się w Excelu i Arkuszach Google.',
                    onSave: () => _run(Api.exportTrainingsCsv,
                        'treningi-$_stamp.csv', 'text/csv',
                        share: false),
                    onShare: () => _run(Api.exportTrainingsCsv,
                        'treningi-$_stamp.csv', 'text/csv',
                        share: true),
                  ),
                  _card(
                    c,
                    icon: Icons.sports_soccer,
                    title: 'Mecze (CSV)',
                    subtitle:
                        'Przeciwnik, wynik, minuty, gole, asysty, ocena i notatki.',
                    onSave: () => _run(
                        Api.exportMatchesCsv, 'mecze-$_stamp.csv', 'text/csv',
                        share: false),
                    onShare: () => _run(
                        Api.exportMatchesCsv, 'mecze-$_stamp.csv', 'text/csv',
                        share: true),
                  ),
                  const SizedBox(height: Sp.md),
                  const SectionTitle('PRZYWRACANIE'),
                  const SizedBox(height: Sp.sm),
                  Text(
                    'Wybierz wcześniej zapisany plik kopii (dziennik-kopia-....json).',
                    style: manrope(size: 12, color: c.muted),
                  ),
                  SecondaryButton(
                    label: _busy ? 'Proszę czekać...' : 'Przywróć kopię',
                    icon: Icons.restore,
                    marginTop: Sp.md,
                    onTap: _busy ? null : _restore,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    AppColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onSave,
    required VoidCallback onShare,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: c.brandPrimary),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  title,
                  style: manrope(
                      size: 16, weight: FontWeight.w700, color: c.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: manrope(size: 12, height: 1.4, color: c.muted)),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: _smallButton(c, 'Zapisz', Icons.download,
                    primary: true, onTap: _busy ? null : onSave),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _smallButton(c, 'Udostępnij', Icons.share_outlined,
                    primary: false, onTap: _busy ? null : onShare),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallButton(AppColors c, String label, IconData icon,
      {required bool primary, VoidCallback? onTap}) {
    final bg = primary ? c.brandPrimary : c.surface;
    final fg = primary ? c.onBrandPrimary : c.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Rad.pill),
            border: primary ? null : Border.all(color: c.borderStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: manrope(
                      size: 12,
                      weight: FontWeight.w800,
                      letterSpacing: 1,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
