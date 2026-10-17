import 'package:flutter/material.dart';

import '../api.dart';
import '../coach_content.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'add_event_screen.dart';
import 'profile_screen.dart';
import 'training_details_screen.dart';
import 'activity_editor.dart';
import '../services/user_errors.dart';

class _Session {
  const _Session({
    required this.id,
    required this.isMatch,
    required this.title,
    required this.date,
    required this.duration,
    required this.rating,
    required this.wentWell,
    required this.toImprove,
  });

  final String id;
  final bool isMatch;
  final String title;
  final String date;
  final int duration;
  final int rating;
  final String wentWell;
  final String toImprove;
}

/// Zakładka "Dziennik".
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({
    super.key,
    required this.selected,
    required this.index,
    required this.onOpenCoach,
  });

  final ValueNotifier<int> selected;
  final int index;
  final VoidCallback onOpenCoach;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late final Resource<List<Training>> _trainings = Resource<List<Training>>(
    Api.listTrainings,
    _rebuild,
  );
  late final Resource<List<MatchEntry>> _matches = Resource<List<MatchEntry>>(
    Api.listMatches,
    _rebuild,
  );
  late final Resource<String> _motivation = Resource<String>(
    Api.motivation,
    _rebuild,
  );
  late final Resource<Progress> _progress = Resource<Progress>(
    Api.progress,
    _rebuild,
  );
  late final Resource<Profile> _profile = Resource<Profile>(
    Api.getProfile,
    _rebuild,
  );
  late final Resource<List<EventItem>> _events = Resource<List<EventItem>>(
    Api.listEvents,
    _rebuild,
  );

  /// Dzień wybrany na pasku tygodnia (domyślnie dziś).
  String _selectedDay = todayIso();
  late final Resource<WeeklyPlan?> _plan = Resource(
    Api.getWeeklyPlan,
    _rebuild,
  );

  /// Aktywności wybranego dnia: najpierw do wykonania, potem wg godziny,
  /// notatki na końcu.
  List<EventItem> _dayEvents(String date) {
    int rank(EventItem e) => e.type == 'note' ? 2 : (e.isPending ? 0 : 1);
    return (_events.data ?? <EventItem>[])
        .where((e) => first10(e.date) == date)
        .toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.time.compareTo(b.time);
      });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_onTabChanged);
    _motivation.refetch();
    _reloadAll();
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onTabChanged);
    _trainings.dispose();
    _matches.dispose();
    _motivation.dispose();
    _progress.dispose();
    _profile.dispose();
    _events.dispose();
    _plan.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.selected.value == widget.index) _reloadAll();
  }

  Future<void> _reloadAll() {
    return Future.wait<void>([
      _trainings.refetch(),
      _matches.refetch(),
      _progress.refetch(),
      _profile.refetch(),
      _events.refetch(),
      _plan.refetch(),
    ]);
  }

  Future<void> _openModal(Widget page) async {
    await pushModal<bool>(context, page);
    if (mounted) _reloadAll();
  }

  List<_Session> _sessions() {
    final list = <_Session>[];
    for (final t in _trainings.data ?? <Training>[]) {
      list.add(
        _Session(
          id: t.id,
          isMatch: false,
          title: t.isClub ? 'Trening klubowy: ${t.focus}' : t.focus,
          date: t.date,
          duration: t.durationMin,
          rating: t.rating,
          wentWell: t.wentWell,
          toImprove: t.toImprove,
        ),
      );
    }
    for (final m in _matches.data ?? <MatchEntry>[]) {
      list.add(
        _Session(
          id: m.id,
          isMatch: true,
          title: 'Mecz vs ${m.opponent}',
          date: m.date,
          duration: m.minutesPlayed,
          rating: m.rating,
          wentWell: m.wentWell,
          toImprove: m.toImprove,
        ),
      );
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top;
    final loading = _trainings.isLoading || _matches.isLoading;
    final sessions = _sessions();
    final profileName = _profile.data?.name ?? '';

    // Tydzień (Pn-Nd) bieżącego tygodnia - daty lokalne.
    final today = DateTime.now();
    final dayOffset = today.weekday - 1;
    final weekDates = List<DateTime>.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day - dayOffset + i),
    );
    final typesByDay = <String, Set<String>>{};
    for (final e in _events.data ?? <EventItem>[]) {
      typesByDay.putIfAbsent(first10(e.date), () => <String>{}).add(e.type);
    }
    final todayStr = dateIso(today);

    return RefreshIndicator(
      color: c.brandPrimary,
      backgroundColor: c.surfaceSecondary,
      onRefresh: () => Future.wait<void>([
        _trainings.refetch(),
        _matches.refetch(),
        _progress.refetch(),
      ]),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Sp.lg, top + Sp.md, Sp.lg, Sp.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- Nagłówek ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profileName.isNotEmpty ? 'CZEŚĆ' : 'CZEŚĆ, PIŁKARZU',
                          style: manrope(
                            size: 11,
                            weight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profileName.isNotEmpty ? profileName : 'Dziennik',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: barlow(size: 34, color: c.onSurface),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sp.md,
                          vertical: Sp.sm,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceSecondary,
                          borderRadius: BorderRadius.circular(Rad.pill),
                          border: Border.all(color: c.border, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              size: 18,
                              color: c.brandSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_progress.data?.streakDays ?? 0} dni',
                              style: manrope(
                                size: 13,
                                weight: FontWeight.w700,
                                color: c.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      AppTapTarget(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openModal(const ProfileScreen()),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: c.surfaceSecondary,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.border, width: 1),
                          ),
                          alignment: Alignment.center,
                          child: profileName.isNotEmpty
                              ? Text(
                                  profileName.substring(0, 1).toUpperCase(),
                                  style: barlow(size: 16, color: c.onSurface),
                                )
                              : Icon(
                                  Icons.person_outline,
                                  size: 22,
                                  color: c.onSurface,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------- Pasek tygodnia ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 7; i++)
                    _dayCell(
                      c,
                      label: kWeekDays[i],
                      date: weekDates[i],
                      isToday: dateIso(weekDates[i]) == todayStr,
                      isSelected: dateIso(weekDates[i]) == _selectedDay,
                      types: typesByDay[dateIso(weekDates[i])] ?? <String>{},
                      onTap: () =>
                          setState(() => _selectedDay = dateIso(weekDates[i])),
                    ),
                ],
              ),
            ),

            // ---------- Hero: Dzisiejszy cel ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              child: _hero(c),
            ),

            // ---------- Szybkie akcje ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              child: Row(
                children: [
                  Expanded(
                    child: _quickCard(
                      c,
                      icon: Icons.directions_run,
                      iconColor: c.brandPrimary,
                      textColor: c.brandPrimary,
                      bg: c.brandTertiary,
                      label: 'Zapisz trening',
                      onTap: () => _openModal(
                        AddEventScreen(
                          initialDate: _selectedDay,
                          initialType: 'training',
                          isPlanned: false,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: _quickCard(
                      c,
                      icon: Icons.sports_soccer,
                      iconColor: c.brandSecondary,
                      textColor: c.onSurfaceSecondary,
                      bg: c.surfaceSecondary,
                      label: 'Zapisz mecz',
                      onTap: () => _openModal(
                        AddEventScreen(
                          initialDate: _selectedDay,
                          initialType: 'match',
                          isPlanned: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Awaria odczytu lokalnych danych ----------
            if (_trainings.error != null ||
                _matches.error != null ||
                _events.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nie można odczytać części dziennika. Dane nie zostały usunięte.',
                      style: manrope(size: 13, color: c.error),
                    ),
                    TextButton(
                      onPressed: () => _reloadAll(),
                      child: const Text('Spróbuj ponownie'),
                    ),
                  ],
                ),
              ),

            // ---------- Ostatnie wpisy ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionTitle('OSTATNIE WPISY'),
                  Text(
                    '${sessions.length} ostatnich',
                    style: manrope(size: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: Spinner()),
              )
            else if (_trainings.error != null || _matches.error != null)
              Text(
                'Odczyt wpisów nie powiódł się — przywróć kopię, jeśli błąd się powtarza.',
                style: manrope(size: 13, color: c.error),
              )
            else if (sessions.isEmpty)
              _empty(c)
            else
              ...sessions.map((s) => _sessionCard(c, s)),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(
    AppColors c, {
    required String label,
    required DateTime date,
    required bool isToday,
    required bool isSelected,
    required Set<String> types,
    required VoidCallback onTap,
  }) {
    return AppTapTarget(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? c.brandPrimary
              : isToday
              ? c.surfaceSecondary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: manrope(
                size: 10,
                weight: FontWeight.w700,
                color: isSelected ? c.onBrandPrimary : c.muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: barlow(
                size: 18,
                color: isSelected
                    ? c.onBrandPrimary
                    : isToday
                    ? c.brandPrimary
                    : c.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in kEventTypes)
                    if (types.contains(t))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: eventTypeColor(c, t),
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: c.onBrandPrimary, width: 1)
                              : null,
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

  /// Tło dobierane do rzeczywistego rodzaju aktywności wybranego dnia.
  /// Priorytet: mecz > trening klubowy > trening indywidualny > odpoczynek.
  /// Notatki nie są aktywnością sportową i nie zmieniają tła.
  String _goalBackground(List<EventItem> events) {
    if (events.any((e) => e.type == 'match')) {
      return 'assets/images/goal_match.webp';
    }
    if (events.any((e) => e.type == 'club_training')) {
      return 'assets/images/goal_team.webp';
    }
    if (events.any((e) => e.type == 'training')) {
      return 'assets/images/goal_individual.webp';
    }
    return 'assets/images/goal_rest.webp';
  }

  Widget _hero(AppColors c) {
    final events = _dayEvents(_selectedDay);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 180),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Rad.lg),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                _goalBackground(events),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stack) =>
                    Container(color: c.surfaceSecondary),
              ),
            ),
            // Ciemny gradient pod treścią: dolna część niemal nieprzezroczysta,
            // dzięki czemu biały tekst pozostaje czytelny na każdym zdjęciu.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: <double>[0.0, 0.38, 0.72, 1.0],
                    colors: <Color>[
                      Color(0x330B1015),
                      Color(0x990B1015),
                      Color(0xE80B1015),
                      Color(0xFA0B1015),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 180 - 2 * Sp.lg),
                child: _heroContent(c, events),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _heroLabel() {
    final today = todayIso();
    if (_selectedDay == today) return 'DZISIEJSZY CEL';
    final d = DateTime.tryParse(_selectedDay);
    if (d == null) return 'PLAN DNIA';
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    if (dateIso(tomorrow) == _selectedDay) return 'JUTRO';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${kPolishDays[d.weekday - 1].toUpperCase()} $dd.$mm';
  }

  bool _canOpen(EventItem e) => e.type != 'note' || e.steps.isNotEmpty;

  Future<void> _openGoal(EventItem e) async {
    if (e.done && e.type != 'note') {
      try {
        final page = await activityEditor(e);
        if (!mounted) return;
        await pushModal<bool>(context, page);
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } else {
      await pushModal<bool>(context, TrainingDetailsScreen.forEvent(e));
    }
    if (mounted) _reloadAll();
  }

  Widget _heroContent(AppColors c, List<EventItem> events) {
    final isToday = _selectedDay == todayIso();
    final isPast = _selectedDay.compareTo(todayIso()) < 0;
    final label = _heroLabel();
    final labelStyle = manrope(
      size: 11,
      weight: FontWeight.w800,
      letterSpacing: 1.8,
      color: c.brandPrimary == const Color(0xFFD4FF26)
          ? c.brandPrimary
          : const Color(0xFFD4FF26),
    );

    final restDays =
        _plan.data?.days
            .where((d) => first10(d.date) == _selectedDay && d.isRest)
            .toList() ??
        <PlanDay>[];
    if (events.where((e) => e.type != 'note').isEmpty && restDays.isNotEmpty) {
      final recovered =
          _progress.data?.confirmedRecoveryDays.contains(_selectedDay) ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 8),
          Text(
            recovered
                ? 'Regeneracja potwierdzona'
                : 'Dziś zadbaj o regenerację',
            style: manrope(
              size: 22,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Odpoczynek jest częścią Twojego planu. Zobacz wskazówki na ten dzień.',
            style: manrope(size: 14, color: Colors.white),
          ),
          const SizedBox(height: 12),
          _heroButton(
            c,
            label: 'Zobacz regenerację',
            icon: Icons.self_improvement,
            onTap: () async {
              await pushModal<bool>(
                context,
                TrainingDetailsScreen.forPlanDay(restDays.first),
              );
              if (mounted) _reloadAll();
            },
          ),
        ],
      );
    }
    if (events.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 6),
          Text(
            isPast
                ? 'Brak aktywności tego dnia'
                : 'Brak zaplanowanej aktywności',
            style: manrope(
              size: 20,
              weight: FontWeight.w700,
              height: 1.3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isToday
                ? (_motivation.data ??
                      'Zaplanuj aktywność lub odpoczynek zgodnie ze swoim tygodniem.')
                : isPast
                ? 'Nie zapisano treningu ani meczu.'
                : 'Dodaj trening w kalendarzu albo z planu tygodnia u trenera.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: manrope(
              size: 13,
              height: 1.4,
              color: const Color(0xFFD0D4DA),
            ),
          ),
          const SizedBox(height: Sp.md),
          _heroButton(
            c,
            label: 'Zaplanuj aktywność',
            icon: Icons.arrow_forward,
            onTap: () => _openModal(
              AddEventScreen(
                initialDate: _selectedDay,
                initialType: 'training',
              ),
            ),
          ),
        ],
      );
    }

    final shown = events.take(3).toList();
    final first = shown.first;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          events.length > 1 ? '$label · ${events.length} AKTYWNOŚCI' : label,
          style: labelStyle,
        ),
        const SizedBox(height: Sp.sm),
        for (final e in shown) _heroRow(c, e, big: e == first),
        if (events.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+ ${events.length - shown.length} więcej w kalendarzu',
              style: manrope(size: 12, color: const Color(0xFFD0D4DA)),
            ),
          ),
        if (_canOpen(first)) ...[
          const SizedBox(height: Sp.md),
          _heroButton(
            c,
            label: first.done ? 'Zobacz podsumowanie' : 'Zobacz trening',
            icon: Icons.arrow_forward,
            onTap: () => _openGoal(first),
          ),
        ],
        if (!first.done &&
            first.type != 'note' &&
            _selectedDay.compareTo(todayIso()) <= 0) ...[
          const SizedBox(height: 8),
          _heroButton(
            c,
            label: isPast
                ? 'Uzupełnij wykonanie'
                : first.type == 'match'
                ? 'Mecz wykonany'
                : 'Trening wykonany',
            icon: Icons.check,
            onTap: () async {
              try {
                final page = await activityEditor(first, complete: true);
                if (!mounted) return;
                await pushModal<bool>(context, page);
                if (mounted) _reloadAll();
              } catch (error) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _heroRow(AppColors c, EventItem e, {required bool big}) {
    final meta = <String>[
      eventTypeLabel(e.type),
      if (e.time.isNotEmpty) 'godz. ${e.time}',
      if (e.durationMin > 0) '${e.durationMin} min',
      if (e.intensity.isNotEmpty) 'intensywność ${intensityLabel(e.intensity)}',
      if (e.done && e.type != 'note') 'wykonany',
    ].join(' · ');
    final open = _canOpen(e);
    return AppTapTarget(
      behavior: HitTestBehavior.opaque,
      onTap: open ? () => _openGoal(e) : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: EdgeInsets.only(top: big ? 7 : 4, right: Sp.sm),
              decoration: BoxDecoration(
                color: eventTypeColor(c, e.type),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: big ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(
                      size: big ? 20 : 14,
                      weight: FontWeight.w700,
                      height: 1.25,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(size: 12, color: const Color(0xFFD0D4DA)),
                  ),
                ],
              ),
            ),
            if (open && !big)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFD0D4DA),
              ),
          ],
        ),
      ),
    );
  }

  Widget _heroButton(
    AppColors c, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFD4FF26),
        foregroundColor: Colors.black,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center),
    );
  }

  Widget _quickCard(
    AppColors c, {
    required IconData icon,
    required Color iconColor,
    required Color textColor,
    required Color bg,
    required String label,
    required VoidCallback onTap,
  }) {
    return AppTapTarget(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(
                  size: 14,
                  weight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(AppColors c) {
    return Container(
      margin: const EdgeInsets.only(top: Sp.sm),
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 36, color: c.muted),
          const SizedBox(height: Sp.sm),
          Text(
            'Pusto w dzienniku',
            style: manrope(
              size: 16,
              weight: FontWeight.w700,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Zapisz pierwszy trening lub mecz, a trener zacznie Ci pomagać.',
            textAlign: TextAlign.center,
            style: manrope(size: 13, height: 1.4, color: c.muted),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(AppColors c, _Session s) {
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: s.isMatch ? c.brandSecondary : c.brandTertiary,
              borderRadius: BorderRadius.circular(Rad.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              s.isMatch ? Icons.sports_soccer : Icons.directions_run,
              size: 18,
              color: s.isMatch ? c.onBrandSecondary : c.brandPrimary,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(
                    size: 15,
                    weight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${first10(s.date)} · ${s.duration} min · ${s.rating > 0 ? 'ocena ${s.rating}/5' : 'bez oceny'}',
                  style: manrope(size: 12, color: c.muted),
                ),
                if (s.wentWell.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+ ${s.wentWell}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(size: 12, color: c.brandPrimary),
                  ),
                ],
                if (s.toImprove.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '! ${s.toImprove}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(size: 12, color: c.warning),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
