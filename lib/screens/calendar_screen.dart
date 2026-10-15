import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'add_event_screen.dart';
import 'club_training_screen.dart';
import 'log_match_screen.dart';
import 'log_session_screen.dart';
import 'training_details_screen.dart';

/// Zakładka "Kalendarz".
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.selected,
    required this.index,
  });

  final ValueNotifier<int> selected;
  final int index;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final Resource<List<EventItem>> _events = Resource<List<EventItem>>(
    Api.listEvents,
    _rebuild,
  );

  late DateTime _cursor;
  late String _selectedDate;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _cursor = DateTime(now.year, now.month, 1);
    _selectedDate = dateIso(now);
    widget.selected.addListener(_onTabChanged);
    _events.refetch();
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onTabChanged);
    _events.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.selected.value == widget.index) _events.refetch();
  }

  Future<void> _toggle(EventItem e) async {
    if (e.type != 'note') {
      if (!e.done) {
        await _openDetails(e);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ten trening lub mecz jest już zapisany jako wykonany.')));
      }
      return;
    }
    try {
      await Api.toggleEvent(e.id, !e.done);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie udało się zmienić statusu: $error')));
    }
    await _events.refetch();
  }

  Future<void> _delete(EventItem e) async {
    final linked = e.sourceId.isNotEmpty &&
        (e.source == 'trainings' || e.source == 'matches');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć wydarzenie?'),
        content: Text(linked
            ? 'To wydarzenie zostanie trwale usunięte z kalendarza i dziennika. Powiązany trening lub mecz zniknie także ze statystyk i eksportu danych.'
            : 'To wydarzenie zostanie trwale usunięte z kalendarza. Tej operacji nie można cofnąć.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń wszędzie'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Api.deleteEvent(e.id, deleteJournalEntry: true);
      await _events.refetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wydarzenie zostało usunięte.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nie udało się usunąć: $error')),
        );
      }
    }
  }

  /// Edycja: trening/mecz z dziennika - pełny formularz; trening klubowy -
  /// tylko ocena; notatki i treningi z planu - tytuł, data, godzina, opis.
  Future<void> _edit(EventItem e) async {
    Widget? page;
    if (e.type == 'club_training' && e.source == 'club') {
      page = ClubTrainingScreen(event: e);
    } else if (e.source == 'trainings' && e.sourceId.isNotEmpty) {
      final t = await Api.getTraining(e.sourceId);
      if (t != null) page = LogSessionScreen(editing: t, kind: t.kind);
    } else if (e.source == 'matches' && e.sourceId.isNotEmpty) {
      final m = await Api.getMatch(e.sourceId);
      if (m != null) page = LogMatchScreen(editing: m);
    }
    page ??= AddEventScreen(editing: e, initialType: e.type);
    if (!mounted) return;
    await pushModal<bool>(context, page);
    if (mounted) _events.refetch();
  }

  Future<void> _openDetails(EventItem e) async {
    await pushModal<bool>(context, TrainingDetailsScreen.forEvent(e));
    if (mounted) _events.refetch();
  }

  Future<void> _addEvent() async {
    await pushModal<bool>(context, AddEventScreen(initialDate: _selectedDate));
    if (mounted) _events.refetch();
  }

  List<DateTime?> _cells() {
    final first = DateTime(_cursor.year, _cursor.month, 1);
    final total = DateTime(_cursor.year, _cursor.month + 1, 0).day;
    final offset = first.weekday - 1; // poniedziałek = 0
    final cells = <DateTime?>[];
    for (var i = 0; i < offset; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= total; d++) {
      cells.add(DateTime(_cursor.year, _cursor.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top;

    final byDate = <String, List<EventItem>>{};
    for (final e in _events.data ?? <EventItem>[]) {
      byDate.putIfAbsent(first10(e.date), () => <EventItem>[]).add(e);
    }
    final selectedEvents = byDate[_selectedDate] ?? <EventItem>[];
    final cells = _cells();

    return RefreshIndicator(
      color: c.brandPrimary,
      backgroundColor: c.surfaceSecondary,
      onRefresh: () => _events.refetch(),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PLANUJ',
                        style: manrope(
                          size: 11,
                          weight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: c.muted,
                        ),
                      ),
                      Text(
                        'Kalendarz',
                        style: barlow(size: 34, color: c.onSurface),
                      ),
                    ],
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _addEvent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Sp.md,
                        vertical: Sp.sm,
                      ),
                      decoration: BoxDecoration(
                        color: c.brandPrimary,
                        borderRadius: BorderRadius.circular(Rad.pill),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 18, color: c.onBrandPrimary),
                          const SizedBox(width: 4),
                          Text(
                            'Dodaj',
                            style: manrope(
                              size: 13,
                              weight: FontWeight.w800,
                              color: c.onBrandPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Przełącznik miesiąca ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _chevron(
                    c,
                    Icons.chevron_left,
                    () => setState(() {
                      _cursor = DateTime(_cursor.year, _cursor.month - 1, 1);
                    }),
                  ),
                  Text(
                    '${kMonths[_cursor.month - 1]} ${_cursor.year}',
                    style: manrope(
                      size: 16,
                      weight: FontWeight.w700,
                      color: c.onSurface,
                    ),
                  ),
                  _chevron(
                    c,
                    Icons.chevron_right,
                    () => setState(() {
                      _cursor = DateTime(_cursor.year, _cursor.month + 1, 1);
                    }),
                  ),
                ],
              ),
            ),

            // ---------- Etykiety dni tygodnia ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.xs),
              child: Row(
                children: [
                  for (final l in kWeekDays)
                    Expanded(
                      child: Text(
                        l,
                        textAlign: TextAlign.center,
                        style: manrope(
                          size: 11,
                          weight: FontWeight.w800,
                          color: c.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ---------- Siatka dni ----------
            Padding(
              padding: EdgeInsets.zero,
              child: GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                childAspectRatio: 1,
                children: [for (final cell in cells) _dayBox(c, cell, byDate)],
              ),
            ),

            _legend(c),

            // ---------- Wydarzenia wybranego dnia ----------
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedDate,
                    style: manrope(
                      size: 14,
                      weight: FontWeight.w800,
                      color: c.onSurface,
                    ),
                  ),
                  Text(
                    '${selectedEvents.length} wpisów',
                    style: manrope(size: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            if (_events.isLoading)
              const Center(child: Spinner())
            else if (selectedEvents.isEmpty)
              _empty(c)
            else
              ...selectedEvents.map((e) => _eventCard(c, e)),
          ],
        ),
      ),
    );
  }

  Widget _chevron(AppColors c, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: c.onSurface),
      ),
    );
  }

  Widget _dayBox(
    AppColors c,
    DateTime? cell,
    Map<String, List<EventItem>> byDate,
  ) {
    if (cell == null) return const SizedBox.shrink();
    final iso = dateIso(cell);
    final dayEvents = byDate[iso] ?? <EventItem>[];
    final isSelected = iso == _selectedDate;
    final types = <String>{for (final e in dayEvents) e.type};
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedDate = iso),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? c.brandPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${cell.day}',
              style: manrope(
                size: 15,
                weight: FontWeight.w600,
                color: isSelected ? c.onBrandPrimary : c.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: withGap([
                  for (final t in kEventTypes)
                    if (types.contains(t))
                      _dot(
                        eventTypeColor(c, t),
                        ring: isSelected ? c.onBrandPrimary : null,
                      ),
                ], width: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, {Color? ring}) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: ring != null ? Border.all(color: ring, width: 1) : null,
      ),
    );
  }

  /// Legenda kolorów pod kalendarzem.
  Widget _legend(AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm, bottom: Sp.md),
      child: Wrap(
        spacing: Sp.md,
        runSpacing: 6,
        children: [
          for (final t in kEventTypes)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: eventTypeColor(c, t),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  eventTypeLabel(t),
                  style: manrope(size: 11, color: c.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _empty(AppColors c) {
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_today_outlined, size: 32, color: c.muted),
          const SizedBox(height: Sp.sm),
          Text(
            'Brak wydarzeń',
            style: manrope(
              size: 16,
              weight: FontWeight.w700,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Zaplanuj trening lub mecz, aby wiedzieć co robić dalej.',
            textAlign: TextAlign.center,
            style: manrope(size: 13, color: c.muted),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(AppColors c, EventItem e) {
    final Color pillBg;
    final Color pillFg;
    final String pillTxt;
    pillBg = eventTypeColor(c, e.type);
    pillFg = onEventTypeColor(e.type, pillBg);
    pillTxt = e.type == 'match'
        ? 'MECZ'
        : e.type == 'training'
            ? 'TRENING'
            : e.type == 'club_training'
                ? 'KLUBOWY'
                : 'NOTATKA';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _edit(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: Sp.sm),
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.md),
          border: e.isPending
              ? Border.all(
                  color: c.brandPrimary.withValues(alpha: 0.5),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Text(
                pillTxt,
                style: manrope(
                  size: 10,
                  weight: FontWeight.w800,
                  letterSpacing: 1,
                  color: pillFg,
                ),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.done && e.type != 'note' && e.title.toLowerCase().startsWith('planowany trening') ? e.title.replaceFirst(RegExp(r'^Planowany ', caseSensitive: false), '') : e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(
                      size: 15,
                      weight: FontWeight.w700,
                      color: c.onSurface,
                    ),
                  ),
                  if (e.time.isNotEmpty || e.type != 'note') ...[
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (e.time.isNotEmpty) e.time,
                        if (e.type != 'note')
                          (e.done ? 'Wykonany' : first10(e.date).compareTo(todayIso()) < 0 ? 'Nieodnotowany · termin minął' : 'Zaplanowany'),
                      ].join(' · '),
                      style: manrope(size: 12, color: c.muted),
                    ),
                  ],
                  if (e.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      e.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(size: 12, color: c.onSurfaceSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Sp.md),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggle(e),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  e.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 24,
                  color: e.done ? c.brandPrimary : c.muted,
                ),
              ),
            ),
            const SizedBox(width: Sp.xs),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _delete(e),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.delete_outline, size: 20, color: c.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
