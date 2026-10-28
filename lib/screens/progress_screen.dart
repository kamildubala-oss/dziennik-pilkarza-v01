import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../local_db.dart';
import '../services/progress_report.dart';
import '../services/progress_calculator.dart';
import '../services/skill_radar_service.dart';
import '../services/achievement_service.dart';
import 'activity_editor.dart';
import 'drill_screen.dart';
import '../services/coach_runtime.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/period_selector.dart';
import '../widgets/exercise_button.dart';

/// Zakładka "Postęp".
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    super.key,
    required this.selected,
    required this.index,
  });

  final ValueNotifier<int> selected;
  final int index;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final Resource<Progress> _progress = Resource<Progress>(
    Api.progress,
    _rebuild,
  );
  late final Resource<WeakSpotsPayload?> _weak = Resource<WeakSpotsPayload?>(
    Api.getWeakSpots,
    _rebuild,
  );

  int _period = 30;
  late final Resource<ProgressReport> _report = Resource<ProgressReport>(
    () => ProgressReport.load(_period), _rebuild);
  Map<String, String> _earned = {};
  String _fingerprint = '';
  Future<void> _refresh() async {
    await Future.wait([_progress.refetch(), _report.refetch(), _weak.refetch()]);
    try {
      final trainings = await LocalDb.list('trainings');
      final matches = await LocalDb.list('matches');
      final earned = AchievementService.earnedDates(await LocalDb.exportAll(), trainings, matches);
      final fingerprint = ObservationSample.fingerprint(ObservationSample.latest(trainings, matches));
      if (mounted) setState(() { _earned = earned; _fingerprint = fingerprint; });
    } catch (_) { /* Główny Resource pokazuje błąd odczytu. */ }
  }
  bool _analyzing = false;
  bool _badgesExpanded = false;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_onTabChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onTabChanged);
    _report.dispose();
    _progress.dispose();
    _weak.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.selected.value == widget.index) _refresh();
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    setState(() => _analyzing = true);
    try {
      await Api.analyzeWeakSpots();
      await _weak.refetch();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nie udało się utworzyć analizy. Spróbuj ponownie.')));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top;
    final stats = _report.data?.stats;

    return RefreshIndicator(
      color: c.brandPrimary,
      backgroundColor: c.surfaceSecondary,
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Sp.lg, top + Sp.md, Sp.lg, Sp.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'TWÓJ POSTĘP',
              style: manrope(
                size: 11,
                weight: FontWeight.w700,
                letterSpacing: 1.5,
                color: c.muted,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              child: Text(
                'Statystyki',
                style: barlow(size: 34, color: c.onSurface),
              ),
            ),
            PeriodSelector(value: _period,
              onChanged: _report.isLoading || _report.isRefetching ? null : (value) async {
                setState(() => _period = value);
                await _report.refetch();
              }),
            if (_report.isRefetching) const LinearProgressIndicator(),
            if (_report.data != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${_report.data!.rangeLabel}${_period == -1 ? ' · sezon od 1 lipca' : ''}',
                style: manrope(size: 11, color: c.muted))),
            if (_progress.isLoading || _report.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: Spinner()),
              )
            else if (_progress.error != null || _report.error != null)
              _weakEmpty(c, title: 'Nie udało się wczytać statystyk',
                sub: 'Pociągnij ekran w dół lub wybierz „Spróbuj ponownie”.'),
            if (_progress.error != null || _report.error != null)
              TextButton(onPressed: _refresh, child: const Text('Spróbuj ponownie'))
            else if (!_progress.isLoading && !_report.isLoading)
              ..._content(c, stats),
          ],
        ),
      ),
    );
  }

  Widget _section(String text, {double top = Sp.md, double bottom = Sp.sm}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: SectionTitle(text),
    );
  }

  List<Widget> _content(AppColors c, Progress? stats) {
    final week = _progress.data?.weekSessions ?? <int>[0, 0, 0, 0, 0, 0, 0];
    final maxV = math.max(1, week.isEmpty ? 1 : week.reduce(math.max));
    final avg = stats?.avgRating;
    final ratedCount = stats?.ratedEntriesCount ?? 0;

    // Etykiety dni: ostatnie 7 dni kończące się dzisiaj.
    final now = DateTime.now();
    final labels = List<String>.generate(7, (i) {
      final d = DateTime(now.year, now.month, now.day - (6 - i));
      return kWeekDays[d.weekday - 1];
    });

    return <Widget>[
      // ---------- Streak + ocena ----------
      Padding(
        padding: const EdgeInsets.only(bottom: Sp.lg),
        child: IntrinsicHeight(child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _heroCell(
                c,
                bg: c.brandPrimary,
                icon: Icons.local_fire_department,
                iconColor: c.onBrandPrimary,
                value: '${_progress.data?.streakDays ?? 0}',
                valueColor: c.onBrandPrimary,
                label: 'DNI Z RZĘDU',
                subtitle: 'Bieżąca seria · cała historia',
                labelColor: c.onBrandPrimary,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _heroCell(
                c,
                bg: c.surfaceSecondary,
                icon: Icons.star,
                iconColor: c.brandSecondary,
                value: avg != null && avg > 0 ? avg.toStringAsFixed(1) : '—',
                valueColor: c.onSurface,
                label: 'SAMOOCENA TRENINGÓW I MECZÓW',
                subtitle: ratedCount == 0
                    ? 'Ocena jest opcjonalna'
                    : 'Na podstawie $ratedCount ${ratedCount == 1 ? 'oceny' : 'ocen'}',
                labelColor: c.muted,
              ),
            ),
          ],
        )),
      ),

      // ---------- Ostatnie 7 dni ----------
      _section('OSTATNIE 7 DNI'),
      Padding(padding: const EdgeInsets.only(bottom: Sp.sm),
        child: Text('Liczba aktywności', style: manrope(size: 12, color: c.muted))),
      Container(
        height: 160,
        padding: const EdgeInsets.all(Sp.sm),
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < week.length && i < 7; i++)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        key: ValueKey('week-bar-$i'),
                        width: 18,
                        height: week[i] > 0 ? (week[i] / maxV) * 100 : 0,
                        child: i < (_progress.data?.weekSessionTypes.length ?? 0) && week[i] > 0
                            ? Column(
                                children: [
                                  for (final type in kEventTypes.where((t) =>
                                      (_progress.data!.weekSessionTypes[i][t] ?? 0) > 0))
                                    Expanded(
                                      flex: _progress.data!.weekSessionTypes[i][type]!,
                                      child: ColoredBox(
                                        color: eventTypeColor(c, type),
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                ],
                              )
                            : ColoredBox(
                                color: week[i] > 0
                                    ? eventTypeColor(c, 'training')
                                    : c.surfaceTertiary,
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      style: manrope(
                        size: 10,
                        weight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${week[i]}',
                      style: manrope(
                        size: 11,
                        weight: FontWeight.w700,
                        color: c.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),

      // ---------- Metryki ----------
      _section('METRYKI'),
      LayoutBuilder(
        builder: (context, constraints) {
          final w = (constraints.maxWidth - 2 * Sp.sm) / 3;
          final labels = ['Treningi indywidualne', 'Treningi klubowe', 'Mecze', 'Minuty', 'Gole', 'Asysty'];
          final values = ['${stats?.totalIndividualTrainings ?? 0}', '${stats?.totalClubTrainings ?? 0}',
            '${stats?.totalMatches ?? 0}', '${stats?.totalMinutes ?? 0}',
            '${stats?.totalGoals ?? 0}', '${stats?.totalAssists ?? 0}'];
          double measure(String text, TextStyle style) {
            final painter = TextPainter(text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
              textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
              ..layout(maxWidth: w - 2 * Sp.md);
            final height = painter.height;
            painter.dispose();
            return height;
          }
          final labelHeight = labels.map((text) => measure(text,
            manrope(size: 10, weight: FontWeight.w700, letterSpacing: 1))).reduce(math.max);
          final valueHeight = values.map((text) => measure(text, barlow(size: 22))).reduce(math.max);
          final height = (2 * Sp.md + 18 + 8 + labelHeight + valueHeight).ceilToDouble();
          return Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              _metric(c, w, height, Icons.directions_run, 'Treningi indywidualne',
                '${stats?.totalIndividualTrainings ?? 0}'),
              _metric(c, w, height, Icons.groups, 'Treningi klubowe',
                '${stats?.totalClubTrainings ?? 0}'),
              _metric(c, w, height, Icons.sports_soccer, 'Mecze', '${stats?.totalMatches ?? 0}'),
              _metric(c, w, height, Icons.timer, 'Minuty', '${stats?.totalMinutes ?? 0}'),
              _metric(c, w, height, Icons.gps_fixed, 'Gole', '${stats?.totalGoals ?? 0}'),
              _metric(c, w, height, Icons.handshake, 'Asysty', '${stats?.totalAssists ?? 0}'),
            ],
          );
        },
      ),

      ..._reportSections(c),

      // ---------- Słabe punkty (AI) ----------
      ..._weakSection(c),

      // ---------- Odznaki: realizacja i regeneracja zamiast treningu codziennie ----------
      _section('ODZNAKI'),
      Text('Cała historia', style: manrope(size: 11, color: c.muted)),
      InkWell(
        borderRadius: BorderRadius.circular(Rad.md),
        onTap: () => setState(() => _badgesExpanded = !_badgesExpanded),
        child: Row(children: [
          Expanded(child: _badge(c,
            active: (_progress.data?.latestBadgeTitle ?? '').isNotEmpty,
            icon: Icons.emoji_events,
            title: (_progress.data?.latestBadgeTitle ?? '').isNotEmpty
              ? _progress.data!.latestBadgeTitle : 'Twoja pierwsza odznaka czeka',
            sub: _badgesExpanded ? 'Zwiń odznaki' : 'Dotknij, aby zobaczyć wszystkie odznaki')),
          Icon(_badgesExpanded ? Icons.expand_less : Icons.expand_more, color: c.muted),
        ]),
      ),
      if (_badgesExpanded) Column(
        children: withGap([
          _badge(c, active: (_progress.data?.totalTrainings ?? 0) >= 1,
              icon: Icons.sports_score, title: 'Pierwszy trening',
              sub: 'Pierwszy zapisany trening.'),
          _badge(c, active: (_progress.data?.totalTrainings ?? 0) >= 10,
              icon: Icons.directions_run, title: '10 treningów',
              sub: 'Rozwijasz systematyczność.'),
          _badge(c, active: (_progress.data?.totalTrainings ?? 0) >= 30,
              icon: Icons.fitness_center, title: '30 treningów',
              sub: 'Treningowa wytrwałość.'),
          _badge(c, active: (_progress.data?.totalTrainings ?? 0) >= 100,
              icon: Icons.military_tech, title: '100 treningów',
              sub: 'Długa droga, wielki postęp.'),
          _badge(c, active: (_progress.data?.totalMatches ?? 0) >= 1,
              icon: Icons.sports_soccer, title: 'Pierwszy mecz',
              sub: 'Pierwszy zapisany występ.'),
          _badge(c, active: (_progress.data?.totalMatches ?? 0) >= 10,
              icon: Icons.shield, title: '10 meczów',
              sub: 'Dziesięć sportowych doświadczeń.'),
          _badge(c, active: (_progress.data?.totalMinutes ?? 0) >= 300,
              icon: Icons.timer, title: '5 godzin aktywności',
              sub: '300 minut treningów i meczów.'),
          _badge(c, active: (_progress.data?.totalMinutes ?? 0) >= 1200,
              icon: Icons.access_time_filled, title: '20 godzin aktywności',
              sub: '1200 minut systematycznej pracy.'),
          _badge(c, active: (_progress.data?.totalGoals ?? 0) >= 1,
              icon: Icons.sports_score, title: 'Pierwszy gol',
              sub: 'Pierwsza bramka w dzienniku.'),
          _badge(c, active: (_progress.data?.totalGoals ?? 0) >= 5,
              icon: Icons.emoji_events, title: 'Snajper',
              sub: '5 bramek łącznie.'),
          _badge(c, active: (_progress.data?.bestMatchGoals ?? 0) >= 3,
              icon: Icons.stars, title: 'Hat-trick',
              sub: '3 gole w jednym meczu.'),
          _badge(c, active: (_progress.data?.totalAssists ?? 0) >= 1,
              icon: Icons.handshake, title: 'Pierwsza asysta',
              sub: 'Pomoc w zdobyciu bramki.'),
          _badge(c, active: (_progress.data?.totalAssists ?? 0) >= 10,
              icon: Icons.group, title: '10 asyst',
              sub: 'Grasz zespołowo.'),
          _badge(c, active: _progress.data?.hasTopRating == true,
              icon: Icons.star, title: 'Ocena 5/5',
              sub: 'Pierwsza najwyższa ocena.'),
          _badge(c, active: _progress.data?.completedPlanWeek == true,
              icon: Icons.self_improvement, title: 'Tydzień według planu',
              sub: 'Realizacja aktywności i zaplanowanej regeneracji.'),
        ], height: Sp.sm),
      ),
    ];
  }

  List<Widget> _weakSection(AppColors c) {
    final data = _weak.data;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: Sp.lg, bottom: Sp.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('NAD CZYM WARTO POPRACOWAĆ'),
                  if (data != null && data.notice.isNotEmpty)
                    Text(data.notice, style: manrope(size: 12, color: c.muted)),
                  if (data != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${CoachRuntime.sourceLabel(data.source)}\n'
                        'Utworzono: ${CoachRuntime.dateLabel(data.generatedAt)} · '
                        '${data.noteCount} obserwacji'
                        '${data.rangeStart.isEmpty ? '' : '\nZakres: ${data.rangeStart} – ${data.rangeEnd}'}',
                        style: manrope(size: 11, color: c.muted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _analyzing ? null : _analyze,
              child: Opacity(
                opacity: _analyzing ? 0.6 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.brandPrimary,
                    borderRadius: BorderRadius.circular(Rad.pill),
                  ),
                  child: _analyzing
                      ? Spinner(color: c.onBrandPrimary)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              data != null
                                  ? Icons.refresh
                                  : Icons.auto_fix_high,
                              size: 14,
                              color: c.onBrandPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              data != null ? 'Odśwież' : 'Analizuj',
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
            ),
          ],
        ),
      ),
      if (data != null && (data.sampleFingerprint.isEmpty || data.sampleFingerprint != _fingerprint))
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(
          'Obserwacje zmieniły się od ostatniej analizy. Odśwież wskazówki.',
          style: manrope(size: 12, color: c.warning))),
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(
        'Analiza obejmuje maksymalnie 50 najnowszych obserwacji z całej historii.',
        style: manrope(size: 11, color: c.muted))),
      if (_weak.isLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.md),
          child: Center(child: Spinner()),
        )
      else if (_weak.error != null)
        _weakEmpty(c, title: 'Nie udało się wczytać analizy', sub: 'Odśwież ekran, aby spróbować ponownie.')
      else if (data == null)
        _weakEmpty(
          c,
          icon: Icons.auto_fix_high,
          title: 'Brak analizy',
          sub: 'Dodaj obserwacje po treningach, aby otrzymać wskazówki',
        )
      else if (data.weakSpots.isEmpty || data.noteCount < 2)
        _weakEmpty(
          c,
          title: data.noteCount == 0 ? 'Brak obserwacji' : 'Za mało powtarzających się obserwacji',
          sub: 'Zapisuj konkretne obserwacje w polu „Co trzeba poprawić?”. Pojedynczy wpis nie oznacza stałej trudności.',
        )
      else
        ...data.weakSpots.map((w) => _weakCard(c, w)),
    ];
  }

  Widget _weakEmpty(
    AppColors c, {
    IconData? icon,
    required String title,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: withGap([
          if (icon != null) Icon(icon, size: 24, color: c.brandPrimary),
          Text(
            title,
            style: manrope(
              size: 15,
              weight: FontWeight.w800,
              color: c.onSurface,
            ),
          ),
          Text(sub, style: manrope(size: 13, height: 1.4, color: c.muted)),
        ], height: 6),
      ),
    );
  }

  Widget _weakCard(AppColors c, WeakSpot w) {
    final Color prio;
    if (w.priority == 'high') {
      prio = c.brandSecondary;
    } else if (w.priority == 'medium') {
      prio = c.warning;
    } else {
      prio = c.surfaceTertiary;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: prio,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    w.area.toUpperCase(),
                    style: manrope(
                      size: 10,
                      weight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: c.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(w.insight, style: manrope(size: 14, height: 1.36, color: c.onSurface)),
                  Padding(padding: const EdgeInsets.only(top: 8), child: ExerciseButton(
                    onTap: () => _showExercises(w.area), label: 'Zobacz ćwiczenia')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCell(
    AppColors c, {
    required Color bg,
    required IconData icon,
    required Color iconColor,
    required String value,
    required Color valueColor,
    required String label,
    required Color labelColor,
    String? subtitle,
  }) {
    return Container(
      key: ValueKey('hero-$label'),
      constraints: const BoxConstraints(minHeight: 110),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: iconColor),
          Text(value, style: barlow(size: 36, color: valueColor)),
          Text(
            label,
            style: manrope(
              size: 10,
              weight: FontWeight.w800,
              letterSpacing: 1.2,
              color: labelColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: manrope(size: 11, color: labelColor)),
          ],
        ],
      ),
    );
  }

  List<Widget> _reportSections(AppColors c) {
    final report = _report.data;
    if (report == null) return [];
    final previous = report.previous;
    final maxArea = math.max(1, report.areas.values.fold<int>(0, math.max));
    String delta(int value, int before) => '${value - before >= 0 ? '+' : ''}${value - before}';
    String average(String source) {
      final ratings = report.entries.where((e) => e['_source'] == source)
        .map((e) => ProgressCalculator.asInt(e['rating'])).where((r) => r >= 1 && r <= 5).toList();
      return ratings.isEmpty ? 'brak ocen' : '${(ratings.reduce((a, b) => a + b) / ratings.length).toStringAsFixed(1)} (${ratings.length} ocen)';
    }
    return [
      TextButton.icon(onPressed: () => _showEntries('Regeneracje'), icon: const Icon(Icons.spa_outlined),
        label: Text('Regeneracje: ${report.entries.where((e) => e['kind'] == 'recovery').length}')),
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(
        'Samoocena: treningi ${average('trainings')} · mecze ${average('matches')}. '
        'To Twoje odczucia, nie pomiar umiejętności.', style: manrope(size: 11, color: c.muted))),
      if (previous != null) ...[
        _section('PORÓWNANIE OKRESÓW'),
        Text('W porównaniu z poprzednim okresem tej samej długości: '
          '${delta(report.stats.totalTrainings + report.stats.totalMatches, previous.totalTrainings + previous.totalMatches)} aktywności, '
          '${delta(report.stats.totalMinutes, previous.totalMinutes)} min. '
          'Większa aktywność nie oznacza automatycznie lepszego rozwoju.',
          style: manrope(size: 12, color: c.muted)),
      ],
      _section('AKTYWNOŚĆ W OBSZARACH'),
      Text('Liczba treningów z zaznaczonym obszarem. Jeden trening może obejmować kilka obszarów. '
        'Nie jest to ocena umiejętności ani podział minut.', style: manrope(size: 11, color: c.muted)),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(color: c.surfaceSecondary, borderRadius: BorderRadius.circular(Rad.md)),
        child: Column(children: [for (final area in report.areas.entries)
          Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: InkWell(
            onTap: () => _showEntries(area.key, area: area.key),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Expanded(child: Text(area.key, style: manrope(size: 12, color: c.onSurface))),
                Text('${area.value}', style: manrope(size: 12, color: c.onSurface))]),
              const SizedBox(height: 3),
              LinearProgressIndicator(value: area.value / maxArea, color: c.brandPrimary,
                backgroundColor: c.surfaceTertiary, semanticsLabel: '${area.key}: ${area.value} treningów'),
            ]))),
        ])),
      _section('REALIZACJA PLANU TYGODNIA'),
      Text(report.planDays == 0 ? 'Brak zakończonych dni planu w wybranym okresie.'
        : '${report.fulfilledDays}/${report.planDays} zakończonych dni zgodnie z planem.',
        style: manrope(size: 14, color: c.onSurface)),
      Text('Dzień treningowy: zapisano aktywność. Regeneracja: brak zapisanej aktywności. '
        'Dzisiejszy i przyszłe dni nie są oceniane. Zgodność dnia nie potwierdza wykonania wszystkich ćwiczeń.',
        style: manrope(size: 11, color: c.muted)),
      _section('CO IDZIE DOBRZE'),
      if (report.strengths.isEmpty)
        Text('Dodaj obserwacje w polu „Co było dobrze?”, aby wracać do swoich sukcesów.',
          style: manrope(size: 12, color: c.muted))
      else ...[
        Text('Twoje ostatnie obserwacje z wybranego okresu', style: manrope(size: 11, color: c.muted)),
        for (final entry in report.strengths.take(3)) ListTile(contentPadding: EdgeInsets.zero,
          title: Text((entry['went_well'] ?? '').toString(), style: manrope(size: 13, color: c.onSurface)),
          subtitle: Text(first10((entry['date'] ?? '').toString())),
          trailing: const Icon(Icons.chevron_right), onTap: () => _editEntry(entry)),
      ],
    ];
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    try {
      final page = await activityEditor(EventItem.fromJson({...entry,
        'source': entry['_source'], 'source_id': entry['id'], 'done': true}));
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć wpisu. Odśwież ekran.')));
    }
  }

  Future<void> _showEntries(String title, {String? area}) async {
    final entries = (_report.data?.entries ?? <Map<String, dynamic>>[]).where((e) {
      if (area != null) return e['_source'] == 'trainings' && SkillRadarService.focuses(e).contains(area);
      if (title == 'Treningi indywidualne') return e['_source'] == 'trainings' && e['kind'] != 'club_training' && e['kind'] != 'recovery';
      if (title == 'Treningi klubowe') return e['_source'] == 'trainings' && e['kind'] == 'club_training';
      if (title == 'Regeneracje') return e['kind'] == 'recovery';
      if (title == 'Mecze') return e['_source'] == 'matches';
      if (title == 'Gole') return ProgressCalculator.asInt(e['goals']) > 0;
      if (title == 'Asysty') return ProgressCalculator.asInt(e['assists']) > 0;
      return true;
    }).toList();
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true,
      builder: (context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .7,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('$title · ${entries.length} wpisów')),
          Expanded(child: entries.isEmpty ? const Center(child: Text('Brak wpisów w wybranym okresie'))
            : ListView.builder(itemCount: entries.length, itemBuilder: (context, i) {
              final e = entries[i];
              final match = e['_source'] == 'matches';
              final club = e['kind'] == 'club_training';
              final recovery = e['kind'] == 'recovery';
              final type = recovery ? 'recovery' : match ? 'match' : club ? 'club_training' : 'training';
              return ListTile(leading: Icon(recovery ? Icons.spa_outlined : match ? Icons.sports_soccer : club ? Icons.groups : Icons.directions_run,
                  color: eventTypeColor(context.c, type)),
                title: Text(recovery ? 'Regeneracja' : match ? 'Mecz · ${e['opponent'] ?? ''}' : club ? 'Trening klubowy' : 'Trening indywidualny'),
                subtitle: Text('${first10((e['date'] ?? '').toString())} · '
                  '${e[match ? 'minutes_played' : 'duration_min'] ?? 0} min'),
                trailing: const Icon(Icons.edit_outlined), onTap: () => Navigator.pop(context, e));
            })),
        ]))));
    if (chosen != null && mounted) await _editEntry(chosen);
  }

  Future<void> _showExercises(String area) async {
    try {
      final all = await Api.drills();
      final terms = SkillRadarService.focusToAxis.entries.where((e) => e.value == area).map((e) => e.key.toLowerCase()).toList();
      if (terms.isEmpty) terms.add(area.toLowerCase());
      final drills = all.where((d) => terms.any((term) =>
        '${d.focus} ${d.title}'.toLowerCase().contains(term))).take(7).toList();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Drill>(context: context, isScrollControlled: true,
        builder: (context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .6,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('Ćwiczenia · $area')),
            Expanded(child: drills.isEmpty ? const Center(child: Text('Brak dopasowanych ćwiczeń w bibliotece'))
              : ListView(children: [for (final d in drills) ListTile(title: Text(d.title),
                subtitle: Text('${d.durationMin} min'), trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, d))])),
          ]))));
      if (chosen != null && mounted) await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DrillScreen(drill: chosen)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się wczytać ćwiczeń. Spróbuj ponownie.')));
    }
  }

  Widget _metric(
    AppColors c,
    double width,
    double height,
    IconData icon,
    String label,
    String value,
  ) {
    return InkWell(onTap: () => _showEntries(label), child: Container(
      key: ValueKey('metric-$label'),
      width: width,
      height: height,
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: withGap([
          Icon(icon, size: 18, color: c.brandPrimary),
          Text(value, style: barlow(size: 22, color: c.onSurface)),
          Text(
            label,
            style: manrope(
              size: 10,
              weight: FontWeight.w700,
              letterSpacing: 1,
              color: c.muted,
            ),
          ),
        ], height: 4),
      ),
    ));
  }

  Widget _badge(
    AppColors c, {
    required bool active,
    required IconData icon,
    required String title,
    required String sub,
  }) {
    final stats = _progress.data;
    final targets = <String, List<int>>{
      'Pierwszy trening': [stats?.totalTrainings ?? 0, 1], '10 treningów': [stats?.totalTrainings ?? 0, 10],
      '30 treningów': [stats?.totalTrainings ?? 0, 30], '100 treningów': [stats?.totalTrainings ?? 0, 100],
      'Pierwszy mecz': [stats?.totalMatches ?? 0, 1], '10 meczów': [stats?.totalMatches ?? 0, 10],
      '5 godzin aktywności': [stats?.totalMinutes ?? 0, 300], '20 godzin aktywności': [stats?.totalMinutes ?? 0, 1200],
      'Pierwszy gol': [stats?.totalGoals ?? 0, 1], 'Snajper': [stats?.totalGoals ?? 0, 5],
      'Hat-trick': [stats?.bestMatchGoals ?? 0, 3], 'Pierwsza asysta': [stats?.totalAssists ?? 0, 1],
      '10 asyst': [stats?.totalAssists ?? 0, 10],
    };
    final target = targets[title];
    final detail = active && _earned.containsKey(title) ? 'Zdobyto: ${_earned[title]}'
      : target == null ? '' : 'Postęp: ${math.min(target[0], target[1])}/${target[1]}';
    return Opacity(
      opacity: active ? 1 : 0.4,
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? c.brandPrimary : c.surfaceTertiary,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 22,
                color: active ? c.onBrandPrimary : c.muted,
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: manrope(
                      size: 15,
                      weight: FontWeight.w800,
                      color: c.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('$sub${detail.isEmpty ? '' : '\n$detail'}', style: manrope(size: 12, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
