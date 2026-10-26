import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../services/user_errors.dart';
import '../models.dart';
import '../theme.dart';
import '../llm_settings.dart';
import '../utils.dart';
import 'ai_key_screen.dart';
import 'export_screen.dart';
import '../widgets/common.dart';
import '../widgets/player_jersey.dart';

const List<String> _positions = <String>[
  'Bramkarz',
  'Obrońca',
  'Pomocnik',
  'Napastnik',
];
const List<String> _feet = <String>['Lewa', 'Prawa', 'Obie'];

class _ThemeOption {
  const _ThemeOption(this.pref, this.label, this.icon);

  final ThemePreference pref;
  final String label;
  final IconData icon;
}

/// Modal "Profil" (dane zawodnika + motyw aplikacji).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _jersey = TextEditingController();
  final TextEditingController _club = TextEditingController();
  final TextEditingController _goal = TextEditingController();
  final TextEditingController _clubTime = TextEditingController();
  final TextEditingController _clubDuration = TextEditingController(text: '90');
  final Set<int> _clubDays = <int>{};

  int _jerseyColor = 0xFF2563EB;
  int _numberColor = 0xFFFFFFFF;
  String _position = '';
  String _foot = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
    _jersey.addListener(_onNameChanged);
    _load();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _jersey.removeListener(_onNameChanged);
    _name.dispose();
    _age.dispose();
    _jersey.dispose();
    _club.dispose();
    _goal.dispose();
    _clubTime.dispose();
    _clubDuration.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Api.getProfile();
      if (!mounted) return;
      _name.text = p.name;
      _age.text = p.age != null ? '${p.age}' : '';
      _jersey.text = p.jerseyNumber != null ? '${p.jerseyNumber}' : '';
      _jerseyColor = p.jerseyColor;
      _numberColor = p.jerseyNumberColor;
      _club.text = p.club;
      _goal.text = p.seasonGoal;
      _position = p.position;
      _foot = p.dominantFoot;
      _clubDays
        ..clear()
        ..addAll(p.clubDays);
      _clubTime.text = p.clubTime;
      _clubDuration.text = '${p.clubDurationMin > 0 ? p.clubDurationMin : 90}';
    } catch (_) {
      // Jak w wersji React - przy błędzie formularz jest po prostu pusty.
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _colorChoice(String label, int value, ValueChanged<int> onChanged) {
    return OutlinedButton(
      onPressed: () async {
        final selected = await showDialog<int>(context: context,
          builder: (context) => AlertDialog(
            title: Text('Kolor: $label'),
            content: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final color in jerseyPalette)
                Semantics(label: color.name, selected: value == color.value,
                  child: InkWell(onTap: () => Navigator.pop(context, color.value),
                    child: Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: Color(color.value), shape: BoxShape.circle,
                        border: Border.all(color: context.c.muted)),
                      child: value == color.value ? Icon(Icons.check,
                        color: Color(color.value).computeLuminance() > 0.5 ? Colors.black : Colors.white) : null))),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj'))],
          ));
        if (selected != null && mounted) onChanged(selected);
      },
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 18, height: 18, decoration: BoxDecoration(color: Color(value),
          shape: BoxShape.circle, border: Border.all(color: context.c.muted))),
        const SizedBox(width: 6), Flexible(child: Text(label, maxLines: 1)),
      ]),
    );
  }

  Future<void> _save() async {
    if (_saving || ageFieldError(_age.text) != null) return;
    final pref = context.read<ThemeController>().preference;
    setState(() => _saving = true);
    try {
      await Api.updateProfile(
        Profile(
          name: _name.text.trim(),
          age: _age.text.trim().isNotEmpty
              ? int.parse(_age.text.trim())
              : null,
          position: _position,
          dominantFoot: _foot,
          club: _club.text.trim(),
          jerseyNumber: _jersey.text.trim().isNotEmpty
              ? int.tryParse(_jersey.text.trim())
              : null,
          jerseyColor: _jerseyColor,
          jerseyNumberColor: _numberColor,
          seasonGoal: _goal.text.trim(),
          theme: pref.name,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          clubDays: _clubDays.toList()..sort(),
          clubTime: _clubTime.text.trim(),
          clubDurationMin:
              (int.tryParse(_clubDuration.text.trim()) ?? 90).clamp(10, 300),
        ),
      );
      // Dodaje / usuwa treningi klubowe w kalendarzu.
      await Api.listEvents();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final themeCtrl = context.watch<ThemeController>();
    final name = _name.text;

    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: 'Profil',
            onClose: () => Navigator.of(context).pop(),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: Spinner()),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Sp.lg,
                  Sp.lg,
                  Sp.lg,
                  Sp.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------- Awatar ----------
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.xl),
                      child: Row(
                        children: [
                          PlayerJersey(size: 64, number: int.tryParse(_jersey.text),
                            color: Color(_jerseyColor), numberColor: Color(_numberColor)),
                          const SizedBox(width: Sp.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isNotEmpty
                                      ? 'Cześć, $name!'
                                      : 'Uzupełnij swój profil',
                                  style: manrope(
                                    size: 18,
                                    weight: FontWeight.w800,
                                    color: c.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Trener dostosuje porady do Twojej pozycji i wieku.',
                                  style: manrope(size: 12, color: c.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.only(top: Sp.sm, bottom: Sp.sm),
                      child: SectionTitle('DANE ZAWODNIKA'),
                    ),

                    LabeledField(
                      label: 'Imię',
                      child: AppTextField(controller: _name, hint: 'np. Kuba'),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: LabeledField(
                            label: 'Wiek',
                            child: AppTextField(
                              controller: _age,
                              keyboardType: TextInputType.number,
                              hint: '14',
                              errorText: ageFieldError(_age.text),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: LabeledField(
                            label: 'Numer',
                            child: AppTextField(
                              controller: _jersey,
                              keyboardType: TextInputType.number,
                              hint: '10',
                            ),
                          ),
                        ),
                      ],
                    ),
                    LabeledField(
                      label: 'Pozycja',
                      child: ChipsWrap(
                        children: [
                          for (final p in _positions)
                            ChipOption(
                              label: p,
                              selected: _position == p,
                              onTap: () => setState(() => _position = p),
                            ),
                        ],
                      ),
                    ),
                    LabeledField(
                      label: 'Dominująca noga',
                      child: ChipsWrap(
                        children: [
                          for (final f in _feet)
                            ChipOption(
                              label: f,
                              selected: _foot == f,
                              onTap: () => setState(() => _foot = f),
                            ),
                        ],
                      ),
                    ),
                    LabeledField(
                      label: 'Klub',
                      child: AppTextField(
                        controller: _club,
                        hint: 'np. Legia U15',
                      ),
                    ),
                    LabeledField(
                      label: 'Cel sezonu',
                      child: AppTextField(
                        controller: _goal,
                        multiline: true,
                        minLines: 3,
                        hint: 'np. 10 goli, debiut w pierwszym składzie...',
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.md),
                      child: Row(children: [
                        Expanded(child: _colorChoice('Koszulka', _jerseyColor,
                          (value) => setState(() => _jerseyColor = value))),
                        const SizedBox(width: Sp.sm),
                        Expanded(child: _colorChoice('Numer', _numberColor,
                          (value) => setState(() => _numberColor = value))),
                      ]),
                    ),
                    // ---------- Treningi klubowe ----------
                    const Padding(
                      padding: EdgeInsets.only(top: Sp.sm, bottom: Sp.sm),
                      child: SectionTitle('TRENINGI KLUBOWE'),
                    ),
                    LabeledField(
                      label: 'Dni treningów (możesz wybrać kilka)',
                      child: ChipsWrap(
                        children: [
                          for (var d = 1; d <= 7; d++)
                            ChipOption(
                              label: kWeekDays[d - 1],
                              selected: _clubDays.contains(d),
                              onTap: () => setState(() {
                                if (!_clubDays.remove(d)) _clubDays.add(d);
                              }),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: LabeledField(
                            label: 'Godzina',
                            child: TimeField(
                              controller: _clubTime,
                              hint: 'np. 17:00',
                            ),
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: LabeledField(
                            label: 'Czas (min)',
                            child: AppTextField(
                              controller: _clubDuration,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.lg),
                      child: Text(
                        _clubDays.isEmpty
                            ? 'Wybierz dni, a treningi klubowe same pojawią się w kalendarzu.'
                            : 'Po zapisaniu treningi klubowe pojawią się w kalendarzu na najbliższe 8 tygodni.',
                        style: manrope(size: 12, color: c.muted),
                      ),
                    ),

                    // ---------- Trener AI ----------
                    const Padding(
                      padding: EdgeInsets.only(top: Sp.sm, bottom: Sp.sm),
                      child: SectionTitle('TRYB TRENERA'),
                    ),
                    Text(
                      LlmSettings.hasKey
                          ? 'Własny klucz API: ${LlmSettings.mask(LlmSettings.activeKey)}'
                          : 'Brak klucza API - trener działa w trybie offline.',
                      style: manrope(size: 12, color: c.muted),
                    ),
                    const SizedBox(height: Sp.sm),
                    Text('Tryb trenera', style: manrope(size: 14, weight: FontWeight.w600, color: c.onSurface)),
                    DropdownButton<String>(
                      value: LlmSettings.mode,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Automatyczny')),
                        DropdownMenuItem(value: 'offline', child: Text('Tylko offline — prywatność')),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        await LlmSettings.setMode(value);
                        if (mounted) setState(() {});
                      },
                    ),
                    Text(
                      'Automatyczny próbuje Gemini z Twoim kluczem i przechodzi na offline przy błędzie; Tylko offline zawsze przetwarza dane na telefonie.',
                      style: manrope(size: 12, color: c.muted),
                    ),
                    SecondaryButton(
                      label: LlmSettings.usingCustom
                          ? 'Zmień klucz'
                          : 'Dodaj klucz API',
                      icon: Icons.vpn_key_outlined,
                      onTap: () async {
                        await pushModal<bool>(context, const AiKeyScreen());
                        if (mounted) setState(() {});
                      },
                    ),
                    const SizedBox(height: Sp.lg),

                    // ---------- Dane i kopia ----------
                    const Padding(
                      padding: EdgeInsets.only(top: Sp.sm, bottom: Sp.sm),
                      child: SectionTitle('DANE I KOPIA ZAPASOWA'),
                    ),
                    SecondaryButton(
                      label: 'Eksport i kopia',
                      icon: Icons.ios_share,
                      marginTop: 0,
                      onTap: () async {
                        final restored = await pushModal<bool>(
                          context,
                          const ExportScreen(),
                        );
                        if (restored == true && mounted) _load();
                      },
                    ),
                    const SizedBox(height: Sp.lg),

                    // ---------- Motyw ----------
                    const Padding(
                      padding: EdgeInsets.only(top: Sp.sm, bottom: Sp.sm),
                      child: SectionTitle('MOTYW APLIKACJI'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.xl),
                      child: Row(
                        children: withGap(
                          <_ThemeOption>[
                            const _ThemeOption(
                              ThemePreference.light,
                              'Jasny',
                              Icons.light_mode,
                            ),
                            const _ThemeOption(
                              ThemePreference.dark,
                              'Ciemny',
                              Icons.dark_mode,
                            ),
                            const _ThemeOption(
                              ThemePreference.system,
                              'Systemowy',
                              Icons.smartphone,
                            ),
                          ].map((t) => _themeCard(c, themeCtrl, t)).toList(),
                          width: Sp.sm,
                        ),
                      ),
                    ),

                    PrimaryButton(
                      label: _saving ? 'Zapisywanie...' : 'Zapisz',
                      onTap: _saving ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _themeCard(AppColors c, ThemeController ctrl, _ThemeOption t) {
    final active = ctrl.preference == t.pref;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ctrl.setPreference(t.pref),
        child: Container(
          height: 90,
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: active ? c.brandTertiary : c.surfaceSecondary,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(
              color: active ? c.brandPrimary : c.border,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      t.icon,
                      size: 24,
                      color: active ? c.onBrandTertiary : c.onSurface,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.label,
                      style: manrope(
                        size: 13,
                        weight: FontWeight.w700,
                        color: active ? c.onBrandTertiary : c.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: c.brandPrimary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
