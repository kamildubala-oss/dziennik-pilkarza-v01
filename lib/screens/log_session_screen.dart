import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../services/user_errors.dart';
import '../services/planned_training_defaults.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/form_exit_guard.dart';

enum TrainingFormMode { create, plan, editTraining, editPlan, complete }

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
    this.onDateChanged,
    this.title,
    this.header,
    this.kind = 'training',
    this.initialFocuses,
    this.initialDuration,
    this.initialIntensity,
    this.plannedEventId,
    this.editing,
    this.editingEvent,
    this.completingEvent,
    this.isPlanned = false,
  }) : assert(
         editing == null ||
             (editingEvent == null &&
                 completingEvent == null &&
                 !isPlanned &&
                 plannedEventId == null),
       ),
       assert(
         editingEvent == null ||
             (completingEvent == null && plannedEventId == null),
       ),
       assert(
         completingEvent == null || (!isPlanned && plannedEventId == null),
       );

  TrainingFormMode get mode => editing != null
      ? TrainingFormMode.editTraining
      : editingEvent != null
      ? TrainingFormMode.editPlan
      : completingEvent != null || plannedEventId != null
      ? TrainingFormMode.complete
      : isPlanned
      ? TrainingFormMode.plan
      : TrainingFormMode.create;

  /// Edytowany trening (tryb edycji). Gdy null - nowy wpis.
  final Training? editing;
  final EventItem? editingEvent;

  /// Wydarzenie z kalendarza, którego wykonanie właśnie zapisujemy.
  /// Nie jest to edycja planu: zapis tworzy wpis w Dzienniku i łączy go z planem.
  final EventItem? completingEvent;

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
  final ValueChanged<String>? onDateChanged;

  /// Tytuł okna. Domyślnie jak w dzienniku.
  final String? title;

  /// Dodatkowa sekcja na górze formularza (np. wybór typu w kalendarzu).
  final Widget? header;

  @override
  State<LogSessionScreen> createState() => _LogSessionScreenState();
}

class _LogSessionScreenState extends State<LogSessionScreen> {
  late final Training? _e = widget.editing;
  late final PlannedTrainingDefaults? _planned =
      (widget.completingEvent ?? widget.editingEvent) == null
      ? null
      : PlannedTrainingDefaults.fromEvent(
          (widget.completingEvent ?? widget.editingEvent)!,
        );
  late final TextEditingController _date = TextEditingController(
    text: _e != null
        ? first10(_e.date)
        : (_planned?.date ??
              widget.editingEvent?.date ??
              widget.initialDate ??
              todayIso()),
  );
  late final TextEditingController _duration = TextEditingController(
    text:
        '${_e?.durationMin ?? _planned?.durationMin ?? widget.editingEvent?.durationMin ?? widget.initialDuration ?? (widget.kind == 'club_training' ? 90 : 45)}',
  );
  late final TextEditingController _wentWell = TextEditingController(
    text:
        _e?.wentWell ??
        _planned?.wentWell ??
        (widget.editingEvent?.details['went_well'] as String?) ??
        '',
  );
  late final TextEditingController _toImprove = TextEditingController(
    text:
        _e?.toImprove ??
        _planned?.toImprove ??
        (widget.editingEvent?.details['to_improve'] as String?) ??
        '',
  );
  late final TextEditingController _notes = TextEditingController(
    text:
        _e?.notes ??
        _planned?.notes ??
        (widget.editingEvent?.details['notes'] as String?) ??
        '',
  );

  List<String> _initialFocuses() {
    if (_e != null) return _e.focuses;
    final planned = _planned;
    if (planned != null && planned.focuses.isNotEmpty) {
      return planned.focuses;
    }
    return widget.initialFocuses ??
        widget.editingEvent?.focus
            .split(', ')
            .where(_focusOptions.contains)
            .toList() ??
        <String>[];
  }

  late final Set<String> _focus = _initialFocuses()
      .where(_focusOptions.contains)
      .toSet();

  late String _intensity = () {
    final value =
        _e?.intensity ??
        _planned?.intensity ??
        widget.initialIntensity ??
        widget.editingEvent?.intensity;
    return _intensities.contains(value) ? (value ?? 'medium') : 'medium';
  }();
  late int _rating = _e != null && _e.rating >= 1
      ? _e.rating
      : _planned?.rating ??
            (widget.editingEvent?.details['rating'] as int?) ??
            0;
  bool _saving = false;
  final _exitKey = GlobalKey<FormExitGuardState>();
  bool get _isPlan => widget.isPlanned || widget.editingEvent != null;
  List<TextEditingController> get _controllers => [
    _date,
    _duration,
    _wentWell,
    _toImprove,
    _notes,
  ];
  String _fingerprint() => [
    ..._controllers.map((c) => c.text),
    _rating,
    ...(_focus.toList()..sort()),
    _intensity,
  ].join('\u0000');

  @override
  void initState() {
    super.initState();
    _date.addListener(_dateChanged);
  }

  void _dateChanged() => widget.onDateChanged?.call(_date.text);

  @override
  void dispose() {
    _date.removeListener(_dateChanged);
    _date.dispose();
    _duration.dispose();
    _wentWell.dispose();
    _toImprove.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _focus.isEmpty ||
        numberFieldError(_duration.text, 'Czas (min)', 0, 600) != null)
      return;
    final minutes = int.parse(_duration.text.trim());
    setState(() => _saving = true);
    try {
      if (widget.mode == TrainingFormMode.editPlan) {
        final event = widget.editingEvent!;
        final focusList = _focusOptions.where(_focus.contains).toList();
        await Api.updatePlannedActivity(
          event.id,
          date: _date.text,
          title:
              '${widget.kind == 'club_training' ? 'Trening klubowy' : 'Trening'}: ${focusList.join(', ')}',
          description:
              'Czas: ${_duration.text} min · Obszary: ${focusList.join(', ')}',
          details: <String, dynamic>{
            'focus': focusList.join(', '),
            'focuses': focusList,
            'duration_min': minutes,
            'intensity': _intensity,
            'notes': _notes.text,
          },
        );
        if (mounted) await _exitKey.currentState!.finish(true);
        return;
      }
      final e = _e;
      if (widget.mode == TrainingFormMode.editTraining && e != null) {
        await Api.updateTraining(
          e.id,
          date: _date.text,
          durationMin: minutes,
          focuses: _focusOptions.where(_focus.contains).toList(),
          intensity: _intensity,
          rating: _rating,
          wentWell: _wentWell.text,
          toImprove: _toImprove.text,
          notes: _notes.text,
        );
        if (mounted) await _exitKey.currentState!.finish(true);
        return;
      }
      await Api.createTraining(
        date: _date.text,
        durationMin: minutes,
        // Kolejność jak na liście wyboru.
        focuses: _focusOptions.where(_focus.contains).toList(),
        kind: widget.kind,
        plannedEventId: widget.completingEvent?.id ?? widget.plannedEventId,
        isPlanned: widget.isPlanned,
        intensity: _intensity,
        rating: _rating,
        wentWell: _wentWell.text,
        toImprove: _toImprove.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      await _exitKey.currentState!.finish(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FormExitGuard(
      key: _exitKey,
      fingerprint: _fingerprint,
      listenables: _controllers,
      child: Scaffold(
        backgroundColor: c.surface,

        body: Column(
          children: [
            ModalHeader(
              title:
                  widget.title ??
                  (_e != null || widget.editingEvent != null
                      ? 'Edytuj trening'
                      : widget.kind == 'club_training'
                      ? 'Zapisz trening klubowy'
                      : 'Zapisz trening'),
              onClose: () => _exitKey.currentState!.close(),
            ),
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
                        errorText: numberFieldError(
                          _duration.text,
                          'Czas (min)',
                          0,
                          600,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    LabeledField(
                      label: _isPlan
                          ? 'Nad czym chcesz pracować?'
                          : 'Nad czym pracowałeś?',
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
                      label: _isPlan
                          ? 'Planowana intensywność'
                          : 'Intensywność',
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
                    if (!_isPlan) ...[
                      LabeledField(
                        label: 'Ocena treningu',
                        child: RatingStars(
                          rating: _rating,
                          onChanged: (n) => setState(() => _rating = n),
                        ),
                      ),
                      ExpansionTile(
                        title: const Text('Dodaj podsumowanie'),
                        initiallyExpanded:
                            _wentWell.text.isNotEmpty ||
                            _toImprove.text.isNotEmpty,
                        tilePadding: EdgeInsets.zero,
                        children: [
                          LabeledField(
                            label: 'Co było dobrze?',
                            child: AppTextField(
                              controller: _wentWell,
                              multiline: true,
                              minLines: 2,
                              hint: 'np. Lepsze przyjęcie piłki...',
                            ),
                          ),
                          LabeledField(
                            label: 'Co trzeba poprawić?',
                            child: AppTextField(
                              controller: _toImprove,
                              multiline: true,
                              minLines: 2,
                              hint: 'np. Celność strzału z dystansu...',
                            ),
                          ),
                        ],
                      ),
                    ],
                    LabeledField(
                      label: 'Notatki',
                      child: AppTextField(
                        controller: _notes,
                        multiline: true,
                        minLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: PrimaryButton(
                  label: _saving
                      ? 'Zapisywanie...'
                      : _focus.isEmpty
                      ? 'Wybierz obszar'
                      : widget.editingEvent != null || _e != null
                      ? 'Zapisz zmiany'
                      : _isPlan
                      ? 'Zapisz plan'
                      : widget.completingEvent != null
                      ? 'Trening wykonany'
                      : 'Zapisz trening',
                  onTap:
                      _saving ||
                          _focus.isEmpty ||
                          numberFieldError(
                                _duration.text,
                                'Czas (min)',
                                0,
                                600,
                              ) !=
                              null
                      ? null
                      : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
