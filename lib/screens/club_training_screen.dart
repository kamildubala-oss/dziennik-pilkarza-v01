import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';

const List<String> _focusOptions = <String>[
  'Prowadzenie',
  'Strzał',
  'Decyzyjność',
  'Siła',
  'Mentalność',
];

/// Ocena treningu klubowego: ocena, co było dobrze, co trzeba poprawić,
/// notatki. Termin treningu wynika z profilu, więc nie jest tu edytowany.
/// Dane trafiają do dziennika, a trener AI może się do nich odnieść.
class ClubTrainingScreen extends StatefulWidget {
  const ClubTrainingScreen({super.key, required this.event});

  final EventItem event;

  @override
  State<ClubTrainingScreen> createState() => _ClubTrainingScreenState();
}

class _ClubTrainingScreenState extends State<ClubTrainingScreen> {
  final TextEditingController _wentWell = TextEditingController();
  final TextEditingController _toImprove = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final Set<String> _focus = <String>{};
  int _rating = 3;
  bool _loading = true;
  bool _saving = false;
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = widget.event;
    if (e.source == 'trainings' && e.sourceId.isNotEmpty) {
      final t = await Api.getTraining(e.sourceId);
      if (t != null) {
        _rated = true;
        _wentWell.text = t.wentWell;
        _toImprove.text = t.toImprove;
        _notes.text = t.notes;
        _focus.addAll(t.focuses.where(_focusOptions.contains));
        if (t.rating >= 1) _rating = t.rating;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _wentWell.dispose();
    _toImprove.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Api.rateClubTraining(
        widget.event,
        focuses: _focusOptions.where(_focus.contains).toList(),
        rating: _rating,
        wentWell: _wentWell.text.trim(),
        toImprove: _toImprove.text.trim(),
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nie udało się zapisać: $error")));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = widget.event;
    final info = <String>[
      first10(e.date),
      if (e.time.isNotEmpty) 'godz. ${e.time}',
      if (e.durationMin > 0) '${e.durationMin} min',
    ].join(' · ');
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: _rated ? 'Edytuj ocenę treningu' : 'Oceń trening klubowy',
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: Spinner())
                : SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(Sp.md),
                          margin: const EdgeInsets.only(bottom: Sp.lg),
                          decoration: BoxDecoration(
                            color: c.surfaceSecondary,
                            borderRadius: BorderRadius.circular(Rad.md),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: Sp.sm),
                                decoration: BoxDecoration(
                                  color: eventTypeColor(c, 'club_training'),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Trening klubowy',
                                      style: manrope(
                                        size: 15,
                                        weight: FontWeight.w700,
                                        color: c.onSurface,
                                      ),
                                    ),
                                    Text(
                                      info,
                                      style: manrope(size: 12, color: c.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        LabeledField(
                          label: 'Ocena treningu',
                          child: RatingStars(
                            rating: _rating,
                            onChanged: (n) => setState(() => _rating = n),
                          ),
                        ),
                        LabeledField(
                          label: 'Nad czym pracowaliście? (opcjonalnie)',
                          child: ChipsWrap(
                            children: [
                              for (final f in _focusOptions)
                                ChipOption(
                                  label: f,
                                  selected: _focus.contains(f),
                                  onTap: () => setState(() {
                                    if (!_focus.remove(f)) _focus.add(f);
                                  }),
                                ),
                            ],
                          ),
                        ),
                        LabeledField(
                          label: 'Co było dobrze?',
                          child: AppTextField(
                            controller: _wentWell,
                            multiline: true,
                            minLines: 3,
                            hint: 'np. Dobre podania w grze na małym polu...',
                          ),
                        ),
                        LabeledField(
                          label: 'Co trzeba poprawić?',
                          child: AppTextField(
                            controller: _toImprove,
                            multiline: true,
                            minLines: 3,
                            hint:
                                'np. Ustawianie się przy stałych fragmentach...',
                          ),
                        ),
                        LabeledField(
                          label: 'Notatki',
                          child: AppTextField(
                            controller: _notes,
                            multiline: true,
                            minLines: 2,
                            hint: 'np. Uwagi trenera klubowego...',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: Sp.sm),
                          child: Text(
                            'Trener indywidualny uwzględni tę ocenę w rozmowie i analizie.',
                            style: manrope(size: 12, color: c.muted),
                          ),
                        ),
                        PrimaryButton(
                          label: _saving
                              ? 'Zapisywanie...'
                              : _rated
                                  ? 'Zapisz zmiany'
                                  : 'ZAPISZ OCENĘ',
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
}
