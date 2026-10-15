import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';

/// Modal "Zapisz mecz".
class LogMatchScreen extends StatefulWidget {
  const LogMatchScreen({
    super.key,
    this.initialDate,
    this.title,
    this.header,
    this.plannedEventId,
    this.editing,
    this.isPlanned = false,
  });

  /// Edytowany mecz (tryb edycji). Gdy null - nowy wpis.
  final MatchEntry? editing;

  /// Zaplanowany mecz z kalendarza, który właśnie się odbył.
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
  State<LogMatchScreen> createState() => _LogMatchScreenState();
}

class _LogMatchScreenState extends State<LogMatchScreen> {
  late final MatchEntry? _e = widget.editing;
  late final TextEditingController _date = TextEditingController(
    text: _e != null ? first10(_e.date) : (widget.initialDate ?? todayIso()),
  );
  late final TextEditingController _opponent =
      TextEditingController(text: _e?.opponent ?? '');
  late final TextEditingController _result =
      TextEditingController(text: _e?.result ?? '');
  late final TextEditingController _minutes =
      TextEditingController(text: '${_e?.minutesPlayed ?? 60}');
  late final TextEditingController _goals =
      TextEditingController(text: '${_e?.goals ?? 0}');
  late final TextEditingController _assists =
      TextEditingController(text: '${_e?.assists ?? 0}');
  late final TextEditingController _wentWell =
      TextEditingController(text: _e?.wentWell ?? '');
  late final TextEditingController _toImprove =
      TextEditingController(text: _e?.toImprove ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: _e?.notes ?? '');

  late int _rating = _e != null && _e.rating >= 1 ? _e.rating : 3;
  bool _saving = false;

  @override
  void dispose() {
    _date.dispose();
    _opponent.dispose();
    _result.dispose();
    _minutes.dispose();
    _goals.dispose();
    _assists.dispose();
    _wentWell.dispose();
    _toImprove.dispose();
    _notes.dispose();
    super.dispose();
  }

  int _num(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final e = _e;
      if (e != null) {
        await Api.updateMatch(
          e.id,
          date: _date.text,
          opponent: _opponent.text,
          result: _result.text,
          minutesPlayed: _num(_minutes),
          goals: _num(_goals),
          assists: _num(_assists),
          rating: _rating,
          wentWell: _wentWell.text,
          toImprove: _toImprove.text,
          notes: _notes.text,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await Api.createMatch(
        date: _date.text,
        opponent: _opponent.text,
        result: _result.text,
        minutesPlayed: _num(_minutes),
        goals: _num(_goals),
        assists: _num(_assists),
        rating: _rating,
        wentWell: _wentWell.text,
        toImprove: _toImprove.text,
        notes: _notes.text,
        plannedEventId: widget.plannedEventId,
        isPlanned: widget.isPlanned,
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
            title: widget.title ?? (_e != null ? 'Edytuj mecz' : 'Zapisz mecz'),
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
                    label: 'Przeciwnik',
                    child: AppTextField(
                      controller: _opponent,
                      hint: 'np. Legia U15',
                    ),
                  ),
                  LabeledField(
                    label: 'Wynik',
                    child: AppTextField(controller: _result, hint: 'np. 3:1'),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: LabeledField(
                          label: 'Minuty',
                          child: AppTextField(
                            controller: _minutes,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: LabeledField(
                          label: 'Gole',
                          child: AppTextField(
                            controller: _goals,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: LabeledField(
                          label: 'Asysty',
                          child: AppTextField(
                            controller: _assists,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ),
                    ],
                  ),
                  LabeledField(
                    label: 'Ocena',
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
                    ),
                  ),
                  LabeledField(
                    label: 'Co poprawić?',
                    child: AppTextField(
                      controller: _toImprove,
                      multiline: true,
                      minLines: 3,
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
                        : _e != null
                            ? 'Zapisz zmiany'
                            : 'Zapisz mecz',
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
