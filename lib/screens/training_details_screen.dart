import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'activity_editor.dart';
import '../services/user_errors.dart';
import 'log_match_screen.dart';
import 'log_session_screen.dart';

/// Szczegóły treningu do wykonania: dzień planu tygodnia albo zaplanowane
/// wydarzenie z kalendarza (trening, trening klubowy, mecz).
class TrainingDetailsScreen extends StatefulWidget {
  const TrainingDetailsScreen({
    super.key,
    required this.label,
    required this.title,
    required this.focus,
    required this.durationMin,
    required this.intensity,
    required this.description,
    required this.steps,
    required this.tip,
    required this.date,
    this.time = '',
    this.type = 'training',
    this.done = false,
    this.inCalendar = false,
    this.onAddToCalendar,
    this.plannedEventId,
    this.event,
    this.extraEvents = const <EventItem>[],
  });

  /// Pozostałe zaplanowane przez użytkownika aktywności tego samego dnia
  /// (poza głównym) - wyświetlane w szczegółach dnia planu.
  final List<EventItem> extraEvents;

  /// Wydarzenie z kalendarza (jeśli istnieje) - potrzebne do oceny
  /// treningu klubowego.
  final EventItem? event;

  /// Plan tygodnia -> szczegóły dnia planu.
  factory TrainingDetailsScreen.forPlanDay(
    PlanDay d, {
    Key? key,
    EventItem? calendarEvent,
    Future<bool> Function()? onAddToCalendar,
    List<EventItem> extraEvents = const <EventItem>[],
  }) {
    final isUserScheduled =
        calendarEvent != null &&
        (calendarEvent.source.isEmpty ||
            calendarEvent.source == 'trainings' ||
            calendarEvent.source == 'matches') &&
        calendarEvent.plannedSource != 'plan';
    return TrainingDetailsScreen(
      key: key,
      label: '${d.dayName.toUpperCase()} · ${first10(d.date)}',
      title: d.title,
      focus: d.focus,
      durationMin: d.durationMin,
      intensity: d.intensity,
      description: d.description,
      steps: d.steps,
      tip: d.tip,
      date: first10(d.date),
      type: d.focus == 'Mecz'
          ? 'match'
          : d.focus == 'Trening klubowy'
          ? 'club_training'
          : d.isRest
          ? 'rest'
          : 'training',
      done: calendarEvent?.done ?? false,
      inCalendar: calendarEvent != null,
      onAddToCalendar: d.isRest ? null : onAddToCalendar,
      plannedEventId:
          calendarEvent != null &&
              (calendarEvent.isPending || isUserScheduled) &&
              !calendarEvent.done
          ? calendarEvent.id
          : null,
      event: calendarEvent,
      extraEvents: extraEvents,
    );
  }

  /// Zaplanowane wydarzenie z kalendarza.
  factory TrainingDetailsScreen.forEvent(EventItem e, {Key? key}) {
    final kind = e.type == 'club_training'
        ? 'TRENING KLUBOWY'
        : e.type == 'match'
        ? 'MECZ'
        : 'TRENING';
    // Przekaż ID także dla ręcznych (niez planu tygodnia) treningów/meczów,
    // żeby zapis wykonania nie utworzył duplikatu w dzienniku.
    final isUserScheduled =
        e.plannedSource != 'plan' &&
        e.source != 'plan' &&
        !e.done &&
        (e.type == 'training' ||
            e.type == 'club_training' ||
            e.type == 'match');
    return TrainingDetailsScreen(
      key: key,
      label:
          '$kind · ${first10(e.date)}${e.time.isNotEmpty ? ' · ${e.time}' : ''}',
      title: e.title,
      focus: e.focus,
      durationMin: e.durationMin,
      intensity: e.intensity,
      description: e.description,
      steps: e.steps,
      tip: e.tip,
      date: first10(e.date),
      time: e.time,
      type: e.type,
      done: e.done,
      inCalendar: true,
      plannedEventId: (e.isPending || isUserScheduled) ? e.id : null,
      event: e,
    );
  }

  final String label;
  final String title;
  final String focus;
  final int durationMin;
  final String intensity;
  final String description;
  final List<String> steps;
  final String tip;
  final String date;
  final String time;

  /// training | club_training | match | rest
  final String type;
  final bool done;
  final bool inCalendar;
  final Future<bool> Function()? onAddToCalendar;
  final String? plannedEventId;

  @override
  State<TrainingDetailsScreen> createState() => _TrainingDetailsScreenState();
}

const List<String> _trainingFocuses = <String>[
  'Prowadzenie',
  'Strzał',
  'Decyzyjność',
  'Siła',
  'Mentalność',
];

class _TrainingDetailsScreenState extends State<TrainingDetailsScreen> {
  late bool _inCalendar = widget.inCalendar;
  EventItem? _linkedEvent;
  bool _adding = false;
  bool _recovered = false;
  @override
  void initState() {
    super.initState();
    if (widget.type == 'rest') _loadRecovery();
  }

  Future<void> _loadRecovery() async {
    try {
      final dates = await Api.recoveryDays();
      if (mounted) setState(() => _recovered = dates.contains(widget.date));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _confirmRecovery() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await Api.confirmRecovery(widget.date);
      if (mounted) setState(() => _recovered = true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Po dodaniu dnia planu do kalendarza nie korzystamy ze starego
  /// widget.plannedEventId (mógł być null w chwili otwarcia okna).
  Future<EventItem?> _resolveCalendarEvent() async {
    final events = await Api.listEvents();
    final current = _linkedEvent ?? widget.event;
    if (current != null) {
      for (final event in events) {
        if (event.id == current.id) return event;
      }
    }
    if (_inCalendar && widget.onAddToCalendar != null) {
      final byKey = await Api.planEvents();
      return byKey[Api.planKey(widget.date, widget.title)];
    }
    return null;
  }

  Future<void> _add() async {
    final cb = widget.onAddToCalendar;
    if (cb == null || _adding) return;
    setState(() => _adding = true);
    try {
      final added = await cb();
      // Odczytujemy nowy ID wydarzenia, zanim pozwolimy je wykonać.
      final byKey = await Api.planEvents();
      final event = byKey[Api.planKey(widget.date, widget.title)];
      if (!mounted) return;
      if (event != null) {
        setState(() {
          _linkedEvent = event;
          _inCalendar = true;
        });
      } else if (added) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nie udało się powiązać planu z kalendarzem. Spróbuj ponownie.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się dodać treningu do kalendarza.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _log() async {
    final ev = await _resolveCalendarEvent();
    if (!mounted) return;
    if (_inCalendar && widget.onAddToCalendar != null && ev == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nie można znaleźć treningu w kalendarzu. Otwórz ponownie szczegóły.',
          ),
        ),
      );
      return;
    }
    final Widget page;
    if (ev != null) {
      try {
        page = await activityEditor(ev, complete: true);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(error))));
        }
        return;
      }
    } else if (widget.type == 'match') {
      page = LogMatchScreen(
        initialDate: widget.date,
        plannedEventId: widget.plannedEventId,
      );
    } else {
      page = LogSessionScreen(
        initialDate: widget.date,
        kind: widget.type == 'club_training' ? 'club_training' : 'training',
        initialFocuses: <String>[
          if (_trainingFocuses.contains(widget.focus)) widget.focus,
        ],
        initialDuration: widget.durationMin > 0 ? widget.durationMin : null,
        initialIntensity: widget.intensity,
        plannedEventId: widget.plannedEventId,
      );
    }
    if (!mounted) return; // Po asynchronicznym odczycie treningu/meczu.
    final saved = await pushModal<bool>(context, page);
    if (!mounted) return; // Modal mógł zostać zamknięty podczas await.
    if (saved == true) {
      // API zapisuje wykonanie i aktualizuje wydarzenie atomowo pod blokadą.
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = widget;
    final meta = trainingMeta(w.durationMin, w.intensity);
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: w.type == 'match' ? 'Mecz' : 'Trening',
            onClose: () =>
                Navigator.of(context).pop(_inCalendar != w.inCalendar),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    w.label,
                    style: manrope(
                      size: 11,
                      weight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: c.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(w.title, style: barlow(size: 28, color: c.onSurface)),
                  const SizedBox(height: Sp.md),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (w.focus.isNotEmpty)
                        _pill(c, Icons.gps_fixed, w.focus),
                      if (w.durationMin > 0)
                        _pill(c, Icons.timer_outlined, '${w.durationMin} min'),
                      if (w.intensity.isNotEmpty)
                        _pill(
                          c,
                          Icons.local_fire_department,
                          'intensywność ${intensityLabel(w.intensity)}',
                        ),
                      if (w.done) _pill(c, Icons.check_circle, 'wykonany'),
                    ],
                  ),
                  if (w.description.isNotEmpty) ...[
                    const SizedBox(height: Sp.lg),
                    Text(
                      w.description,
                      style: manrope(
                        size: 14,
                        height: 1.43,
                        color: c.onSurfaceSecondary,
                      ),
                    ),
                  ],
                  if (widget.extraEvents.isNotEmpty) ...[
                    const SizedBox(height: Sp.lg),
                    const SectionTitle('INNE ZAPLANOWANE WYDARZENIA TEGO DNIA'),
                    const SizedBox(height: Sp.sm),
                    for (final e in widget.extraEvents) _extraEventTile(c, e),
                  ],
                  if (w.steps.isNotEmpty) ...[
                    const SizedBox(height: Sp.xl),
                    const SectionTitle('CO ROBIĆ - KROK PO KROKU'),
                    const SizedBox(height: Sp.sm),
                    for (var i = 0; i < w.steps.length; i++)
                      _step(c, i + 1, w.steps[i]),
                  ],
                  if (w.tip.isNotEmpty) ...[
                    const SizedBox(height: Sp.md),
                    Container(
                      padding: const EdgeInsets.all(Sp.md),
                      decoration: BoxDecoration(
                        color: c.brandTertiary,
                        borderRadius: BorderRadius.circular(Rad.md),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 20,
                            color: c.onBrandTertiary,
                          ),
                          const SizedBox(width: Sp.sm),
                          Expanded(
                            child: Text(
                              w.tip,
                              style: manrope(
                                size: 13,
                                height: 1.4,
                                weight: FontWeight.w600,
                                color: c.onBrandTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (meta.isNotEmpty && w.steps.isEmpty)
                    const SizedBox(height: Sp.md),
                  if (w.onAddToCalendar != null)
                    SecondaryButton(
                      label: _inCalendar
                          ? 'W kalendarzu'
                          : _adding
                          ? 'Dodawanie...'
                          : 'Dodaj do kalendarza',
                      icon: _inCalendar
                          ? Icons.event_available
                          : Icons.calendar_month_outlined,
                      marginTop: Sp.xl,
                      onTap: _inCalendar || _adding ? null : _add,
                    ),
                  if (w.type == 'rest')
                    PrimaryButton(
                      label: _recovered
                          ? 'Regeneracja potwierdzona'
                          : _adding
                          ? 'Zapisywanie…'
                          : 'Potwierdź regenerację',
                      onTap:
                          _recovered ||
                              _adding ||
                              w.date.compareTo(todayIso()) > 0
                          ? null
                          : _confirmRecovery,
                      icon: Icons.self_improvement,
                    ),
                  if (w.type == 'club_training' && w.event != null)
                    PrimaryButton(
                      label: w.event!.source == 'trainings'
                          ? 'Zobacz podsumowanie'
                          : 'Trening wykonany',
                      icon: Icons.star_outline,
                      marginTop: w.onAddToCalendar != null ? Sp.sm : Sp.xl,
                      onTap: _log,
                    )
                  else if (w.type != 'rest' && !w.done)
                    PrimaryButton(
                      label: w.type == 'match'
                          ? 'Zapisz mecz'
                          : 'Zapisz trening',
                      marginTop: w.onAddToCalendar != null ? Sp.sm : Sp.xl,
                      onTap: _log,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _extraEventTile(AppColors c, EventItem e) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Row(
        children: [
          Icon(
            e.type == 'match'
                ? Icons.sports_soccer
                : e.type == 'club_training'
                ? Icons.groups_outlined
                : Icons.fitness_center,
            size: 20,
            color: c.brandPrimary,
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: manrope(
                    size: 14,
                    weight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                if (e.time.isNotEmpty)
                  Text(e.time, style: manrope(size: 12, color: c.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(AppColors c, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.onSurface),
          const SizedBox(width: 4),
          Text(
            text,
            style: manrope(
              size: 12,
              weight: FontWeight.w600,
              color: c.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(AppColors c, int number, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c.brandPrimary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: manrope(
                size: 13,
                weight: FontWeight.w800,
                color: c.onBrandPrimary,
              ),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              text,
              style: manrope(size: 14, height: 1.43, color: c.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
