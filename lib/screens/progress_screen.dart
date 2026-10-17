import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../resource.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../services/user_errors.dart';
import '../services/skill_radar_service.dart';
import 'coach_screen.dart';

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
  late final Resource<Progress> _progress = Resource(Api.progress, _rebuild);
  late final Resource<WeakSpotsPayload?> _weak = Resource(
    Api.getWeakSpots,
    _rebuild,
  );
  bool _analyzing = false;
  String? _analysisError;
  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_onTabChanged);
    _reload();
  }

  Future<void> _reload() => Future.wait([_progress.refetch(), _weak.refetch()]);
  void _onTabChanged() {
    if (widget.selected.value == widget.index) _reload();
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onTabChanged);
    _progress.dispose();
    _weak.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _analysisError = null;
    });
    try {
      await Api.analyzeWeakSpots();
      await _weak.refetch();
    } catch (error) {
      if (mounted) setState(() => _analysisError = friendlyError(error));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.c.surfaceSecondary,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: withGap(children, height: 8),
    ),
  );
  Widget _error(String message, VoidCallback retry) => _card([
    Text(message, style: manrope(color: context.c.error)),
    TextButton(onPressed: retry, child: const Text('Spróbuj ponownie')),
  ]);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final stats = _progress.data;
    return RefreshIndicator(
      onRefresh: _reload,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 16,
          16,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Twój postęp', style: barlow(size: 34, color: c.onSurface)),
            const SizedBox(height: 16),
            if (_progress.error != null)
              _error(
                'Nie udało się odczytać statystyk. Twoje dane pozostają zapisane.',
                _reload,
              ),
            if (_progress.isLoading)
              const Center(child: Spinner())
            else if (stats != null) ...[
              _weekSummary(stats),
              ..._weakSection(c),
              _activityChart(stats),
              _details(stats),
              _areas(stats),
              _achievements(stats),
            ],
          ],
        ),
      ),
    );
  }

  Widget _weekSummary(Progress stats) => _card([
    const SectionTitle('REALIZACJA TYGODNIA'),
    Text(
      stats.weekPlanned == 0
          ? 'Zacznij od planu'
          : '${stats.weekCompleted} z ${stats.weekPlanned} celów wykonanych',
      style: manrope(
        size: 22,
        weight: FontWeight.w700,
        color: context.c.onSurface,
      ),
    ),
    if (stats.weekPlanned > 0)
      LinearProgressIndicator(
        value: stats.weekCompleted / stats.weekPlanned,
        semanticsLabel: 'Realizacja tygodnia',
        semanticsValue: '${stats.weekCompleted} z ${stats.weekPlanned}',
      ),
    Text(
      stats.weekPlanned == 0
          ? 'Ułóż plan u trenera lub zaplanuj aktywność w kalendarzu.'
          : 'Treningi, mecze i potwierdzona regeneracja. Przyszłe cele pozostają do wykonania.',
      style: manrope(size: 14, color: context.c.muted),
    ),
    Text(
      'Seria aktywności: ${stats.streakDays} dni',
      style: manrope(size: 14, color: context.c.muted),
    ),
    const Text(
      'Seria obejmuje kolejne dni treningów i meczów do dziś lub wczoraj. Odpoczynek jest częścią planu.',
    ),
  ]);
  Widget _activityChart(Progress stats) {
    final c = context.c;
    final byType = stats.weekByType;
    final types = ['training', 'club_training', 'match'];
    final maxValue = math.max(1, stats.weekSessions.fold<int>(0, math.max));
    final now = DateTime.now();
    return _card([
      const SectionTitle('OSTATNIE 7 DNI'),
      const Text('Liczba wykonanych aktywności'),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final type in types)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 10, color: eventTypeColor(c, type)),
                const SizedBox(width: 4),
                Text(
                  eventTypeLabel(type),
                  style: manrope(size: 12, color: c.onSurface),
                ),
              ],
            ),
        ],
      ),
      for (var i = 0; i < 7; i++)
        Builder(
          builder: (context) {
            final day = DateTime(now.year, now.month, now.day - 6 + i);
            final values = [
              for (final type in types)
                i < (byType[type]?.length ?? 0) ? byType[type]![i] : 0,
            ];
            final total = values.fold<int>(0, (a, b) => a + b);
            final label =
                '${kWeekDays[day.weekday - 1]} ${day.day}.${day.month}';
            return Semantics(
              label:
                  '$label: treningi ${values[0]}, klubowe ${values[1]}, mecze ${values[2]}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$label · $total',
                    style: manrope(size: 13, color: c.onSurface),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (var j = 0; j < types.length; j++)
                          if (values[j] > 0)
                            Expanded(
                              flex: values[j],
                              child: ColoredBox(
                                color: eventTypeColor(c, types[j]),
                              ),
                            ),
                        if (maxValue - total > 0)
                          Expanded(
                            flex: maxValue - total,
                            child: ColoredBox(color: c.surfaceTertiary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ]);
  }

  Widget _details(Progress stats) => _card([
    const SectionTitle('STATYSTYKI · CAŁA HISTORIA'),
    Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final item in [
          ('Treningi', '${stats.totalTrainings}'),
          ('Mecze', '${stats.totalMatches}'),
          ('Minuty', '${stats.totalMinutes}'),
          ('Gole', '${stats.totalGoals}'),
          ('Asysty', '${stats.totalAssists}'),
        ])
          Text(
            '${item.$1}: ${item.$2}',
            style: manrope(size: 15, color: context.c.onSurface),
          ),
      ],
    ),
    Text(
      stats.ratedCount == 0
          ? 'Samoocena: brak ocen'
          : 'Średnia samoocena treningów i meczów: ${stats.avgRating.toStringAsFixed(1)}/5 · ${stats.ratedCount} ocen',
    ),
  ]);
  Widget _areas(Progress stats) {
    final maxCount = math.max(
      1,
      [
        ...stats.skillRadarRecent.values,
        ...stats.skillRadarPrevious.values,
      ].fold<int>(0, math.max),
    );
    return _card([
      const SectionTitle('AKTYWNOŚĆ W OBSZARACH'),
      const Text(
        'Liczba treningów obejmujących obszar. Jeden trening może dotyczyć kilku obszarów.',
      ),
      const Text(
        'Pokazuje zapisaną pracę, nie poziom umiejętności. Mecze nie są automatycznie przypisywane do obszarów.',
      ),
      for (final area in SkillRadarService.axes)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              area,
              style: manrope(
                size: 15,
                weight: FontWeight.w700,
                color: context.c.onSurface,
              ),
            ),
            Text(
              'Ostatnie 14 dni: ${stats.skillRadarRecent[area] ?? 0} · Poprzednie 14 dni: ${stats.skillRadarPrevious[area] ?? 0}',
            ),
            LinearProgressIndicator(
              value: (stats.skillRadarRecent[area] ?? 0) / maxCount,
              semanticsLabel: '$area, ostatnie 14 dni',
              semanticsValue: '${stats.skillRadarRecent[area] ?? 0} treningów',
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (stats.skillRadarPrevious[area] ?? 0) / maxCount,
              color: context.c.muted,
              semanticsLabel: '$area, poprzednie 14 dni',
              semanticsValue:
                  '${stats.skillRadarPrevious[area] ?? 0} treningów',
            ),
          ],
        ),
    ]);
  }

  List<Widget> _weakSection(AppColors c) {
    final data = _weak.data;
    return [
      _card([
        const SectionTitle('OBSZAR DO NASTĘPNEGO TRENINGU'),
        if (data != null)
          Text(
            'Analiza z ${first10(data.generatedAt)} · ${data.noteCount} notatek · '
            '${data.source == 'online'
                ? 'Online · Gemini'
                : data.source == 'offline'
                ? 'Offline'
                : 'Źródło nieznane'}',
            style: manrope(size: 13, color: c.muted),
          ),
        if (_weak.isLoading)
          const Center(child: Spinner())
        else if (data == null || data.weakSpots.isEmpty) ...[
          Text(
            data == null ? 'Brak analizy' : 'Za mało danych do wniosków',
            style: manrope(
              size: 18,
              weight: FontWeight.w700,
              color: c.onSurface,
            ),
          ),
          const Text(
            'Dodaj w podsumowaniu treningu, co chcesz poprawić. Trener poszuka powtarzających się tematów.',
          ),
        ] else ...[
          Text(
            data.weakSpots.first.area,
            style: manrope(
              size: 20,
              weight: FontWeight.w700,
              color: c.onSurface,
            ),
          ),
          Text(data.weakSpots.first.insight),
          PrimaryButton(
            label: 'Zobacz ćwiczenia',
            icon: Icons.fitness_center,
            onTap: () => pushModal<void>(
              context,
              Scaffold(
                appBar: AppBar(title: const Text('Ćwiczenia dla Ciebie')),
                body: CoachScreen(
                  selected: widget.selected,
                  index: widget.index,
                  initialSection: 1,
                  initialArea: data.weakSpots.first.area,
                ),
              ),
            ),
          ),
          if (data.weakSpots.length > 1)
            ExpansionTile(
              title: const Text('Pozostałe obszary'),
              children: [
                for (final item in data.weakSpots.skip(1))
                  ListTile(
                    title: Text(item.area),
                    subtitle: Text(item.insight),
                  ),
              ],
            ),
        ],
        SecondaryButton(
          label: _analyzing
              ? 'Analizowanie…'
              : data == null
              ? 'Analizuj notatki'
              : 'Odśwież analizę',
          onTap: _analyzing ? null : _analyze,
        ),
        if (_analysisError != null)
          Text(_analysisError!, style: manrope(color: c.error)),
        if (_weak.error != null)
          TextButton(
            onPressed: () => _weak.refetch(),
            child: const Text('Ponów odczyt analizy'),
          ),
      ]),
    ];
  }

  Widget _achievements(Progress stats) {
    final next = stats.totalTrainings < 1
        ? 1
        : stats.totalTrainings < 10
        ? 10
        : stats.totalTrainings < 30
        ? 30
        : stats.totalTrainings < 100
        ? 100
        : 0;
    final c = context.c;
    return _card([
      const SectionTitle('ODZNAKI'),
      Text(
        next == 0
            ? 'Masz odznakę za 100 treningów!'
            : 'Następna odznaka treningowa: ${stats.totalTrainings}/$next',
      ),
      if (next > 0)
        LinearProgressIndicator(
          value: stats.totalTrainings / next,
          semanticsLabel: 'Postęp do odznaki',
          semanticsValue: '${stats.totalTrainings} z $next treningów',
        ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Zobacz wszystkie odznaki'),
        children: [
          _badge(
            c,
            active: (stats?.totalTrainings ?? 0) >= 1,
            icon: Icons.sports_score,
            title: 'Pierwszy trening',
            sub: 'Pierwszy zapisany trening.',
          ),
          _badge(
            c,
            active: (stats?.totalTrainings ?? 0) >= 10,
            icon: Icons.directions_run,
            title: '10 treningów',
            sub: 'Rozwijasz systematyczność.',
          ),
          _badge(
            c,
            active: (stats?.totalTrainings ?? 0) >= 30,
            icon: Icons.fitness_center,
            title: '30 treningów',
            sub: 'Treningowa wytrwałość.',
          ),
          _badge(
            c,
            active: (stats?.totalTrainings ?? 0) >= 100,
            icon: Icons.military_tech,
            title: '100 treningów',
            sub: 'Długa droga, wielki postęp.',
          ),
          _badge(
            c,
            active: (stats?.totalMatches ?? 0) >= 1,
            icon: Icons.sports_soccer,
            title: 'Pierwszy mecz',
            sub: 'Pierwszy zapisany występ.',
          ),
          _badge(
            c,
            active: (stats?.totalMatches ?? 0) >= 10,
            icon: Icons.shield,
            title: '10 meczów',
            sub: 'Dziesięć sportowych doświadczeń.',
          ),
          _badge(
            c,
            active: (stats?.totalMinutes ?? 0) >= 300,
            icon: Icons.timer,
            title: '5 godzin aktywności',
            sub: '300 minut treningów i meczów.',
          ),
          _badge(
            c,
            active: (stats?.totalMinutes ?? 0) >= 1200,
            icon: Icons.access_time_filled,
            title: '20 godzin aktywności',
            sub: '1200 minut systematycznej pracy.',
          ),
          _badge(
            c,
            active: (stats?.totalGoals ?? 0) >= 1,
            icon: Icons.sports_score,
            title: 'Pierwszy gol',
            sub: 'Pierwsza bramka w dzienniku.',
          ),
          _badge(
            c,
            active: (stats?.totalGoals ?? 0) >= 5,
            icon: Icons.emoji_events,
            title: 'Snajper',
            sub: '5 bramek łącznie.',
          ),
          _badge(
            c,
            active: (stats?.bestMatchGoals ?? 0) >= 3,
            icon: Icons.stars,
            title: 'Hat-trick',
            sub: '3 gole w jednym meczu.',
          ),
          _badge(
            c,
            active: (stats?.totalAssists ?? 0) >= 1,
            icon: Icons.handshake,
            title: 'Pierwsza asysta',
            sub: 'Pomoc w zdobyciu bramki.',
          ),
          _badge(
            c,
            active: (stats?.totalAssists ?? 0) >= 10,
            icon: Icons.group,
            title: '10 asyst',
            sub: 'Grasz zespołowo.',
          ),
          _badge(
            c,
            active: stats?.hasTopRating == true,
            icon: Icons.star,
            title: 'Ocena 5/5',
            sub: 'Pierwsza najwyższa ocena.',
          ),
          _badge(
            c,
            active: stats?.completedPlanWeek == true,
            icon: Icons.self_improvement,
            title: 'Tydzień według planu',
            sub: 'Realizacja aktywności i zaplanowanej regeneracji.',
          ),
        ],
      ),
    ]);
  }

  Widget _badge(
    AppColors c, {
    required bool active,
    required IconData icon,
    required String title,
    required String sub,
  }) => ListTile(
    leading: Icon(
      active ? Icons.check_circle : icon,
      color: active ? c.success : c.muted,
    ),
    title: Text(title),
    subtitle: Text('${active ? 'Zdobyta' : 'Do zdobycia'} · $sub'),
  );
}
