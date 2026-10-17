import 'package:flutter/material.dart';

import '../api.dart';
import '../llm_settings.dart';
import '../services/coach_runtime.dart';
import '../services/user_errors.dart';
import '../config.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'drill_screen.dart';
import 'training_details_screen.dart';

class _Msg {
  const _Msg(this.role, this.content, [this.source = '']);
  final String source;

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
  const CoachScreen({
    super.key,
    required this.selected,
    required this.index,
    this.initialSection = 0,
    this.initialArea,
  });

  final ValueNotifier<int> selected;
  final int index;
  final int initialSection;
  final String? initialArea;

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
  late int _section = widget.initialSection;
  late String? _area = widget.initialArea;
  String? _chatError;
  String? _retryMessage;
  String? _planError;
  String? _addError;

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
    _drills.refetch();
    _plan.refetch();
    _planEvents.refetch();
    widget.selected.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (widget.selected.value == widget.index) {
      _planEvents.refetch();
      _plan.refetch();
      _rebuild();
    }
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
    setState(() {
      _addingWeek = true;
      _addError = null;
    });
    try {
      final n = await Api.addPlanWeekToCalendar(plan);
      await _planEvents.refetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n == 0
                  ? 'Wszystkie treningi z planu są już w kalendarzu.'
                  : 'Dodano do kalendarza: $n ${n == 1
                        ? 'trening'
                        : n < 5
                        ? 'treningi'
                        : 'treningów'}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _addError = 'Nie udało się dodać planu. ${friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _addingWeek = false);
    }
  }

  @override
  void dispose() {
    _input.removeListener(_rebuild);
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
    setState(() {
      _generating = true;
      _planError = null;
    });
    try {
      await Api.generateWeeklyPlan();
      await _plan.refetch();
      // Po wygenerowaniu planu odświeżamy też mapę powiązanych wydarzeń
      // kalendarza, bo plan może teraz odwoływać się do ręcznych treningów.
      await _planEvents.refetch();
    } catch (error) {
      if (mounted) {
        setState(
          () => _planError =
              'Nie udało się utworzyć planu. Dotychczasowy plan jest zachowany. ${friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _send([String? text, bool retry = false]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      if (!retry) _messages.add(_Msg('user', msg));
      _chatError = null;
      _retryMessage = msg;
      _sending = true;
    });
    try {
      final reply = await Api.chat(AppConfig.coachSessionId, msg);
      if (mounted) {
        setState(() {
          _messages.add(
            _Msg('assistant', reply, CoachRuntime.lastReplySource.value),
          );
          if (_messages.length > 5) {
            _messages.removeRange(0, _messages.length - 5);
          }
          _retryMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _chatError = 'Trener chwilowo nie odpowiada. ${friendlyError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      Future<void>.delayed(const Duration(milliseconds: 50), _scrollToEnd);
    }
  }

  Widget _error(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: manrope(size: 14, color: context.c.error)),
        TextButton(onPressed: retry, child: const Text('Spróbuj ponownie')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final plan = _plan.data;
    final canSend = _input.text.trim().isNotEmpty && !_sending;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Twój trener',
                  style: barlow(size: 30, color: c.onSurface),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: CoachRuntime.lastReplySource,
                  builder: (context, source, _) => Text(
                    LlmSettings.forceOffline || !LlmSettings.hasKey
                        ? 'Offline · pytania pozostają na urządzeniu'
                        : source == 'offline'
                        ? 'Ostatnia odpowiedź: offline'
                        : source == 'online'
                        ? 'Ostatnia odpowiedź: online · Gemini'
                        : 'Automatyczny · online z opcją offline',
                    style: manrope(size: 13, color: c.muted),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (i, label) in [
                      (0, 'Plan'),
                      (1, 'Ćwiczenia'),
                      (2, 'Rozmowa'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _section == i,
                        onSelected: (_) => setState(() => _section = i),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey('coach-section-$_section'),
              controller: _section == 2 ? _scroll : null,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_section == 0) ...[
                    const SectionTitle('PLAN TYGODNIA'),
                    if (plan != null)
                      Text(
                        'Od ${plan.weekStart} · ${_sourceLabel(plan.source)}',
                        style: manrope(size: 13, color: c.muted),
                      ),
                    PrimaryButton(
                      label: _generating
                          ? 'Układanie planu…'
                          : plan == null
                          ? 'Ułóż plan'
                          : 'Generuj ponownie',
                      icon: Icons.auto_fix_high,
                      onTap: _generating ? null : _generatePlan,
                    ),
                    if (_planError != null) _error(_planError!, _generatePlan),
                    if (_plan.error != null)
                      _error(
                        'Nie udało się odczytać planu.',
                        () => _plan.refetch(),
                      ),
                    if (_plan.isLoading)
                      const Center(child: Spinner())
                    else if (plan == null && _plan.error == null)
                      _planEmpty(c)
                    else if (plan != null) ...[
                      _planRail(c, plan, todayIso()),
                      const Text(
                        'Dotknij dnia, aby zobaczyć trening lub regenerację.',
                      ),
                      SecondaryButton(
                        label: _addingWeek
                            ? 'Dodawanie…'
                            : 'Dodaj plan do kalendarza',
                        icon: Icons.calendar_month_outlined,
                        onTap: _addingWeek ? null : () => _addWeek(plan),
                      ),
                      if (_addError != null)
                        _error(_addError!, () => _addWeek(plan)),
                    ],
                  ],
                  if (_section == 1) ...[
                    const SectionTitle('GOTOWE TRENINGI'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final area in <String?>[
                          null,
                          'Technika',
                          'Strzał',
                          'Taktyka',
                          'Motoryka',
                          'Mentalność',
                        ])
                          ChoiceChip(
                            label: Text(area ?? 'Wszystkie'),
                            selected: _area == area,
                            onSelected: (_) => setState(() => _area = area),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 8,
                            ),
                          ),
                      ],
                    ),
                    if (_drills.error != null)
                      _error(
                        'Nie udało się odczytać ćwiczeń.',
                        () => _drills.refetch(),
                      ),
                    _drillsRail(c),
                  ],
                  if (_section == 2) ...[
                    const SectionTitle('CZAT Z TRENEREM'),
                    if (_messages.isEmpty) _quickCol(c),
                    ..._messages.map((m) => _bubble(c, m)),
                    if (_sending) _typingBubble(c),
                    if (_chatError != null)
                      _error(_chatError!, () => _send(_retryMessage, true)),
                  ],
                ],
              ),
            ),
          ),
          if (_section == 2) _inputBar(c, canSend),
        ],
      ),
    );
  }

  String _sourceLabel(String source) => source == 'online'
      ? 'Online · Gemini'
      : source == 'offline'
      ? 'Offline'
      : 'Źródło wcześniejszej analizy nieznane';

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
      ev = Api.planEventById(_planEvents.data!, d.calendarEventIds.first);
    } else {
      ev = _planEvents.data?[Api.planKey(d.date, d.title)];
    }
    return AppTapTarget(
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
    final drills = (_drills.data ?? <Drill>[])
        .where(
          (d) =>
              _area == null ||
              d.focus.toLowerCase().contains(_area!.toLowerCase()) ||
              (_area == 'Technika' && d.focus.contains('Prowadzenie')) ||
              (_area == 'Motoryka' && d.focus.contains('Siła')) ||
              (_area == 'Taktyka' && d.focus.contains('Decyzyjność')),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_drills.isLoading) const Center(child: Spinner()),
        if (!_drills.isLoading && _drills.error == null && drills.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Brak ćwiczeń w tym obszarze. Wybierz „Wszystkie”.'),
          ),
        ...drills.map(
          (d) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _drillCard(c, d),
          ),
        ),
      ],
    );
  }

  Widget _drillCard(AppColors c, Drill d) {
    return AppTapTarget(
      behavior: HitTestBehavior.opaque,
      onTap: () => pushModal<void>(context, DrillScreen(drill: d)),
      child: Container(
        width: double.infinity,
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
            return AppTapTarget(
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
                          'TRENER · ${_sourceLabel(m.source)}',
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
          IconButton.filled(
            tooltip: 'Wyślij wiadomość',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: canSend ? () => _send() : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
