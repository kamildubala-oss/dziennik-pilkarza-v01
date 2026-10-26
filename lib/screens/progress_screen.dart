import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../services/coach_runtime.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';

const List<String> _skillKeys = <String>[
  'Technika',
  'Strzał',
  'Taktyka',
  'Motoryka',
  'Mentalność',
];

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

  bool _analyzing = false;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_onTabChanged);
    _progress.refetch();
    _weak.refetch();
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onTabChanged);
    _progress.dispose();
    _weak.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.selected.value == widget.index) _progress.refetch();
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
    final stats = _progress.data;

    return RefreshIndicator(
      color: c.brandPrimary,
      backgroundColor: c.surfaceSecondary,
      onRefresh: () => _progress.refetch(),
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
            if (_progress.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: Spinner()),
              )
            else
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
    final week = stats?.weekSessions ?? <int>[0, 0, 0, 0, 0, 0, 0];
    final maxV = math.max(1, week.isEmpty ? 1 : week.reduce(math.max));
    final avg = stats?.avgRating;

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
        child: Row(
          children: [
            Expanded(
              child: _heroCell(
                c,
                bg: c.brandPrimary,
                icon: Icons.local_fire_department,
                iconColor: c.onBrandPrimary,
                value: '${stats?.streakDays ?? 0}',
                valueColor: c.onBrandPrimary,
                label: 'DNI Z RZĘDU',
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
                label: 'ŚR. OCENA TRENINGÓW I MECZÓW',
                labelColor: c.muted,
              ),
            ),
          ],
        ),
      ),

      // ---------- Ostatnie 7 dni ----------
      _section('OSTATNIE 7 DNI'),
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
                        width: 18,
                        height: math.max(8.0, (week[i] / maxV) * 100),
                        child: i < (stats?.weekSessionTypes.length ?? 0) && week[i] > 0
                            ? Column(
                                children: [
                                  for (final type in kEventTypes.where((t) =>
                                      (stats!.weekSessionTypes[i][t] ?? 0) > 0))
                                    Expanded(
                                      flex: stats!.weekSessionTypes[i][type]!,
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
          final w = constraints.maxWidth * 0.315;
          return Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              _metric(
                c,
                w,
                Icons.directions_run,
                'Treningi',
                '${stats?.totalTrainings ?? 0}',
              ),
              _metric(
                c,
                w,
                Icons.sports_soccer,
                'Mecze',
                '${stats?.totalMatches ?? 0}',
              ),
              _metric(
                c,
                w,
                Icons.timer,
                'Minuty',
                '${stats?.totalMinutes ?? 0}',
              ),
              _metric(
                c,
                w,
                Icons.gps_fixed,
                'Gole',
                '${stats?.totalGoals ?? 0}',
              ),
              _metric(
                c,
                w,
                Icons.handshake,
                'Asysty',
                '${stats?.totalAssists ?? 0}',
              ),
              _metric(
                c,
                w,
                Icons.trending_up,
                'Śr. ocena T+M',
                avg != null && avg > 0 ? avg.toStringAsFixed(1) : '—',
              ),
            ],
          );
        },
      ),

      // ---------- Mapa umiejętności ----------
      Padding(
        padding: const EdgeInsets.only(top: Sp.md, bottom: Sp.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('AKTYWNOŚĆ W OBSZARACH'),
            const SizedBox(height: 2),
            Text(
              'Jasna = cały czas · Mocna = ostatnie 2 tyg.',
              style: manrope(size: 11, color: c.muted),
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: 260,
          height: 260,
          child: CustomPaint(
            painter: _RadarPainter(
              values: _skillKeys
                  .map((k) => (stats?.skillRadarRecent[k] ?? 0) / 100)
                  .toList(),
              shadowValues: _skillKeys
                  .map((k) => (stats?.skillRadarAll[k] ?? 0) / 100)
                  .toList(),
              labels: _skillKeys,
              gridColor: c.border,
              brandColor: c.brandPrimary,
              labelColor: c.muted,
            ),
          ),
        ),
      ),

      // ---------- Słabe punkty (AI) ----------
      ..._weakSection(c),

      // ---------- Odznaki: realizacja i regeneracja zamiast treningu codziennie ----------
      _section('ODZNAKI'),
      Column(
        children: withGap([
          _badge(c, active: (stats?.totalTrainings ?? 0) >= 1,
              icon: Icons.sports_score, title: 'Pierwszy trening',
              sub: 'Pierwszy zapisany trening.'),
          _badge(c, active: (stats?.totalTrainings ?? 0) >= 10,
              icon: Icons.directions_run, title: '10 treningów',
              sub: 'Rozwijasz systematyczność.'),
          _badge(c, active: (stats?.totalTrainings ?? 0) >= 30,
              icon: Icons.fitness_center, title: '30 treningów',
              sub: 'Treningowa wytrwałość.'),
          _badge(c, active: (stats?.totalTrainings ?? 0) >= 100,
              icon: Icons.military_tech, title: '100 treningów',
              sub: 'Długa droga, wielki postęp.'),
          _badge(c, active: (stats?.totalMatches ?? 0) >= 1,
              icon: Icons.sports_soccer, title: 'Pierwszy mecz',
              sub: 'Pierwszy zapisany występ.'),
          _badge(c, active: (stats?.totalMatches ?? 0) >= 10,
              icon: Icons.shield, title: '10 meczów',
              sub: 'Dziesięć sportowych doświadczeń.'),
          _badge(c, active: (stats?.totalMinutes ?? 0) >= 300,
              icon: Icons.timer, title: '5 godzin aktywności',
              sub: '300 minut treningów i meczów.'),
          _badge(c, active: (stats?.totalMinutes ?? 0) >= 1200,
              icon: Icons.access_time_filled, title: '20 godzin aktywności',
              sub: '1200 minut systematycznej pracy.'),
          _badge(c, active: (stats?.totalGoals ?? 0) >= 1,
              icon: Icons.sports_score, title: 'Pierwszy gol',
              sub: 'Pierwsza bramka w dzienniku.'),
          _badge(c, active: (stats?.totalGoals ?? 0) >= 5,
              icon: Icons.emoji_events, title: 'Snajper',
              sub: '5 bramek łącznie.'),
          _badge(c, active: (stats?.bestMatchGoals ?? 0) >= 3,
              icon: Icons.stars, title: 'Hat-trick',
              sub: '3 gole w jednym meczu.'),
          _badge(c, active: (stats?.totalAssists ?? 0) >= 1,
              icon: Icons.handshake, title: 'Pierwsza asysta',
              sub: 'Pomoc w zdobyciu bramki.'),
          _badge(c, active: (stats?.totalAssists ?? 0) >= 10,
              icon: Icons.group, title: '10 asyst',
              sub: 'Grasz zespołowo.'),
          _badge(c, active: stats?.hasTopRating == true,
              icon: Icons.star, title: 'Ocena 5/5',
              sub: 'Pierwsza najwyższa ocena.'),
          _badge(c, active: stats?.completedPlanWeek == true,
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
                  const SectionTitle('SŁABE PUNKTY'),
                  if (data != null && data.notice.isNotEmpty)
                    Text(data.notice, style: manrope(size: 12, color: c.muted)),
                  if (data != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${CoachRuntime.sourceLabel(data.source)}\n'
                        'Utworzono: ${CoachRuntime.dateLabel(data.generatedAt)} · '
                        '${data.noteCount} notatek',
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
      if (_weak.isLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.md),
          child: Center(child: Spinner()),
        )
      else if (data == null)
        _weakEmpty(
          c,
          icon: Icons.auto_fix_high,
          title: 'Brak analizy',
          sub: 'Trener AI przeczyta Twoje notatki „Co trzeba poprawić" '
              'i wyciągnie wnioski niezależnie od zapisanych treningów.',
        )
      else if (data.weakSpots.isEmpty)
        _weakEmpty(
          c,
          title: 'Zero słabych punktów!',
          sub: 'Dodaj kilka notatek w polach „Co trzeba poprawić" żeby '
              'trener miał z czym pracować.',
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
                  Text(
                    w.insight,
                    style: manrope(size: 14, height: 1.36, color: c.onSurface),
                  ),
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
  }) {
    return Container(
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
        ],
      ),
    );
  }

  Widget _metric(
    AppColors c,
    double width,
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      width: width,
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
    );
  }

  Widget _badge(
    AppColors c, {
    required bool active,
    required IconData icon,
    required String title,
    required String sub,
  }) {
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
                  Text(sub, style: manrope(size: 12, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wykres radarowy (pajęczyna) - odpowiednik komponentu `RadarChart` z SVG.
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.values,
    required this.shadowValues,
    required this.labels,
    required this.gridColor,
    required this.brandColor,
    required this.labelColor,
  });

  final List<double> values;
  final List<double> shadowValues;
  final List<String> labels;
  final Color gridColor;
  final Color brandColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 32;
    final n = values.length;

    double angleFor(int i) => (math.pi * 2 * i) / n - math.pi / 2;

    Path polygon(double Function(int) scaleFor) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a = angleFor(i);
        final s = scaleFor(i);
        final x = cx + math.cos(a) * r * s;
        final y = cy + math.sin(a) * r * s;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      return path;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final s in <double>[0.25, 0.5, 0.75, 1.0]) {
      canvas.drawPath(polygon((_) => s), gridPaint);
    }

    for (var i = 0; i < n; i++) {
      final a = angleFor(i);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
        gridPaint,
      );
    }

    // Warstwa "cień" - cały czas.
    final shadow = polygon((i) => math.max(0.02, shadowValues[i]));
    canvas.drawPath(
      shadow,
      Paint()
        ..color = brandColor.withAlpha(31) // 0.12
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      shadow,
      Paint()
        ..color = brandColor.withAlpha(102) // 0.4
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Warstwa "mocna" - ostatnie 14 dni.
    final recent = polygon((i) => math.max(0.02, values[i]));
    canvas.drawPath(
      recent,
      Paint()
        ..color = brandColor.withAlpha(102) // 0.4
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      recent,
      Paint()
        ..color = brandColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Etykiety osi.
    for (var i = 0; i < n; i++) {
      final a = angleFor(i);
      final lx = cx + math.cos(a) * (r + 18);
      final ly = cy + math.sin(a) * (r + 18);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: manrope(size: 10, weight: FontWeight.w700, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - baseline));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}
