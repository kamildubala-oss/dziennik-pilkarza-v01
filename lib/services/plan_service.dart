part of '../api.dart';

/// Wydzielona implementacja PlanService. Publiczny interfejs pozostaje w Api.
class PlanService {
  static Future<bool> addPlanDayToCalendar(PlanDay d) {
    return LocalDb.synchronized<bool>(() async {
      final events = await LocalDb.list('events');
      final added = Api._addPlanDay(events, d);
      if (added) await LocalDb.saveList('events', events);
      return added;
    });
  }

  static Future<int> addPlanWeekToCalendar(WeeklyPlan plan) {
    return LocalDb.synchronized<int>(() async {
      final events = await LocalDb.list('events');
      final today = todayIso();
      var count = 0;
      for (final d in plan.days) {
        if (d.isRest || first10(d.date).compareTo(today) < 0) continue;
        if (Api._addPlanDay(events, d)) count++;
      }
      if (count > 0) await LocalDb.saveList('events', events);
      return count;
    });
  }

  static String planKey(String date, String title) => '${first10(date)}|$title';

  static Future<Map<String, EventItem>> planEvents() async {
    final events = await LocalDb.list('events');
    final out = <String, EventItem>{
      // Treningi klubowe z kalendarza odpowiadają dniom klubowym planu.
      for (final e in events)
        if (_s(e['type']) == 'club_training')
          Api.planKey(_s(e['date']), 'Trening klubowy'): EventItem.fromJson(e),
      for (final e in events)
        if (Api._fromPlan(e))
          Api.planKey(_s(e['date']), _s(e['plan_title'])): EventItem.fromJson(
            e,
          ),
      // Ręczne zaplanowane treningi/mecze - powiązane z planem przez
      // plan_link (ustawiane w _addPlanDay przy już istniejącym wydarzeniu).
      for (final e in events)
        if (_isUserScheduledActivity(e))
          Api.planKey(_s(e['date']), _s(e['title'])): EventItem.fromJson(e),
    };
    // Indeks po ID - wszystkie wydarzenia, także wykonane, żeby
    // powiązanie z planem nie zależało od statusu wykonania.
    for (final e in events) {
      out['id:${_s(e['id'])}'] = EventItem.fromJson(e);
    }
    return out;
  }

  static Future<WeeklyPlan?> getWeeklyPlan() async {
    final week = _currentWeek();
    final doc = await LocalDb.getDoc('weekly_plan_${week.id}');
    if (doc == null) return null;
    final days = doc['days'];
    if (days is List) {
      final profile = await LocalDb.getDoc('profile') ?? <String, dynamic>{};
      // Dni planu powiązane z ręcznymi wydarzeniami kalendarza nie są
      // nadpisywane dniami klubowymi ani uzupełniane domyślnymi krokami.
      doc['days'] = _applyClubDays(
        days
            .whereType<Map>()
            .map((d) => _withSteps(Map<String, dynamic>.from(d)))
            .toList(),
        profile,
      );
    }
    return WeeklyPlan.fromJson(doc);
  }

  static Future<WeeklyPlan> generateWeeklyPlan() async {
    final week = _currentWeek();
    final profile = await LocalDb.getDoc('profile') ?? <String, dynamic>{};
    final scheduled = await _scheduledEventsForWeek(week.monday);

    // Uzupełniamy parametry wydarzeń (czas, intensywność, obszar) z powiązanych
    // treningów/meczów w dzienniku - używane w promptcie i przy nakładaniu.
    for (final entry in scheduled.entries) {
      for (final e in entry.value) {
        await _enrichEventFromDiary(e);
      }
    }

    List<Map<String, dynamic>>? days;
    var source = 'offline';

    if (Llm.enabled) {
      try {
        var prompt =
            'Zawodnik: '
            'imię=${_orDefault(profile['name'], 'brak')}, '
            'wiek=${_orDefault(profile['age'], 'brak')}, '
            'pozycja=${_orDefault(profile['position'], 'brak')}, '
            'dominująca noga=${_orDefault(profile['dominant_foot'], 'brak')}, '
            'klub=${_orDefault(profile['club'], 'brak')}, '
            'cel sezonu=${_orDefault(profile['season_goal'], 'ogólny rozwój')}. '
            'Dni treningów klubowych: ${_clubDays(profile).isEmpty ? 'brak' : (_clubDays(profile).toList()..sort()).map((d) => kPolishDays[d - 1]).join(', ')}. '
            'Tydzień rozpoczyna się ${dateIso(week.monday)} (Poniedziałek). '
            'Zbuduj plan 7 dni dopasowany do pozycji i celu.';

        // Zaplanowane przez zawodnika w kalendarzu treningi/mecze mają
        // pierwszeństwo - AI ma je uwzględnić i nie układać w tych dniach
        // własnego treningu (zostaną też nadpisane deterministycznie).
        if (scheduled.isNotEmpty) {
          final b = StringBuffer()
            ..writeln()
            ..writeln(
              'Zaplanowane przez zawodnika w kalendarzu (PRIORYTET - te dni są zajęte):',
            );
          for (final entry in scheduled.entries) {
            for (final e in entry.value) {
              final type = _s(e['type']);
              final label = type == 'match'
                  ? 'Mecz'
                  : type == 'club_training'
                  ? 'Trening klubowy'
                  : 'Trening';
              final time = _s(e['time']);
              final dur = _i(e['duration_min']) > 0
                  ? '${_i(e['duration_min'])} min'
                  : 'brak danych';
              final focus = _s(e['focus']);
              final intensity = _s(e['intensity']);
              final description = _s(e['description']);
              b.writeln(
                '- ${entry.key}${time.isNotEmpty ? ' ${time}' : ''}: $label – ${_s(e['title'])}'
                '${focus.isNotEmpty ? ' (obszar: $focus)' : ''}'
                '${dur != 'brak danych' ? ' ($dur)' : ''}'
                '${intensity.isNotEmpty ? ' (intensywność: $intensity)' : ''}'
                '${description.isNotEmpty ? ' (opis: $description)' : ''}'
                '. W tym dniu NIE układaj własnego treningu - powtórz tylko focus i tytuł tego wydarzenia, '
                'steps puste (zostanie uzupełnione automatycznie).',
              );
            }
          }
          b.writeln(
            'Te wydarzenia mają pierwszeństwo nad pozostałymi zasadami.',
          );
          prompt = '$prompt\n${b.toString()}';
        }
        final raw = await Llm.complete(
          fast: true,
          json: true,
          system: kPlanSystem,
          messages: <Map<String, String>>[
            <String, String>{'role': 'user', 'content': prompt},
          ],
        );
        final parsed = _extractJsonObject(raw);
        final list = parsed?['days'];
        if (list is List && list.length == 7) {
          final built = <Map<String, dynamic>>[];
          for (var i = 0; i < 7; i++) {
            final d = list[i];
            if (d is! Map) {
              built.clear();
              break;
            }
            var intensity = _s(d['intensity']);
            if (intensity != 'low' &&
                intensity != 'medium' &&
                intensity != 'high') {
              intensity = 'medium';
            }
            final dur = _i(d['duration_min']);
            built.add(<String, dynamic>{
              'date': dateIso(week.monday.add(Duration(days: i))),
              'day_name': _orDefault(d['day_name'], kPolishDays[i]),
              'focus': _orDefault(d['focus'], 'Trening'),
              'title': _orDefault(d['title'], 'Trening'),
              'duration_min': (dur == 0 ? 30 : dur).clamp(5, 180).toInt(),
              'intensity': intensity,
              'description': _s(d['description']),
              'steps': d['steps'] is List
                  ? (d['steps'] as List)
                        .map(_s)
                        .where((x) => x.trim().isNotEmpty)
                        .take(8)
                        .toList()
                  : <String>[],
              'tip': _s(d['tip']),
            });
          }
          if (built.length == 7) {
            days = built;
            source = 'online';
          }
        }
      } catch (_) {
        days = null;
      }
    }

    if (days == null) {
      days = _fallbackPlan(week.monday, profile);
      // Tryb offline: rzeczywiste ćwiczenia z pakietu 60 pozycji.
      final library = await OfflineCoach.exercises();
      final priorities = <String>['technika', 'taktyka', 'motoryka'];
      for (var i = 0; i < days.length; i++) {
        final day = days[i];
        if (_s(day['focus']) == 'Odpoczynek' ||
            _clubDays(profile).contains(i + 1))
          continue;
        final area = priorities[i % priorities.length];
        final matching = library
            .where((e) => _s(e['area']).toLowerCase() == area)
            .toList();
        if (matching.isEmpty) continue;
        final exercise = matching[(week.monday.day + i) % matching.length];
        day['title'] = _s(exercise['title']);
        day['focus'] = _s(exercise['area']);
        day['duration_min'] = _i(exercise['duration_min']).clamp(10, 60);
        day['intensity'] = _s(exercise['intensity']);
        day['description'] = _s(exercise['goal']);
        day['steps'] =
            (exercise['steps'] as List?)?.map(_s).toList() ?? <String>[];
        day['tip'] = _s(exercise['regression']);
      }
    }
    days = _applyClubDays(days.map(_withSteps).toList(), profile);

    // Zaplanowane przez zawodnika wydarzenia z kalendarza mają pierwszeństwo
    // nad dniami klubowymi i nad treningami AI.
    days = _applyCalendarEvents(days, scheduled);

    final plan = <String, dynamic>{
      'id': week.id,
      'week_start': dateIso(week.monday),
      'days': days,
      'generated_at': _nowIso(),
      'source': source,
    };
    await LocalDb.setDoc('weekly_plan_${week.id}', plan);
    return WeeklyPlan.fromJson(plan);
  }
}
