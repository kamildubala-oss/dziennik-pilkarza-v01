import 'package:flutter/material.dart';

import '../api.dart';
import '../services/coach_runtime.dart';
import '../llm_settings.dart';
import '../config.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'drill_screen.dart';
import 'training_details_screen.dart';

class _Msg {
  const _Msg(this.role, this.content);

  final String role; // user | assistant
  final String content;
}

const List<String> _quickPrompts = <String>[
  'Co powinienem dzisiaj trenować?',
  'Jak poprawić strzał z dystansu?',
  'Daj mi plan na 20 minut – prowadzenie piłki.',
  'Jak lepiej czytać grę?',
];

/// Zakładka "Trener" (AI).
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, required this.selected, required this.index});

  final ValueNotifier<int> selected;
  final int index;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  late final Resource<List<Drill>> _drills = Resource<List<Drill>>(
    Api.drills,
    _rebuild,
  );
  late final Resource<WeeklyPlan?> _plan = Resource<WeeklyPlan?>(
    Api.getWeeklyPlan,
    _rebuild,
  );
  late final Resource<Map<String, EventItem>> _planEvents =
      Resource<Map<String, EventItem>>(Api.planEvents, _rebuild);
  bool _addingWeek = false;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = <_Msg>[];
  bool _sending = false;
  bool _generating = false;

  static final OutlineInputBorder _plainBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Rad.md),
    borderSide: BorderSide.none,
  );

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _input.addListener(_rebuild);
    CoachRuntime.last.addListener(_rebuild);
    _drills.refetch();
    _plan.refetch();
    _planEvents.refetch();
    widget.selected.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (widget.selected.value == widget.index) _planEvents.refetch();
  }

  Future<void> _openPlanDay(PlanDay d) async {
    // Dla dni powiązanych z zaplanowanymi przez użytkownika wydarzeniami
    // bierzemy dodatkowe wydarzenia tego dnia, żeby wyświetlić je w szczegółach.
    final pe = _planEvents.data;
    EventItem? mainEvent;
    final extraEvents = <EventItem>[];
    if (d.calendarEventIds.isNotEmpty) {
      // Główne wydarzenie dnia planu - pierwsze zapisane ID.
      if (pe != null) {
        mainEvent = Api.planEventById(pe, d.calendarEventIds.first);
        for (final id in d.calendarEventIds.skip(1)) {
          final e = Api.planEventById(pe, id);
          if (e != null) extraEvents.add(e);
        }
      }
    } else if (pe != null) {
      // Starszy plan bez powiązania po ID - fallback po kluczu planKey.
      mainEvent = pe[Api.planKey(d.date, d.title)];
    }
    await pushModal<bool>(
      context,
      TrainingDetailsScreen.forPlanDay(
        d,
        calendarEvent: mainEvent,
        extraEvents: extraEvents,
        onAddToCalendar: () => Api.addPlanDayToCalendar(d),
      ),
    );
    if (mounted) _planEvents.refetch();
  }

  Future<void> _addWeek(WeeklyPlan plan) async {
    if (_addingWeek) return;
    setState(() => _addingWeek = true);
    try {
      final n = await Api.addPlanWeekToCalendar(plan);
      await _planEvents.refetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n == 0
                  ? 'Wszystkie treningi z planu są już w kalendarzu.'
                  : 'Dodano do kalendarza: $n ${n == 1 ? 'trening' : n < 5 ? 'treningi' : 'treningów'}.',
            ),
          ),
        );
      }
    } catch (_) {
      // Błąd zapisu - bez komunikatu.
    } finally {
      if (mounted) setState(() => _addingWeek = false);
    }
  }

  @override
  void dispose() {
    _input.removeListener(_rebuild);
    CoachRuntime.last.removeListener(_rebuild);
    _input.dispose();
    _scroll.dispose();
    widget.selected.removeListener(_onTabChanged);
    _drills.dispose();
    _plan.dispose();
    _planEvents.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _generatePlan() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      await Api.generateWeeklyPlan();
      await _plan.refetch();
      // Po wygenerowaniu planu odświeżamy też mapę powiązanych wydarzeń
      // kalendarza, bo plan może teraz odwoływać się do ręcznych treningów.
      await _planEvents.refetch();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nie udało się utworzyć planu. Spróbuj ponownie.')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add(_Msg('user', msg));
      _sending = true;
    });
    try {
      final reply = await Api.chat(AppConfig.coachSessionId, msg);
      if (mounted) setState(() => _messages.add(_Msg('assistant', reply)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            _Msg(
              'assistant',
              'Trener chwilowo nie odpowiada. Spróbuj ponownie za chwilę. ($e)',
            ),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      Future<void>.delayed(const Duration(milliseconds: 50), _scrollToEnd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top;
    final todayStr = todayIso();
    final plan = _plan.data;
    final canSend = _input.text.trim().isNotEmpty && !_sending;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(Sp.lg, top + Sp.md, Sp.lg, Sp.xxxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(c),
                if (CoachRuntime.last.value?.notice.isNotEmpty ?? false)
                  Padding(padding: const EdgeInsets.only(bottom: Sp.md),
                    child: Text(CoachRuntime.last.value!.notice,
                      style: manrope(size: 13, color: c.onSurface))),

                // ---------- Plan tygodnia ----------
                Padding(
                  padding: const EdgeInsets.only(top: Sp.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: Sp.sm),
                              child: SectionTitle('PLAN TYGODNIA'),
                            ),
                            if (plan != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Od ${plan.weekStart} · ${CoachRuntime.sourceLabel(plan.source)}',
                                  style: manrope(
                                    size: 12,
                                    weight: FontWeight.w600,
                                    color: c.onSurface,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      _planAction(c, plan != null),
                    ],
                  ),
                ),
                if (_plan.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: Sp.sm),
                    child: Center(child: Spinner()),
                  )
                else if (plan == null)
                  _planEmpty(c)
                else ...[
                  _planRail(c, plan, todayStr),
                  Text(
                    'Dotknij dnia, aby zobaczyć ćwiczenia krok po kroku.',
                    style: manrope(size: 12, color: c.muted),
                  ),
                  SecondaryButton(
                    label: _addingWeek
                        ? 'Dodawanie...'
                        : 'Dodaj plan do kalendarza',
                    icon: Icons.calendar_month_outlined,
                    onTap: _addingWeek ? null : () => _addWeek(plan),
                  ),
                ],

                // ---------- Gotowe treningi ----------
                const Padding(
                  padding: EdgeInsets.only(top: Sp.sm),
                  child: SectionTitle('GOTOWE TRENINGI'),
                ),
                _drillsRail(c),

                // ---------- Czat ----------
                const Padding(
                  padding: EdgeInsets.only(top: Sp.lg),
                  child: SectionTitle('CZAT Z TRENEREM'),
                ),
                if (_messages.isEmpty) _quickCol(c),
                ..._messages.map((m) => _bubble(c, m)),
                if (_sending) _typingBubble(c),
              ],
            ),
          ),
        ),
        _inputBar(c, canSend),
      ],
    );
  }

  Widget _hero(AppColors c) {
    final execution = CoachRuntime.last.value;
    final source = execution?.source ?? (LlmSettings.allowNetwork ? '' : 'offline');
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.lg),
      child: SizedBox(
        height: 48 + MediaQuery.textScalerOf(context).scale(150),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Rad.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/coach_field.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    Container(color: c.surfaceSecondary),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x4D0F1115), Color(0xF20F1115)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Sp.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TWÓJ TRENER',
                      style: manrope(
                        size: 11,
                        weight: FontWeight.w800,
                        letterSpacing: 1.8,
                        color: c.brandPrimary,
                      ),
                    ),
                    Text(
                      source == 'online' ? 'Online' : source == 'offline' ? 'Offline' : 'Połączenie jeszcze niesprawdzone',
                      style: manrope(size: 14, weight: FontWeight.w800,
                        color: source == 'online' ? Colors.greenAccent : source == 'offline' ? Colors.redAccent : c.muted),
                    ),
                    if (execution != null) Text(
                      'Ostatni wynik: ${execution.operation} · ${CoachRuntime.dateLabel(execution.createdAt)}',
                      style: manrope(size: 11, color: c.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Trener indywidualny',
                      style: barlow(size: 28, color: c.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Indywidualny trening · Rozwój umiejętności',
                      style: manrope(size: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planAction(AppColors c, bool hasPlan) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _generating ? null : _generatePlan,
      child: Opacity(
        opacity: _generating ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.brandPrimary,
            borderRadius: BorderRadius.circular(Rad.pill),
          ),
          child: _generating
              ? Spinner(color: c.onBrandPrimary)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasPlan ? Icons.refresh : Icons.auto_fix_high,
                      size: 14,
                      color: c.onBrandPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasPlan ? 'Generuj ponownie' : 'Ułóż plan',
                      style: manrope(
                        size: 10,
                        weight: FontWeight.w800,
                        letterSpacing: 1,
                        color: c.onBrandPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _planEmpty(AppColors c) {
    return Container(
      margin: const EdgeInsets.only(top: Sp.sm),
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: withGap([
          Icon(Icons.view_week_outlined, size: 28, color: c.brandPrimary),
          Text(
            'Brak planu na ten tydzień',
            style: manrope(
              size: 15,
              weight: FontWeight.w800,
              color: c.onSurface,
            ),
          ),
          Text(
            'Trener zbuduje spersonalizowany plan 7 dni na podstawie Twojej '
            'pozycji i celu sezonu. Trwa ok. 10-20 s.',
            style: manrope(size: 13, height: 1.4, color: c.muted),
          ),
        ], height: 6),
      ),
    );
  }

  Widget _planRail(AppColors c, WeeklyPlan plan, String todayStr) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: withGap(
            plan.days.map((d) => _planCard(c, d, d.date == todayStr)).toList(),
            width: Sp.sm,
          ),
        ),
      ),
    );
  }

  Widget _planCard(AppColors c, PlanDay d, bool isToday) {
    final onToday = c.onBrandPrimary;
    // Dla dni powiązanych z kalendarzem używamy powiązania po ID,
    // żeby status wykonania nie zrywał rozpoznania.
    EventItem? ev;
    if (d.calendarEventIds.isNotEmpty && _planEvents.data != null) {
      ev = Api.planEventById(
          _planEvents.data!, d.calendarEventIds.first);
    } else {
      ev = _planEvents.data?[Api.planKey(d.date, d.title)];
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPlanDay(d),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: isToday ? c.brandPrimary : c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.md),
          border: Border.all(
            color: isToday ? c.brandPrimary : c.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cut(d.dayName, 3).toUpperCase(),
                  style: manrope(
                    size: 11,
                    weight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: isToday ? onToday : c.muted,
                  ),
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.onBrandPrimary,
                      borderRadius: BorderRadius.circular(Rad.pill),
                    ),
                    child: Text(
                      'DZIŚ',
                      style: manrope(
                        size: 9,
                        weight: FontWeight.w800,
                        letterSpacing: 1,
                        color: c.brandPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              d.focus,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: manrope(
                size: 11,
                weight: FontWeight.w800,
                letterSpacing: 1,
                color: isToday ? onToday : c.brandPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              d.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: manrope(
                size: 14,
                weight: FontWeight.w800,
                color: isToday ? onToday : c.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${d.durationMin} min · ${intensityLabel(d.intensity)}',
              style: manrope(size: 11, color: isToday ? onToday : c.muted),
            ),
            const Spacer(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  ev == null
                      ? Icons.chevron_right
                      : ev.done
                          ? Icons.check_circle
                          : Icons.event_available,
                  size: 14,
                  color: isToday ? onToday : c.brandPrimary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    ev == null
                        ? 'Szczegóły'
                        : ev.done
                            ? 'Wykonany'
                            : 'W kalendarzu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(
                      size: 10,
                      weight: FontWeight.w800,
                      letterSpacing: 1,
                      color: isToday ? onToday : c.brandPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _drillsRail(AppColors c) {
    final drills = _drills.data ?? <Drill>[];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: withGap([
            if (_drills.isLoading) const Spinner(),
            ...drills.map((d) => _drillCard(c, d)),
          ], width: Sp.sm),
        ),
      ),
    );
  }

  Widget _drillCard(AppColors c, Drill d) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => pushModal<void>(context, DrillScreen(drill: d)),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.md),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.source,
              style: manrope(
                size: 10,
                weight: FontWeight.w800,
                letterSpacing: 1.2,
                color: c.brandPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              d.title,
              style: manrope(
                size: 16,
                weight: FontWeight.w800,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${d.durationMin} min · ${intensityLabel(d.intensity)}',
              style: manrope(size: 12, color: c.muted),
            ),
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.brandPrimary,
                borderRadius: BorderRadius.circular(Rad.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 14, color: c.onBrandPrimary),
                  const SizedBox(width: 4),
                  Text(
                    'Start',
                    style: manrope(
                      size: 10,
                      weight: FontWeight.w800,
                      letterSpacing: 1,
                      color: c.onBrandPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCol(AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: withGap(
          _quickPrompts.map((q) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _send(q),
              child: Container(
                padding: const EdgeInsets.all(Sp.md),
                decoration: BoxDecoration(
                  color: c.surfaceSecondary,
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: Border.all(color: c.border, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: c.brandPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q,
                        style: manrope(size: 14, color: c.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          height: Sp.sm,
        ),
      ),
    );
  }

  Widget _bubble(AppColors c, _Msg m) {
    final isUser = m.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.92,
              ),
              child: Container(
                padding: const EdgeInsets.all(Sp.md),
                decoration: BoxDecoration(
                  color: isUser ? c.brandPrimary : c.surfaceSecondary,
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: isUser ? null : Border.all(color: c.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUser)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'TRENER',
                          style: manrope(
                            size: 10,
                            weight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: c.brandPrimary,
                          ),
                        ),
                      ),
                    Text(
                      m.content,
                      style: manrope(
                        size: 14,
                        height: 1.43,
                        color: isUser ? c.onBrandPrimary : c.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _typingBubble(AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: c.surfaceSecondary,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(color: c.border, width: 1),
          ),
          child: const Spinner(),
        ),
      ),
    );
  }

  Widget _inputBar(AppColors c, bool canSend) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              cursorColor: c.brandPrimary,
              style: manrope(size: 14, color: c.onSurface),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceSecondary,
                hintText: 'O co chcesz zapytać Trenera?',
                hintStyle: manrope(size: 14, color: c.muted),
                constraints: const BoxConstraints(minHeight: 44),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Sp.md,
                  vertical: 12,
                ),
                border: _plainBorder,
                enabledBorder: _plainBorder,
                focusedBorder: _plainBorder,
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canSend ? () => _send() : null,
            child: Opacity(
              opacity: canSend ? 1 : 0.5,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.brandPrimary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.send, size: 18, color: c.onBrandPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
