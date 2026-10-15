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
const List<String> _intensities = <String>['low', 'medium', 'high'];

String _intensityLabel(String i) {
  if (i == 'low') return 'Niska';
  if (i == 'medium') return 'Średnia';
  return 'Wysoka';
}

/// Modal "Zapisz trening".
class LogSessionScreen extends StatefulWidget {
  const LogSessionScreen({
    super.key,
    this.initialDate,
    this.title,
    this.header,
    this.kind = 'training',
    this.initialFocuses,
    this.initialDuration,
    this.initialIntensity,
    this.plannedEventId,
    this.editing,
    this.editingEvent,
    this.isPlanned = false,
  });

  /// Edytowany trening (tryb edycji). Gdy null - nowy wpis.
  final Training? editing;
  final EventItem? editingEvent;

  /// 'training' (zwykły) lub 'club_training' (klubowy).
  final String kind;

  /// Wstępnie zaznaczone obszary (np. z planu tygodnia).
  final List<String>? initialFocuses;
  final int? initialDuration;
  final String? initialIntensity;

  /// Zaplanowany trening z kalendarza, który zawodnik właśnie wykonał.
  final String? plannedEventId;

  /// True, gdy zapisujemy plan z kalendarza, a nie wykonaną już aktywność.
  final bool isPlanned;

  /// Data początkowa (RRRR-MM-DD). Domyślnie dzisiaj.
  final String? initialDate;

  /// Tytuł okna. Domyślnie jak w dzienniku.
  final String? title;

  /// Dodatkowa sekcja na górze formularza (np. wybór typu w kalendarzu).
  final Widget? header;

  @override
  State<LogSessionScreen> createState() => _LogSessionScreenState();
}

class _LogSessionScreenState extends State<LogSessionScreen> {
  late final Training? _e = widget.editing;
  late final TextEditingController _date = TextEditingController(
    text: _e != null ? first10(_e.date) : (widget.editingEvent?.date ?? widget.initialDate ?? todayIso()),
  );
  late final TextEditingController _duration = TextEditingController(
    text:
        '${_e?.durationMin ?? widget.editingEvent?.durationMin ?? widget.initialDuration ?? (widget.kind == 'club_training' ? 90 : 45)}',
  );
  late final TextEditingController _wentWell =
      TextEditingController(text: _e?.wentWell ?? '');
  late final TextEditingController _toImprove =
      TextEditingController(text: _e?.toImprove ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: _e?.notes ?? '');

  late final Set<String> _focus = <String>{
    ...?(_e?.focuses ?? widget.initialFocuses ?? (widget.editingEvent?.focus.split(', ').where(_focusOptions.contains).toList()))?.where(_focusOptions.contains),
  };
  late String _intensity =
      _intensities.contains(_e?.intensity ?? widget.initialIntensity ?? widget.editingEvent?.intensity)
          ? (_e?.intensity ?? widget.initialIntensity ?? widget.editingEvent?.intensity)!
          : 'medium';
  late int _rating = _e != null && _e.rating >= 1 ? _e.rating : 3;
  bool _saving = false;

  @override
  void dispose() {
    _date.dispose();
    _duration.dispose();
    _wentWell.dispose();
    _toImprove.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _focus.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (widget.editingEvent != null) {
        final event = widget.editingEvent!;
        final focusList = _focusOptions.where(_focus.contains).toList();
        await Api.updateEvent(event.id,
          date: _date.text,
          time: event.time,
          title: '${widget.kind == 'club_training' ? 'Trening klubowy' : 'Trening'}: ${focusList.join(', ')}',
          description: 'Czas: ${_duration.text} min · Obszary: ${focusList.join(', ')}',
          details: <String, dynamic>{'focus': focusList.join(', '), 'focuses': focusList, 'duration_min': int.tryParse(_duration.text) ?? 0, 'intensity': _intensity, 'rating': _rating, 'went_well': _wentWell.text, 'to_improve': _toImprove.text, 'notes': _notes.text},
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final e = _e;
      if (e != null) {
        await Api.updateTraining(
          e.id,
          date: _date.text,
          durationMin: int.tryParse(_duration.text.trim()) ?? 0,
          focuses: _focusOptions.where(_focus.contains).toList(),
          intensity: _intensity,
          rating: _rating,
          wentWell: _wentWell.text,
          toImprove: _toImprove.text,
          notes: _notes.text,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await Api.createTraining(
        date: _date.text,
        durationMin: int.tryParse(_duration.text.trim()) ?? 0,
        // Kolejność jak na liście wyboru.
        focuses: _focusOptions.where(_focus.contains).toList(),
        kind: widget.kind,
        plannedEventId: widget.plannedEventId,
        isPlanned: widget.isPlanned,
        intensity: _intensity,
        rating: _rating,
        wentWell: _wentWell.text,
        toImprove: _toImprove.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: widget.title ??
                (_e != null
                    ? 'Edytuj trening'
                    : widget.kind == 'club_training'
                        ? 'Zapisz trening klubowy'
                        : 'Zapisz trening'),
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.header != null) widget.header!,
                  LabeledField(
                    label: 'Data',
                    child: DateField(controller: _date),
                  ),
                  LabeledField(
                    label: 'Czas (min)',
                    child: AppTextField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  LabeledField(
                    label: 'Nad czym pracowałeś? (możesz wybrać kilka)',
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
                    label: 'Intensywność',
                    child: ChipsWrap(
                      children: [
                        for (final i in _intensities)
                          ChipOption(
                            label: _intensityLabel(i),
                            selected: _intensity == i,
                            onTap: () => setState(() => _intensity = i),
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
                    label: 'Co było dobrze?',
                    child: AppTextField(
                      controller: _wentWell,
                      multiline: true,
                      minLines: 3,
                      hint: 'np. Lepsze przyjęcie piłki...',
                    ),
                  ),
                  LabeledField(
                    label: 'Co trzeba poprawić?',
                    child: AppTextField(
                      controller: _toImprove,
                      multiline: true,
                      minLines: 3,
                      hint: 'np. Celność strzału z dystansu...',
                    ),
                  ),
                  LabeledField(
                    label: 'Notatki',
                    child: AppTextField(
                      controller: _notes,
                      multiline: true,
                      minLines: 2,
                    ),
                  ),
                  PrimaryButton(
                    label: _saving
                        ? 'Zapisywanie...'
                        : _focus.isEmpty
                            ? 'Wybierz obszar'
                            : _e != null
                                ? 'Zapisz zmiany'
                                : 'Zapisz trening',
                    onTap: _saving || _focus.isEmpty ? null : _save,
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
