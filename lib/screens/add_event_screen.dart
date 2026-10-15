import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'log_match_screen.dart';
import 'log_session_screen.dart';

const List<String> _types = <String>[
  'training',
  'club_training',
  'match',
  'note',
];

String _typeLabel(String t) {
  if (t == 'training') return 'Trening';
  if (t == 'club_training') return 'Trening klubowy';
  if (t == 'match') return 'Mecz';
  return 'Notatka';
}

/// Modal "Nowe wydarzenie" (kalendarz).
class AddEventScreen extends StatefulWidget {
  const AddEventScreen({super.key, this.initialDate, this.editing, this.initialType = 'training', this.isPlanned = true});

  final String? initialDate;
  /// Typ wybrany przez przycisk otwierający formularz.
  final String initialType;
  /// Kalendarz planuje aktywność, dziennik zapisuje wykonaną.
  final bool isPlanned;

  /// Edytowane wydarzenie bez wpisu w dzienniku (notatka, trening z planu).
  final EventItem? editing;

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  late final EventItem? _e = widget.editing;
  late final TextEditingController _date = TextEditingController(
    text: _e != null ? first10(_e.date) : (widget.initialDate ?? todayIso()),
  );
  late final TextEditingController _time =
      TextEditingController(text: _e?.time ?? '17:30');
  late final TextEditingController _title =
      TextEditingController(text: _e?.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: _e?.description ?? '');

  late String _type = _e?.type ?? widget.initialType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _date.dispose();
    _time.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final e = _e;
      if (e != null) {
        await Api.updateEvent(
          e.id,
          date: _date.text,
          time: _time.text.trim(),
          title: _title.text.trim(),
          description: _description.text.trim(),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await Api.createEvent(
        date: _date.text,
        time: _time.text,
        type: _type,
        title: _title.text,
        description: _description.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nie udało się zapisać: $e")));
        setState(() => _saving = false);
      }
    }
  }

  Widget _typeSelector() {
    return LabeledField(
      label: 'Typ',
      child: ChipsWrap(
        children: [
          for (final t in _types)
            ChipOption(
              label: _typeLabel(t),
              selected: _type == t,
              onTap: () => setState(() => _type = t),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Te same formularze obsługują kalendarz (plan) i dziennik (wykonanie).
    // isPlanned określa, czy zapisujemy plan czy zrealizowaną aktywność.
    if ((_e == null || _e!.sourceId.isEmpty) && (_type == 'training' || _type == 'club_training')) {
      return LogSessionScreen(
        key: ValueKey<String>(_type),
        kind: _type,
        editingEvent: _e,
        initialDate: _date.text,
        title: widget.isPlanned ? 'Zaplanuj trening' : 'Zapisz trening',
        header: _typeSelector(),
        isPlanned: widget.isPlanned,
      );
    }
    if ((_e == null || _e!.sourceId.isEmpty) && _type == 'match') {
      return LogMatchScreen(
        key: const ValueKey<String>('match'),
        editingEvent: _e,
        initialDate: _date.text,
        title: widget.isPlanned ? 'Zaplanuj mecz' : 'Zapisz mecz',
        header: _typeSelector(),
        isPlanned: true,
      );
    }
    final c = context.c;
    final canSave = _title.text.trim().isNotEmpty && !_saving;
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: _e != null ? 'Edytuj wydarzenie' : 'Nowe wydarzenie',
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_e == null) _typeSelector(),
                  const FieldLabel('Data'),
                  DateField(controller: _date),
                  const SizedBox(height: Sp.lg),
                  const FieldLabel('Godzina'),
                  TimeField(controller: _time),
                  const SizedBox(height: Sp.lg),
                  const FieldLabel('Tytuł'),
                  AppTextField(
                    controller: _title,
                    hint: 'np. Trening klubowy, Mecz z Wisłą...',
                  ),
                  const SizedBox(height: Sp.lg),
                  const FieldLabel('Opis / uwagi'),
                  AppTextField(
                    controller: _description,
                    multiline: true,
                    minLines: 4,
                    hint: 'Co trenujemy, nad czym pracujemy...',
                  ),
                  PrimaryButton(
                    label: _saving
                        ? 'Zapisywanie...'
                        : _e != null
                            ? 'Zapisz zmiany'
                            : 'Dodaj',
                    marginTop: Sp.xl,
                    onTap: canSave ? _save : null,
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
