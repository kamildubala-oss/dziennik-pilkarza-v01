import 'dart:convert';

import 'coach_content.dart';
import 'llm.dart';
import 'offline_coach.dart';
import 'local_db.dart';
import 'models.dart';
import 'utils.dart';
import 'services/progress_calculator.dart';

/// Błąd walidacji / operacji - analogiczny do błędów HTTP z dawnego backendu.
class ApiException implements Exception {
  ApiException(this.statusCode, this.reason, this.body);

  final int statusCode;
  final String reason;
  final String body;

  @override
  String toString() => '$statusCode $reason: $body';
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

void _check(bool ok, String message) {
  if (!ok) throw ApiException(422, 'Unprocessable Entity', message);
}


/// Data wykonania nie może być przyszła; planowanie może dotyczyć dowolnego dnia.
void _validateActivityDate(String date, {required bool isPlanned}) {
  final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date);
  final parsed = DateTime.tryParse(date);
  _check(match && parsed != null && dateIso(parsed) == date,
      'Podaj prawidłową datę (RRRR-MM-DD).');
  if (!isPlanned) {
    _check(date.compareTo(todayIso()) <= 0,
        'Nie można zapisać wykonanego treningu ani meczu z datą przyszłą. '
        'Użyj opcji planowania.');
  }
}

int _i(dynamic v) => v is num ? v.toInt() : 0;

String _s(dynamic v) => v == null ? '' : v.toString();

String _orDefault(dynamic v, String fallback) {
  final s = _s(v).trim();
  return s.isEmpty ? fallback : s;
}

/// Sortowanie stabilne po kluczu tekstowym (jak sort() w bazie).
List<Map<String, dynamic>> _sortedBy(
  List<Map<String, dynamic>> items,
  String key, {
  bool desc = false,
}) {
  final indexed = <MapEntry<int, Map<String, dynamic>>>[];
  for (var i = 0; i < items.length; i++) {
    indexed.add(MapEntry<int, Map<String, dynamic>>(i, items[i]));
  }
  indexed.sort((a, b) {
    final av = _s(a.value[key]);
    final bv = _s(b.value[key]);
    final c = desc ? bv.compareTo(av) : av.compareTo(bv);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

Map<String, dynamic>? _extractJsonObject(String text) {
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(text);
  if (m == null) return null;
  try {
    final decoded = jsonDecode(m.group(0)!);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    // Niepoprawny JSON z modelu.
  }
  return null;
}

class _WeekInfo {
  const _WeekInfo(this.id, this.monday);

  final String id; // np. 2026-W19
  final DateTime monday; // data poniedziałku (UTC, północ)
}

_WeekInfo _currentWeek() {
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final thursday = monday.add(const Duration(days: 3));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  final week = (thursday.difference(jan1).inDays ~/ 7) + 1;
  return _WeekInfo(
    '${thursday.year}-W${week.toString().padLeft(2, '0')}',
    monday,
  );
}

class _PlanBase {
  const _PlanBase(this.focus, this.title, this.duration, this.intensity);

  final String focus;
  final String title;
  final int duration;
  final String intensity;
}

const List<_PlanBase> _fallbackBase = <_PlanBase>[
  _PlanBase('Prowadzenie', 'Slalom i zmiany kierunku', 35, 'medium'),
  _PlanBase('Decyzyjność', 'Pojedynki 1v1 z zadaniem', 30, 'high'),
  _PlanBase('Siła', 'Trening motoryczny (IMOPEKSIS)', 25, 'medium'),
  _PlanBase('Strzał', 'Strzały z 3 stref', 40, 'high'),
  _PlanBase('Mentalność', 'Wizualizacja i oddech', 10, 'low'),
  _PlanBase('Odpoczynek', 'Rozciąganie i regeneracja', 20, 'low'),
  _PlanBase('Mecz', 'Mecz lub spacerowy trening', 70, 'medium'),
];

List<Map<String, dynamic>> _fallbackPlan(
  DateTime monday,
  Map<String, dynamic> profile,
) {
  final goal = _orDefault(profile['season_goal'], 'ogólny rozwój');
  final position = _orDefault(profile['position'], 'zawodnik');
  final clubDays = _clubDays(profile);
  final days = <Map<String, dynamic>>[];
  for (var i = 0; i < _fallbackBase.length; i++) {
    final b = _fallbackBase[i];
    if (clubDays.contains(i + 1)) {
      days.add(
        _clubPlanDay(
          dateIso(monday.add(Duration(days: i))),
          kPolishDays[i],
          profile,
        ),
      );
      continue;
    }
    days.add(<String, dynamic>{
      'date': dateIso(monday.add(Duration(days: i))),
      'day_name': kPolishDays[i],
      'focus': b.focus,
      'title': b.title,
      'duration_min': b.duration,
      'intensity': b.intensity,
      'description': 'Plan dopasowany do pozycji $position. Cel sezonu: $goal.',
      'steps': planStepsFor(b.focus),
      'tip': planTipFor(b.focus),
    });
  }
  return days;
}

/// Dni treningów klubowych z profilu (1 = poniedziałek ... 7 = niedziela).
Set<int> _clubDays(Map<String, dynamic> profile) {
  final raw = profile['club_days'];
  if (raw is! List) return <int>{};
  return raw.map(_i).where((d) => d >= 1 && d <= 7).toSet();
}

/// Opis treningu klubowego - taki sam w planie i w kalendarzu.
String _clubDescription(Map<String, dynamic> profile) {
  final club = _s(profile['club']).trim();
  return club.isEmpty ? 'Trening z drużyną.' : 'Trening z drużyną ($club).';
}

/// Dzień treningu klubowego w planie - identyczny jak wpis w kalendarzu.
/// Trener AI nie układa w te dni własnego treningu.
Map<String, dynamic> _clubPlanDay(
  String date,
  String dayName,
  Map<String, dynamic> profile,
) {
  final dur = _i(profile['club_duration_min']);
  return <String, dynamic>{
    'date': date,
    'day_name': dayName,
    'focus': 'Trening klubowy',
    'title': 'Trening klubowy',
    'duration_min': dur > 0 ? dur : 90,
    'intensity': 'medium',
    'description': _clubDescription(profile),
    'steps': planStepsFor('Trening klubowy'),
    'tip': planTipFor('Trening klubowy'),
  };
}

/// Podmienia dni treningów klubowych w planie na stały wpis klubowy.
/// Dni, które przestały być klubowe, a mają wpis klubowy, zamienia na
/// trening z planu awaryjnego.
List<Map<String, dynamic>> _applyClubDays(
  List<Map<String, dynamic>> days,
  Map<String, dynamic> profile,
) {
  final club = _clubDays(profile);
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < days.length; i++) {
    final d = days[i];
    final date = _s(d['date']);
    final wd = DateTime.tryParse(first10(date))?.weekday ?? (i + 1);
    final dayName =
        _s(d['day_name']).isEmpty ? kPolishDays[wd - 1] : _s(d['day_name']);
    // Dni powiązane z ręcznymi wydarzeniami użytkownika nie są nadpisywane
    // dniami klubowymi - wydarzenie użytkownika ma pierwszeństwo.
    if ((d['calendar_event_ids'] as List?)?.isNotEmpty == true) {
      out.add(d);
      continue;
    }
    if (club.contains(wd)) {
      out.add(_clubPlanDay(date, dayName, profile));
    } else if (_s(d['focus']) == 'Trening klubowy' &&
        wd <= _fallbackBase.length) {
      final b = _fallbackBase[wd - 1];
      out.add(<String, dynamic>{
        'date': date,
        'day_name': dayName,
        'focus': b.focus,
        'title': b.title,
        'duration_min': b.duration,
        'intensity': b.intensity,
        'description': 'Trening indywidualny.',
        'steps': planStepsFor(b.focus),
        'tip': planTipFor(b.focus),
      });
    } else {
      out.add(d);
    }
  }
  return out;
}

/// Uzupełnia dzień planu o kroki i wskazówkę, jeśli ich brakuje.
Map<String, dynamic> _withSteps(Map<String, dynamic> day) {
  final out = Map<String, dynamic>.from(day);
  // Dni powiązane z konkretnymi wydarzeniami użytkownika z kalendarza
  // nie dostają domyślnej rozpiski - użytkownik sam zaplanował trening/mecz.
  if ((out['calendar_event_ids'] as List?)?.isNotEmpty == true) return out;
  final steps = out['steps'];
  if (steps is! List || steps.isEmpty) {
    out['steps'] = planStepsFor(_s(out['focus']));
  }
  if (_s(out['tip']).trim().isEmpty) out['tip'] = planTipFor(_s(out['focus']));
  return out;
}

/// Wydarzenie zaplanowane przez użytkownika (nie z planu tygodnia AI,
/// nie automatyczny trening klubowy z profilu, nie notatka).
/// Uwaga: "zaplanowane" oznacza datę przyszłą (jutro lub pózniej) -
/// dzisiejsze/przeszłe wydarzenia są już "wykonane" (done=true).
bool _isUserScheduledActivity(Map<String, dynamic> e) {
  if (e['done'] == true) return false;
  if (!const {'training', 'club_training', 'match'}.contains(_s(e['type']))) {
    return false;
  }
  final source = _s(e['source']);
  final originalSource = _s(e['planned_source']);
  if (originalSource == 'plan' || originalSource == 'club') return false;
  return const {'', 'trainings', 'matches'}.contains(source);
}

/// Zbiera zaplanowane przez użytkownika treningi i mecze w tygodniu planu
/// (poniedziałek–niedziela, niedziela włącznie).
Future<Map<String, List<Map<String, dynamic>>>> _scheduledEventsForWeek(DateTime monday) async {
  final events = await LocalDb.list('events');
  final byDate = <String, List<Map<String, dynamic>>>{};
  for (var i = 0; i < 7; i++) {
    final iso = dateIso(monday.add(Duration(days: i)));
    for (final e in events) {
      if (!_isUserScheduledActivity(e)) continue;
      if (first10(_s(e['date'])) != iso) continue;
      byDate.putIfAbsent(iso, () => []).add(Map<String, dynamic>.from(e));
    }
  }
  return byDate;
}

/// Uzupełnia dane wydarzenia o parametry z powiązanego treningu/meczu
/// w dzienniku (source w trainings/matches).
Future<void> _enrichEventFromDiary(Map<String, dynamic> e) async {
  final source = _s(e['source']);
  final sourceId = _s(e['source_id']);
  if (sourceId.isEmpty) return;
  if (source == 'trainings') {
    final t = await LocalDb.list('trainings')
        .then((items) => items.firstWhere((x) => _s(x['id']) == sourceId,
            orElse: () => <String, dynamic>{}));
    if (t.isNotEmpty) {
      if (_i(t['duration_min']) > 0) e['duration_min'] = _i(t['duration_min']);
      if (_s(t['intensity']).isNotEmpty) e['intensity'] = _s(t['intensity']);
      if (_s(e['focus']).isEmpty && _s(t['focus']).isNotEmpty) {
        e['focus'] = _s(t['focus']);
      }
    }
  } else if (source == 'matches') {
    final m = await LocalDb.list('matches')
        .then((items) => items.firstWhere((x) => _s(x['id']) == sourceId,
            orElse: () => <String, dynamic>{}));
    if (m.isNotEmpty) {
      if (_i(m['minutes_played']) > 0) {
        e['duration_min'] = _i(m['minutes_played']);
      }
    }
  }
}

/// Podmienia dni planu na zaplanowane przez użytkownika treningi/mecze z
/// kalendarza. Ręczne wydarzenia mają pierwszeństwo nad dniami klubowymi i
/// nad treningami AI. Jeśli w danym dniu jest więcej niż jedno wydarzenie,
/// zachowujemy listę `calendar_event_ids`, a na głównej karcie planu używamy
/// pierwszego (lub meczu, jeśli jest mecz).
List<Map<String, dynamic>> _applyCalendarEvents(
  List<Map<String, dynamic>> days,
  Map<String, List<Map<String, dynamic>>> scheduledByDate,
) {
  final out = <Map<String, dynamic>>[];
  for (final d in days) {
    final date = first10(_s(d['date']));
    final scheduled = scheduledByDate[date];
    if (scheduled == null || scheduled.isEmpty) {
      out.add(d);
      continue;
    }
    // Sortowanie: mecz > trening klubowy > trening, potem wg czasu.
    int rank(String type) => type == 'match'
        ? 0
        : type == 'club_training'
            ? 1
            : 2;
    final sorted = List<Map<String, dynamic>>.from(scheduled)
      ..sort((a, b) {
        final r = rank(_s(a['type'])).compareTo(rank(_s(b['type'])));
        return r != 0 ? r : _s(a['time']).compareTo(_s(b['time']));
      });
    final primary = sorted.first;
    final rest = sorted.sublist(1);
    final type = _s(primary['type']);
    final focus = type == 'match'
        ? 'Mecz'
        : type == 'club_training'
            ? 'Trening klubowy'
            : (_s(primary['focus']).isNotEmpty
                ? _s(primary['focus'])
                : 'Trening');
    // Jeśli brak danych, zostawiamy domyślne (trening/mecz AI może
    // potem dostosować, gdy plan jest przeglądany).
    final duration = _i(primary['duration_min']);
    final intensity = _s(primary['intensity']);
    final steps = _sList(primary['steps']);
    final tip = _s(primary['tip']);
    final dayName = _s(d['day_name']);
    final newDay = <String, dynamic>{
      'date': date,
      'day_name': dayName,
      'focus': focus,
      'title': _s(primary['title']).isNotEmpty ? _s(primary['title']) : 'Trening',
      'duration_min': duration > 0 ? duration : 60,
      'intensity': intensity.isNotEmpty ? intensity : 'medium',
      'description': _s(primary['description']),
      'steps': steps,
      'tip': tip,
      'calendar_event_ids': <String>[for (final e in sorted) _s(e['id'])],
      'extra_event_ids': <String>[for (final e in rest) _s(e['id'])],
    };
    out.add(newDay);
  }
  return out;
}

List<String> _sList(dynamic v) =>
    v is List ? v.map(_s).where((x) => x.trim().isNotEmpty).toList() : <String>[];

/// "Backend" aplikacji - działa w całości na telefonie (bez serwera).
/// Interfejs jest taki sam jak wcześniej, dlatego ekrany nie wymagały zmian.
class Api {
  Api._();

  // ---------------- Treningi ----------------
  static Future<List<Training>> listTrainings() async {
    final items = await LocalDb.list('trainings');
    return _sortedBy(items, 'date', desc: true).map(Training.fromJson).toList();
  }

  /// Zapisuje trening. [focuses] - lista obszarów (min. 1).
  /// [kind] - 'training' lub 'club_training'.
  /// [plannedEventId] - zaplanowane wydarzenie z kalendarza, które ten
  /// trening realizuje (zostanie oznaczone jako wykonane zamiast tworzenia
  /// nowego wpisu w kalendarzu).
  static Future<Training> createTraining({
    required String date,
    required int durationMin,
    required List<String> focuses,
    required String intensity,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
    String kind = 'training',
    String? plannedEventId,
    /// True, gdy zapisujemy przyszły plan (Kalendarz → Dodaj), a nie
    /// wykonaną już aktywność. Dzisiejsze planowane treningi nie są
    /// oznaczane jako wykonane.
    bool isPlanned = false,
  }) async {
    _validateActivityDate(date, isPlanned: isPlanned);
    _check(
      durationMin >= 0 && durationMin <= 600,
      'duration_min must be between 0 and 600',
    );
    _check(rating >= 1 && rating <= 5, 'rating must be between 1 and 5');
    _check(focuses.isNotEmpty || kind == 'club_training',
        'focuses must not be empty');
    final doc = <String, dynamic>{
      'id': LocalDb.newId(),
      'date': date,
      'duration_min': durationMin,
      'focus': focuses.join(', '),
      'focuses': focuses,
      'intensity': intensity,
      'rating': rating,
      'went_well': wentWell,
      'to_improve': toImprove,
      'notes': notes,
      'kind': kind == 'club_training' ? 'club_training' : 'training',
      'created_at': _nowIso(),
    };
    if (isPlanned) {
      final planDetails = <String>[
        'Czas: $durationMin min',
        'Obszary: ${focuses.join(', ')}',
        'Intensywność: $intensity',
        'Planowana ocena: $rating/5',
        if (wentWell.trim().isNotEmpty) 'Co było dobrze: $wentWell',
        if (toImprove.trim().isNotEmpty) 'Do poprawy: $toImprove',
        if (notes.trim().isNotEmpty) 'Notatka: $notes',
      ].join('\n');
      await createEvent(
        date: date,
        type: kind,
        title: kind == 'club_training' ? 'Trening klubowy: ${focuses.join(', ')}' : 'Trening: ${focuses.join(', ')}',
        details: <String, dynamic>{'focus': focuses.join(', '), 'focuses': focuses, 'duration_min': durationMin, 'intensity': intensity, 'rating': rating, 'went_well': wentWell, 'to_improve': toImprove, 'notes': notes},
        description: planDetails,
      );
      return Training.fromJson(doc);
    }
    return LocalDb.synchronized<Training>(() async {
      // Sprawdzenie planu PRZED dopisaniem treningu i wewnątrz blokady.
      // Dzięki temu nawet dwa równoczesne zapisy nie tworzą duplikatu.
      List<Map<String, dynamic>>? events;
      var eventIndex = -1;
      if (plannedEventId != null && plannedEventId.isNotEmpty) {
        events = await LocalDb.list('events');
        eventIndex = events.indexWhere((e) => _s(e['id']) == plannedEventId);
        if (eventIndex < 0) {
          throw ApiException(404, 'Not Found',
              'Nie znaleziono zaplanowanego treningu w kalendarzu.');
        }
        final planned = events[eventIndex];
        final linkedId = _s(planned['source_id']);
        if (linkedId.isNotEmpty || planned['done'] == true) {
          if (_s(planned['source']) == 'trainings' && linkedId.isNotEmpty) {
            final saved = await LocalDb.list('trainings');
            for (final item in saved) {
              if (_s(item['id']) == linkedId) {
                return Training.fromJson(item);
              }
            }
          }
          throw ApiException(409, 'Conflict',
              'Ten trening jest już zapisany jako wykonany. Otwórz jego edycję.');
        }
        if (_s(planned['type']) != 'training' &&
            _s(planned['type']) != 'club_training') {
          throw ApiException(409, 'Conflict',
              'Wybrane wydarzenie nie jest treningiem.');
        }
      }
      final items = await LocalDb.list('trainings');
      items.add(doc);
      await LocalDb.saveList('trainings', items);
      final linked = _eventForTraining(doc);
      if (events != null) {
        final planned = events[eventIndex];
        events[eventIndex] = <String, dynamic>{
          ...planned,
          ..._completedEventFields(linked),
          'done': true,
          'source': 'trainings',
          'source_id': doc['id'],
          'planned_source': _s(planned['source']),
        };
        await LocalDb.saveList('events', events);
      } else {
        await _addLinkedEvent(linked);
      }
      return Training.fromJson(doc);
    });
  }

  static Future<Training?> getTraining(String id) async {
    final items = await LocalDb.list('trainings');
    for (final t in items) {
      if (_s(t['id']) == id) return Training.fromJson(t);
    }
    return null;
  }

  static Future<MatchEntry?> getMatch(String id) async {
    final items = await LocalDb.list('matches');
    for (final m in items) {
      if (_s(m['id']) == id) return MatchEntry.fromJson(m);
    }
    return null;
  }

  /// Pola wykonania w kalendarzu są projekcją rzeczywistego wpisu
  /// w dzienniku. Nie kopiujemy ID wydarzenia ani godziny planu.
  static Map<String, dynamic> _completedEventFields(Map<String, dynamic> linked) {
    const fields = <String>[
      'date', 'title', 'description', 'type', 'duration_min',
      'focus', 'focuses', 'intensity', 'rating',
      'opponent', 'result', 'minutes_played', 'goals', 'assists',
      'went_well', 'to_improve', 'notes',
    ];
    return <String, dynamic>{
      for (final key in fields)
        if (linked.containsKey(key)) key: linked[key],
    };
  }

  /// Aktualizuje zarówno opis, jak i dane strukturalne karty kalendarza.
  /// Wywoływane wewnątrz LocalDb.synchronized.
  static Future<void> _refreshLinkedEvents(
      String sourceId, Map<String, dynamic> linked) async {
    final events = await LocalDb.list('events');
    var changed = false;
    for (final e in events) {
      if (_s(e['source_id']) != sourceId) continue;
      e.addAll(_completedEventFields(linked));
      e['done'] = true;
      changed = true;
    }
    if (changed) await LocalDb.saveList('events', events);
  }

  /// Edycja zapisanego treningu (także oceny treningu klubowego).
  static Future<Training> updateTraining(
    String id, {
    String? date,
    int? durationMin,
    List<String>? focuses,
    String? intensity,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
  }) {
    if (date != null) _validateActivityDate(date, isPlanned: false);
    if (durationMin != null) {
      _check(durationMin >= 0 && durationMin <= 600,
          'Czas treningu musi wynosić od 0 do 600 minut.');
    }
    _check(rating >= 1 && rating <= 5, 'rating must be between 1 and 5');
    return LocalDb.synchronized<Training>(() async {
      final items = await LocalDb.list('trainings');
      final idx = items.indexWhere((t) => _s(t['id']) == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Training not found');
      final t = items[idx];
      if (date != null) t['date'] = date;
      if (durationMin != null) t['duration_min'] = durationMin;
      if (focuses != null) {
        t['focuses'] = focuses;
        t['focus'] = focuses.join(', ');
      }
      if (intensity != null) t['intensity'] = intensity;
      t['rating'] = rating;
      t['went_well'] = wentWell;
      t['to_improve'] = toImprove;
      t['notes'] = notes;
      t['updated_at'] = _nowIso();
      await LocalDb.saveList('trainings', items);
      await _refreshLinkedEvents(id, _eventForTraining(t));
      return Training.fromJson(t);
    });
  }

  /// Edycja zapisanego meczu.
  static Future<MatchEntry> updateMatch(
    String id, {
    required String date,
    required String opponent,
    required String result,
    required int minutesPlayed,
    required int goals,
    required int assists,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
  }) {
    _validateActivityDate(date, isPlanned: false);
    _check(minutesPlayed >= 0 && minutesPlayed <= 180,
        'Czas meczu musi wynosić od 0 do 180 minut.');
    _check(goals >= 0 && goals <= 20, 'Liczba goli musi wynosić od 0 do 20.');
    _check(assists >= 0 && assists <= 20,
        'Liczba asyst musi wynosić od 0 do 20.');
    _check(rating >= 1 && rating <= 5, 'rating must be between 1 and 5');
    return LocalDb.synchronized<MatchEntry>(() async {
      final items = await LocalDb.list('matches');
      final idx = items.indexWhere((m) => _s(m['id']) == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Match not found');
      final m = items[idx];
      m['date'] = date;
      m['opponent'] = opponent;
      m['result'] = result;
      m['minutes_played'] = minutesPlayed;
      m['goals'] = goals;
      m['assists'] = assists;
      m['rating'] = rating;
      m['went_well'] = wentWell;
      m['to_improve'] = toImprove;
      m['notes'] = notes;
      m['updated_at'] = _nowIso();
      await LocalDb.saveList('matches', items);
      await _refreshLinkedEvents(id, _eventForMatch(m));
      return MatchEntry.fromJson(m);
    });
  }

  /// Ocena treningu klubowego (ocena, co było dobrze, co poprawić, notatki).
  /// Pierwsza ocena tworzy wpis treningu w dzienniku i oznacza trening
  /// w kalendarzu jako wykonany; kolejne aktualizują ocenę.
  static Future<void> rateClubTraining(
    EventItem e, {
    required List<String> focuses,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
  }) async {
    if (e.source == 'trainings' && e.sourceId.isNotEmpty) {
      final existing = await getTraining(e.sourceId);
      if (existing != null) {
        await updateTraining(
          e.sourceId,
          focuses: focuses,
          rating: rating,
          wentWell: wentWell,
          toImprove: toImprove,
          notes: notes,
        );
        return;
      }
    }
    final profile = await LocalDb.getDoc('profile') ?? <String, dynamic>{};
    final dur = e.durationMin > 0
        ? e.durationMin
        : (_i(profile['club_duration_min']) > 0
            ? _i(profile['club_duration_min'])
            : 90);
    await createTraining(
      date: first10(e.date),
      durationMin: dur,
      focuses: focuses,
      intensity: e.intensity.isNotEmpty ? e.intensity : 'medium',
      rating: rating,
      wentWell: wentWell,
      toImprove: toImprove,
      notes: notes,
      kind: 'club_training',
      plannedEventId: e.id,
    );
  }

  // ---------------------------------------------------------------------
  // Eksport i kopia zapasowa
  // ---------------------------------------------------------------------

  static const String _backupApp = 'dziennik_pilkarza';

  /// Pełna kopia zapasowa (JSON) - do przywrócenia na tym lub innym telefonie.
  static Future<String> exportBackup() async {
    final data = await LocalDb.exportAll();
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'app': _backupApp,
      'version': 1,
      'exported_at': _nowIso(),
      'counts': <String, int>{
        'trainings': (data['trainings'] as List?)?.length ?? 0,
        'matches': (data['matches'] as List?)?.length ?? 0,
        'events': (data['events'] as List?)?.length ?? 0,
      },
      'data': data,
    });
  }

  /// Sprawdza plik kopii i zwraca liczbę treningów/meczów/wydarzeń.
  /// Rzuca [ApiException], gdy plik nie jest kopią z tej aplikacji.
  static Map<String, int> inspectBackup(String json) {
    final data = _parseBackup(json);
    int len(String k) => (data[k] is List) ? (data[k] as List).length : 0;
    return <String, int>{
      'trainings': len('trainings'),
      'matches': len('matches'),
      'events': len('events'),
    };
  }

  /// Przywraca dane z kopii (zastępuje obecne dane w aplikacji).
  static Future<void> importBackup(String json) async {
    await LocalDb.importAll(_parseBackup(json));
  }

  static Map<String, dynamic> _parseBackup(String json) {
    dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw ApiException(400, 'Bad Request', 'To nie jest plik kopii (JSON).');
    }
    if (decoded is! Map ||
        decoded['app'] != _backupApp ||
        decoded['data'] is! Map) {
      throw ApiException(
          400, 'Bad Request', 'To nie jest kopia z Dziennika Piłkarza.');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    try {
      LocalDb.validateImport(data);
    } on FormatException catch (error) {
      throw ApiException(400, 'Bad Request',
          'Kopia zawiera nieprawidłowe dane: ${error.message}');
    }
    return data;
  }

  /// Pole CSV (średnik jako separator - Excel w polskiej wersji).
  static String _csv(dynamic v) {
    var t = _s(v).replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    if (RegExp(r'^[=+\-@]').hasMatch(t)) t = "'$t";
    if (t.contains(';') || t.contains('"')) {
      return '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }

  static String _csvDoc(List<String> header, List<List<dynamic>> rows) {
    final b = StringBuffer('\uFEFF'); // BOM - polskie znaki w Excelu
    b.writeln(header.map(_csv).join(';'));
    for (final r in rows) {
      b.writeln(r.map(_csv).join(';'));
    }
    return b.toString();
  }

  /// Treningi (własne i klubowe) w CSV - otwiera się w Excelu/Arkuszach.
  static Future<String> exportTrainingsCsv() async {
    final items = _sortedBy(await LocalDb.list('trainings'), 'date');
    return _csvDoc(
      <String>[
        'Data',
        'Rodzaj',
        'Obszary',
        'Czas (min)',
        'Intensywność',
        'Ocena (1-5)',
        'Co było dobrze',
        'Co trzeba poprawić',
        'Notatki',
      ],
      <List<dynamic>>[
        for (final t in items)
          <dynamic>[
            first10(_s(t['date'])),
            _s(t['kind']) == 'club_training' ? 'Klubowy' : 'Własny',
            _s(t['focus']),
            _i(t['duration_min']),
            intensityLabel(_s(t['intensity'])),
            _i(t['rating']),
            t['went_well'],
            t['to_improve'],
            t['notes'],
          ],
      ],
    );
  }

  /// Mecze w CSV.
  static Future<String> exportMatchesCsv() async {
    final items = _sortedBy(await LocalDb.list('matches'), 'date');
    return _csvDoc(
      <String>[
        'Data',
        'Przeciwnik',
        'Wynik',
        'Minuty',
        'Gole',
        'Asysty',
        'Ocena (1-5)',
        'Co było dobrze',
        'Co trzeba poprawić',
        'Notatki',
      ],
      <List<dynamic>>[
        for (final m in items)
          <dynamic>[
            first10(_s(m['date'])),
            m['opponent'],
            m['result'],
            _i(m['minutes_played']),
            _i(m['goals']),
            _i(m['assists']),
            _i(m['rating']),
            m['went_well'],
            m['to_improve'],
            m['notes'],
          ],
      ],
    );
  }

  static Future<void> deleteTraining(String id) async {
    await LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list('trainings');
      if (!items.any((e) => e['id'] == id)) throw ApiException(404, 'Not Found', 'Training not found');
      items.removeWhere((e) => e['id'] == id);
      final events = await LocalDb.list('events');
      events.removeWhere((e) => e['source_id'] == id);
      await LocalDb.saveList('trainings', items);
      await LocalDb.saveList('events', events);
    });
  }

  // ---------------- Mecze ----------------
  static Future<List<MatchEntry>> listMatches() async {
    final items = await LocalDb.list('matches');
    return _sortedBy(
      items,
      'date',
      desc: true,
    ).map(MatchEntry.fromJson).toList();
  }

  static Future<MatchEntry> createMatch({
    required String date,
    required String opponent,
    required String result,
    required int minutesPlayed,
    required int goals,
    required int assists,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
    String? plannedEventId,
    /// True, gdy zapisujemy przyszły plan (Kalendarz → Dodaj), a nie
    /// wykonaną już aktywność. Dzisiejsze planowane mecze nie są
    /// oznaczane jako wykonane.
    bool isPlanned = false,
  }) async {
    _validateActivityDate(date, isPlanned: isPlanned);
    _check(
      minutesPlayed >= 0 && minutesPlayed <= 180,
      'minutes_played must be between 0 and 180',
    );
    _check(goals >= 0 && goals <= 20, 'goals must be between 0 and 20');
    _check(assists >= 0 && assists <= 20, 'assists must be between 0 and 20');
    _check(rating >= 1 && rating <= 5, 'rating must be between 1 and 5');
    final doc = <String, dynamic>{
      'id': LocalDb.newId(),
      'date': date,
      'opponent': opponent,
      'result': result,
      'minutes_played': minutesPlayed,
      'goals': goals,
      'assists': assists,
      'rating': rating,
      'went_well': wentWell,
      'to_improve': toImprove,
      'notes': notes,
      'created_at': _nowIso(),
    };
    if (isPlanned) {
      final planDetails = <String>[
        'Rywal: $opponent',
        if (result.trim().isNotEmpty) 'Wynik: $result',
        'Minuty: $minutesPlayed',
        'Bramki: $goals',
        'Asysty: $assists',
        'Planowana ocena: $rating/5',
        if (wentWell.trim().isNotEmpty) 'Co było dobrze: $wentWell',
        if (toImprove.trim().isNotEmpty) 'Do poprawy: $toImprove',
        if (notes.trim().isNotEmpty) 'Notatka: $notes',
      ].join('\n');
      await createEvent(
        date: date,
        type: 'match',
        title: opponent.trim().isEmpty ? 'Mecz' : 'Mecz z $opponent',
        details: <String, dynamic>{'opponent': opponent, 'result': result, 'minutes_played': minutesPlayed, 'goals': goals, 'assists': assists, 'rating': rating, 'went_well': wentWell, 'to_improve': toImprove, 'notes': notes},
        description: planDetails,
      );
      return MatchEntry.fromJson(doc);
    }
    return LocalDb.synchronized<MatchEntry>(() async {
      List<Map<String, dynamic>>? events;
      var eventIndex = -1;
      if (plannedEventId != null && plannedEventId.isNotEmpty) {
        events = await LocalDb.list('events');
        eventIndex = events.indexWhere((e) => _s(e['id']) == plannedEventId);
        if (eventIndex < 0) {
          throw ApiException(404, 'Not Found',
              'Nie znaleziono zaplanowanego meczu w kalendarzu.');
        }
        final planned = events[eventIndex];
        final linkedId = _s(planned['source_id']);
        if (linkedId.isNotEmpty || planned['done'] == true) {
          if (_s(planned['source']) == 'matches' && linkedId.isNotEmpty) {
            final saved = await LocalDb.list('matches');
            for (final item in saved) {
              if (_s(item['id']) == linkedId) {
                return MatchEntry.fromJson(item);
              }
            }
          }
          throw ApiException(409, 'Conflict',
              'Ten mecz jest już zapisany jako wykonany. Otwórz jego edycję.');
        }
        if (_s(planned['type']) != 'match') {
          throw ApiException(409, 'Conflict',
              'Wybrane wydarzenie nie jest meczem.');
        }
      }
      final items = await LocalDb.list('matches');
      items.add(doc);
      await LocalDb.saveList('matches', items);
      final linked = _eventForMatch(doc);
      if (events != null) {
        final planned = events[eventIndex];
        events[eventIndex] = <String, dynamic>{
          ...planned,
          ..._completedEventFields(linked),
          'done': true,
          'source': 'matches',
          'source_id': doc['id'],
          'planned_source': _s(planned['source']),
        };
        await LocalDb.saveList('events', events);
      } else {
        await _addLinkedEvent(linked);
      }
      return MatchEntry.fromJson(doc);
    });
  }

  static Future<void> deleteMatch(String id) async {
    await _deleteFrom('matches', id, 'Match not found');
    await _deleteLinkedEvents(id);
  }

  // ---------------- Kalendarz ----------------
  /// Jednorazowa synchronizacja przy uruchomieniu lub zmianie profilu.
  static Future<void> synchronizeCalendar() async {
    await LocalDb.synchronized<void>(() async {
        // Uzupełnia kalendarz o treningi i mecze zapisane wcześniej
        // w dzienniku (zanim powstało powiązanie z kalendarzem).
        final events = await LocalDb.list('events');
        final linked = events.map((e) => _s(e['source_id'])).toSet();
        final hiddenDoc = await LocalDb.getDoc('hidden_calendar_links');
        final hidden = (hiddenDoc?['ids'] as List?)?.map(_s).toSet() ?? <String>{};
        var changed = false;
        for (final t in await LocalDb.list('trainings')) {
          if (!linked.contains(_s(t['id'])) && !hidden.contains(_s(t['id']))) {
            events.add(_eventForTraining(t));
            changed = true;
          }
        }
        for (final m in await LocalDb.list('matches')) {
          if (!linked.contains(_s(m['id'])) && !hidden.contains(_s(m['id']))) {
            events.add(_eventForMatch(m));
            changed = true;
          }
        }
        if (await _syncClubEvents(events)) changed = true;
        if (changed) await LocalDb.saveList('events', events);
    });
  }

  /// Odczyt nie zmienia stanu aplikacji.
  static Future<List<EventItem>> listEvents() async {
    final items = await LocalDb.list('events');
    return _sortedBy(items, 'date').map(EventItem.fromJson).toList();
  }

  /// Ile tygodni do przodu dodawać treningi klubowe.
  static const int _clubWeeksAhead = 8;

  /// Dopasowuje zaplanowane treningi klubowe do dni wybranych w profilu:
  /// dodaje brakujące (od dziś na [_clubWeeksAhead] tygodni), usuwa
  /// niewykonane z dni, które odznaczono, i aktualizuje godzinę/czas.
  /// Zwraca true, jeśli lista się zmieniła. Wywoływane wewnątrz
  /// LocalDb.synchronized.
  static Future<bool> _syncClubEvents(List<Map<String, dynamic>> events) async {
    final profile = await LocalDb.getDoc('profile') ?? <String, dynamic>{};
    final days = _clubDays(profile);
    final time = _s(profile['club_time']).trim();
    final dur = _i(profile['club_duration_min']) > 0
        ? _i(profile['club_duration_min'])
        : 90;
    final skipped = (await LocalDb.getDoc('club_skipped'))?['dates'];
    final skippedSet = skipped is List ? skipped.map(_s).toSet() : <String>{};
    final today = todayIso();
    var changed = false;

    // Usuń / zaktualizuj przyszłe, niewykonane treningi klubowe.
    final before = events.length;
    events.removeWhere((e) {
      if (_s(e['source']) != 'club' || e['done'] == true) return false;
      final d = DateTime.tryParse(first10(_s(e['date'])));
      if (d == null || first10(_s(e['date'])).compareTo(today) < 0) {
        return false;
      }
      return !days.contains(d.weekday);
    });
    if (events.length != before) changed = true;
    for (final e in events) {
      if (_s(e['source']) != 'club' || e['done'] == true) continue;
      if (_s(e['time']) != time || _i(e['duration_min']) != dur) {
        e['time'] = time;
        e['duration_min'] = dur;
        changed = true;
      }
    }

    if (days.isEmpty) return changed;

    // Dodaj brakujące.
    final existing = <String>{
      for (final e in events)
        if (_s(e['type']) == 'club_training') first10(_s(e['date'])),
    };
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < _clubWeeksAhead * 7; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      if (!days.contains(d.weekday)) continue;
      final iso = dateIso(d);
      if (existing.contains(iso) || skippedSet.contains(iso)) continue;
      events.add(<String, dynamic>{
        'id': LocalDb.newId(),
        'date': iso,
        'time': time,
        'type': 'club_training',
        'title': 'Trening klubowy',
        'description': _clubDescription(profile),
        'done': false,
        'planned': true,
        'source': 'club',
        'focus': 'Trening klubowy',
        'duration_min': dur,
        'intensity': 'medium',
        'steps': planStepsFor('Trening klubowy'),
        'tip': planTipFor('Trening klubowy'),
        'created_at': _nowIso(),
      });
      changed = true;
    }
    return changed;
  }

  /// Wszystkie aktywności danego dnia (dziennik: "Dzisiejszy cel").
  /// Najpierw zaplanowane do wykonania, potem wg godziny; notatki na końcu.
  static Future<List<EventItem>> eventsForDay(String date) async {
    final all = await listEvents();
    int rank(EventItem e) => e.type == 'note' ? 2 : (e.isPending ? 0 : 1);
    return all.where((e) => first10(e.date) == first10(date)).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.time.compareTo(b.time);
      });
  }

  /// Zaplanowane, niewykonane treningi i mecze na dziś ("Dzisiejszy cel").
  static Future<List<EventItem>> todayGoals() async {
    final all = await listEvents();
    final today = todayIso();
    final list = all
        .where(
          (e) => first10(e.date) == today && e.isPending && e.type != 'note',
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  /// Dodaje dzień planu tygodnia do kalendarza jako zaplanowany trening.
  /// Zwraca false, jeśli ten dzień planu jest już w kalendarzu.
  static Future<bool> addPlanDayToCalendar(PlanDay d) {
    return LocalDb.synchronized<bool>(() async {
      final events = await LocalDb.list('events');
      final added = _addPlanDay(events, d);
      if (added) await LocalDb.saveList('events', events);
      return added;
    });
  }

  /// Dodaje cały plan tygodnia (bez dni odpoczynku i dni, które już minęły).
  /// Zwraca liczbę dodanych treningów.
  static Future<int> addPlanWeekToCalendar(WeeklyPlan plan) {
    return LocalDb.synchronized<int>(() async {
      final events = await LocalDb.list('events');
      final today = todayIso();
      var count = 0;
      for (final d in plan.days) {
        if (d.isRest || first10(d.date).compareTo(today) < 0) continue;
        if (_addPlanDay(events, d)) count++;
      }
      if (count > 0) await LocalDb.saveList('events', events);
      return count;
    });
  }

  /// Klucz dnia planu: "RRRR-MM-DD|tytuł".
  static String planKey(String date, String title) => '${first10(date)}|$title';

  /// Wydarzenia w kalendarzu utworzone z planu tygodnia (klucz: [planKey]).
  /// Obejmuje też dni planu powiązane z ręcznymi zaplanowanymi
  /// treningami/meczami użytkownika.
  ///
  /// Dodatkowo dodaje indeks wszystkich wydarzeń (niezależnie od statusu
  /// wykonania) pod kluczem `id:<id>`, żeby dni planu mogły rozpoznać
  /// powiązane wydarzenie po ID, nawet jeśli zostało oznaczone jako
  /// wykonane lub ma powtarzający się tytuł.
  static Future<Map<String, EventItem>> planEvents() async {
    final events = await LocalDb.list('events');
    final out = <String, EventItem>{
      // Treningi klubowe z kalendarza odpowiadają dniom klubowym planu.
      for (final e in events)
        if (_s(e['type']) == 'club_training')
          planKey(_s(e['date']), 'Trening klubowy'): EventItem.fromJson(e),
      for (final e in events)
        if (_fromPlan(e))
          planKey(_s(e['date']), _s(e['plan_title'])): EventItem.fromJson(e),
      // Ręczne zaplanowane treningi/mecze - powiązane z planem przez
      // plan_link (ustawiane w _addPlanDay przy już istniejącym wydarzeniu).
      for (final e in events)
        if (_isUserScheduledActivity(e))
          planKey(_s(e['date']), _s(e['title'])): EventItem.fromJson(e),
    };
    // Indeks po ID - wszystkie wydarzenia, także wykonane, żeby
    // powiązanie z planem nie zależało od statusu wykonania.
    for (final e in events) {
      out['id:${_s(e['id'])}'] = EventItem.fromJson(e);
    }
    return out;
  }

  /// Wyszukuje powiązane z planem wydarzenie kalendarza po ID.
  /// Zwraca null, gdy nie ma takiego wydarzenia.
  static EventItem? planEventById(
      Map<String, EventItem> planEvents, String id) {
    if (id.isEmpty) return null;
    return planEvents['id:$id'];
  }

  static bool _fromPlan(Map<String, dynamic> e) =>
      _s(e['source']) == 'plan' ||
      _s(e['planned_source']) == 'plan' ||
      e['plan_link'] == true;

  static bool _addPlanDay(List<Map<String, dynamic>> events, PlanDay d) {
    final key = planKey(d.date, d.title);
    final exists = events.any(
      (e) => _fromPlan(e) && planKey(_s(e['date']), _s(e['plan_title'])) == key,
    );
    if (exists) return false;

    final club = d.focus == 'Trening klubowy';

    // Jeśli w tym dniu użytkownik już zaplanował trening/mecz, nie
    // duplikujemy wpisu - powiązanie już istnieje w planie przez
    // zapisane ID wydarzeń, więc nie modyfikujemy wydarzeń ani nie
    // zliczamy ich jako nowo dodanych treningów.
    if (d.calendarEventIds.isNotEmpty) {
      return false;
    }
    if (club) {
      // W dniu treningu klubowego nie dublujemy wpisu - łączymy plan
      // z istniejącym treningiem klubowym z kalendarza.
      final idx = events.indexWhere(
        (e) =>
            _s(e['type']) == 'club_training' &&
            first10(_s(e['date'])) == first10(d.date),
      );
      if (idx >= 0) {
        final e = events[idx];
        e['plan_title'] = d.title;
        e['plan_link'] = true;
        final steps = e['steps'];
        if (steps is! List || steps.isEmpty) {
          e['steps'] = d.steps.isNotEmpty ? d.steps : planStepsFor(d.focus);
        }
        if (_s(e['tip']).isEmpty) e['tip'] = d.tip;
        return true;
      }
    }
    events.add(<String, dynamic>{
      'id': LocalDb.newId(),
      'date': first10(d.date),
      'time': '',
      'type': d.focus == 'Mecz'
          ? 'match'
          : club
              ? 'club_training'
              : 'training',
      'title': d.title,
      'plan_title': d.title,
      'description': d.description,
      'done': false,
      'planned': true,
      'source': 'plan',
      'focus': d.focus,
      'duration_min': d.durationMin,
      'intensity': d.intensity,
      'steps': d.steps.isNotEmpty ? d.steps : planStepsFor(d.focus),
      'tip': d.tip.isNotEmpty ? d.tip : planTipFor(d.focus),
      'created_at': _nowIso(),
    });
    return true;
  }

  static Map<String, dynamic> _eventForTraining(Map<String, dynamic> t) {
    final parts = <String>[
      if (_i(t['duration_min']) > 0) '${_i(t['duration_min'])} min',
      if (_s(t['intensity']) == 'low') 'intensywność niska',
      if (_s(t['intensity']) == 'medium') 'intensywność średnia',
      if (_s(t['intensity']) == 'high') 'intensywność wysoka',
      if (_i(t['rating']) > 0) 'ocena ${_i(t['rating'])}/5',
    ];
    final notes = _s(t['notes']).trim();
    final club = _s(t['kind']) == 'club_training';
    return <String, dynamic>{
      'id': LocalDb.newId(),
      'date': _s(t['date']),
      'time': '',
      'type': club ? 'club_training' : 'training',
      'title': _s(t['focus']).trim().isEmpty
          ? (club ? 'Trening klubowy' : 'Trening')
          : '${club ? 'Trening klubowy' : 'Trening'}: ${_s(t['focus'])}',
      'description': [
        parts.join(', '),
        if (notes.isNotEmpty) notes,
      ].where((x) => x.isNotEmpty).join(' - '),
      'duration_min': _i(t['duration_min']),
      'focus': _s(t['focus']),
      'focuses': _sList(t['focuses']).isNotEmpty ? _sList(t['focuses']) : _s(t['focus']).split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      'intensity': _s(t['intensity']),
      'rating': _i(t['rating']),
      'went_well': _s(t['went_well']),
      'to_improve': _s(t['to_improve']),
      'notes': _s(t['notes']),
      'done': true,
      'source': 'trainings',
      'source_id': _s(t['id']),
      'created_at': _nowIso(),
    };
  }

  static Map<String, dynamic> _eventForMatch(Map<String, dynamic> m) {
    final opponent = _s(m['opponent']).trim();
    final result = _s(m['result']).trim();
    final parts = <String>[
      if (result.isNotEmpty) 'wynik $result',
      '${_i(m['minutes_played'])} min',
      if (_i(m['goals']) > 0) 'gole: ${_i(m['goals'])}',
      if (_i(m['assists']) > 0) 'asysty: ${_i(m['assists'])}',
      if (_i(m['rating']) > 0) 'ocena ${_i(m['rating'])}/5',
    ];
    return <String, dynamic>{
      'id': LocalDb.newId(),
      'date': _s(m['date']),
      'time': '',
      'type': 'match',
      'title': opponent.isEmpty ? 'Mecz' : 'Mecz z $opponent',
      'description': parts.join(', '),
      'duration_min': _i(m['minutes_played']),
      'minutes_played': _i(m['minutes_played']),
      'opponent': _s(m['opponent']),
      'result': _s(m['result']),
      'goals': _i(m['goals']),
      'assists': _i(m['assists']),
      'rating': _i(m['rating']),
      'went_well': _s(m['went_well']),
      'to_improve': _s(m['to_improve']),
      'notes': _s(m['notes']),
      'done': true,
      'source': 'matches',
      'source_id': _s(m['id']),
      'created_at': _nowIso(),
    };
  }

  /// Wywoływane wewnątrz LocalDb.synchronized.
  static Future<void> _addLinkedEvent(Map<String, dynamic> event) async {
    final events = await LocalDb.list('events');
    events.add(event);
    await LocalDb.saveList('events', events);
  }

  static Future<void> _deleteLinkedEvents(String sourceId) {
    return LocalDb.synchronized<void>(() async {
      final events = await LocalDb.list('events');
      events.removeWhere((e) => _s(e['source_id']) == sourceId);
      await LocalDb.saveList('events', events);
    });
  }

  static Future<EventItem> createEvent({
    required String date,
    String time = '', // Brak godziny oznacza wydarzenie bez określonej godziny.
    required String type,
    required String title,
    required String description,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    _validateActivityDate(date, isPlanned: true);
    final doc = <String, dynamic>{
      ...details,
      'id': LocalDb.newId(),
      'date': date,
      'time': time,
      'type': type,
      'title': title,
      'description': description,
      'planned': type != 'note',
      'done': false,
      'created_at': _nowIso(),
    };
    await LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list('events');
      items.add(doc);
      await LocalDb.saveList('events', items);
    });
    return EventItem.fromJson(doc);
  }

  /// Edycja wydarzenia bez wpisu w dzienniku (notatka, trening z planu).
  static Future<EventItem> updateEvent(
    String id, {
    required String date,
    required String time,
    required String title,
    required String description,
    Map<String, dynamic>? details,
  }) {
    _validateActivityDate(date, isPlanned: true);
    return LocalDb.synchronized<EventItem>(() async {
      final items = await LocalDb.list('events');
      final idx = items.indexWhere((e) => e['id'] == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
      final e = items[idx];
      e['date'] = date;
      e['time'] = time;
      e['title'] = title;
      e['description'] = description;
      if (details != null) e.addAll(details);
      await LocalDb.saveList('events', items);
      return EventItem.fromJson(e);
    });
  }

  /// Edycja planu bez tworzenia wpisu wykonanego treningu w dzienniku.
  static Future<EventItem> updatePlannedActivity(
    String id, {
    required String date,
    required String title,
    required String description,
    required Map<String, dynamic> details,
  }) {
    _validateActivityDate(date, isPlanned: true);
    return LocalDb.synchronized<EventItem>(() async {
    final items = await LocalDb.list('events');
    final idx = items.indexWhere((e) => _s(e['id']) == id);
    if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
    final e = items[idx];
    if (e['done'] == true || _s(e['source_id']).isNotEmpty) {
      throw ApiException(409, 'Conflict', 'Completed activity cannot be edited as a plan');
    }
    e.addAll(details);
    e['date'] = date;
    e['title'] = title;
    e['description'] = description;
    e['planned'] = true;
    e['updated_at'] = _nowIso();
    await LocalDb.saveList('events', items);
    return EventItem.fromJson(e);
    });
  }

  static Future<EventItem> toggleEvent(String id, bool done) {
    return LocalDb.synchronized<EventItem>(() async {
      final items = await LocalDb.list('events');
      final idx = items.indexWhere((e) => e['id'] == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
      // Oznaczenie wykonania bez dziennika fałszowałoby statystyki.
      final event = items[idx];
      final linked = _s(event['source_id']).isNotEmpty &&
          (_s(event['source']) == 'trainings' || _s(event['source']) == 'matches');
      if (_s(event['type']) != 'note' && !linked) {
        throw StateError('Najpierw zapisz wykonany trening lub mecz w dzienniku.');
      }
      if (linked && !done) {
        throw StateError('Wykonanego wpisu nie można cofnąć bez usunięcia go z dziennika.');
      }
      items[idx]['done'] = done;
      await LocalDb.saveList('events', items);
      return EventItem.fromJson(items[idx]);
    });
  }

  /// Usuwa wydarzenie. Jeśli powstało z treningu lub meczu zapisanego
  /// w dzienniku, usuwa też ten wpis, żeby dziennik i kalendarz były zgodne.
  static Future<void> deleteEvent(String id, {bool deleteJournalEntry = true}) {
    return LocalDb.synchronized<void>(() async {
      final events = await LocalDb.list('events');
      final idx = events.indexWhere((e) => e['id'] == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
      final source = _s(events[idx]['source']);
      final sourceId = _s(events[idx]['source_id']);
      final isClub = _s(events[idx]['type']) == 'club_training' &&
          (source == 'club' || _s(events[idx]['planned_source']) == 'club');
      final date = first10(_s(events[idx]['date']));
      events.removeAt(idx);
      if (!deleteJournalEntry && sourceId.isNotEmpty &&
          (source == 'trainings' || source == 'matches')) {
        final old = await LocalDb.getDoc('hidden_calendar_links');
        final hidden = (old?['ids'] as List?)?.map(_s).toSet() ?? <String>{};
        hidden.add(sourceId);
        await LocalDb.setDoc('hidden_calendar_links', <String, dynamic>{'ids': hidden.toList()});
      }
      await LocalDb.saveList('events', events);
      if (isClub) {
        // Zapamiętaj, żeby trening klubowy nie wrócił automatycznie.
        final doc = await LocalDb.getDoc('club_skipped');
        final dates = doc?['dates'] is List
            ? (doc!['dates'] as List).map(_s).toSet()
            : <String>{};
        dates.add(date);
        await LocalDb.setDoc('club_skipped', <String, dynamic>{
          'dates': dates.toList(),
        });
      }
      if (deleteJournalEntry && sourceId.isNotEmpty &&
          (source == 'trainings' || source == 'matches')) {
        final items = await LocalDb.list(source);
        items.removeWhere((e) => _s(e['id']) == sourceId);
        await LocalDb.saveList(source, items);
      }
    });
  }

  static Future<void> _deleteFrom(
    String collection,
    String id,
    String notFound,
  ) {
    return LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list(collection);
      final before = items.length;
      items.removeWhere((e) => e['id'] == id);
      if (items.length == before) {
        throw ApiException(404, 'Not Found', notFound);
      }
      await LocalDb.saveList(collection, items);
    });
  }

  // ---------------- Postęp ----------------
  static Future<Progress> progress() => ProgressCalculator.calculate();

  // ---------------- Słabe punkty ----------------
  static Future<WeakSpotsPayload?> getWeakSpots() async {
    final doc = await LocalDb.getDoc('weak_spots');
    if (doc == null) return null;
    return WeakSpotsPayload.fromJson(doc);
  }

  static Future<WeakSpotsPayload> analyzeWeakSpots() async {
    final trainings = await LocalDb.list('trainings');
    final matches = await LocalDb.list('matches');

    final notes = <String>[];
    for (final t in trainings) {
      final n = _s(t['to_improve']).trim();
      if (n.isNotEmpty) {
        final club = _s(t['kind']) == 'club_training';
        notes.add('[${club ? 'Trening klubowy' : 'Trening'} '
            '${first10(_s(t['date']))}'
            '${_s(t['focus']).isNotEmpty ? ' · ${_s(t['focus'])}' : ''}] $n');
      }
    }
    for (final m in matches) {
      final n = _s(m['to_improve']).trim();
      if (n.isNotEmpty) {
        notes.add(
          '[Mecz ${first10(_s(m['date']))} vs ${_s(m['opponent'])}] $n',
        );
      }
    }

    if (notes.isEmpty) {
      final empty = <String, dynamic>{
        'weak_spots': <Map<String, dynamic>>[],
        'generated_at': _nowIso(),
        'note_count': 0,
      };
      await LocalDb.setDoc('weak_spots', empty);
      return WeakSpotsPayload.fromJson(empty);
    }

    var spots = <Map<String, dynamic>>[];

    if (Llm.enabled) {
      try {
        final last =
            notes.length > 50 ? notes.sublist(notes.length - 50) : notes;
        final prompt =
            "Przeanalizuj poniższe notatki zawodnika z pola 'Co trzeba poprawić?' "
            'i wskaż 2-5 powtarzających się słabych punktów:\n\n'
            '${last.map((n) => '- $n').join('\n')}';
        final raw = await Llm.complete(
          json: true,
          system: kWeakSpotsSystem,
          messages: <Map<String, String>>[
            <String, String>{'role': 'user', 'content': prompt},
          ],
        );
        final parsed = _extractJsonObject(raw);
        final items = parsed?['weak_spots'];
        if (items is List) {
          for (final it in items.take(5)) {
            if (it is! Map) continue;
            final insight = _s(it['insight']).trim();
            if (insight.isEmpty) continue;
            var priority = _s(it['priority']);
            if (priority != 'low' &&
                priority != 'medium' &&
                priority != 'high') {
              priority = 'medium';
            }
            spots.add(<String, dynamic>{
              'area': _orDefault(it['area'], 'Inne'),
              'insight': insight,
              'priority': priority,
            });
          }
        }
      } catch (_) {
        spots = <Map<String, dynamic>>[];
      }
    }

    if (spots.isEmpty) {
      // Wersja offline - zliczanie słów kluczowych.
      final tally = <String, int>{};
      void bump(String k) => tally[k] = (tally[k] ?? 0) + 1;
      for (final n in notes) {
        final l = n.toLowerCase();
        if (l.contains('strzał') || l.contains('strzelić')) bump('Strzał');
        if (l.contains('podani') ||
            l.contains('przyj') ||
            l.contains('prowadz')) {
          bump('Technika');
        }
        if (l.contains('decyzj') ||
            l.contains('ustaw') ||
            l.contains('pole widzenia')) {
          bump('Taktyka');
        }
        if (l.contains('sił') || l.contains('wytrzym') || l.contains('szybk')) {
          bump('Motoryka');
        }
        if (l.contains('koncentr') ||
            l.contains('ner') ||
            l.contains('pewno')) {
          bump('Mentalność');
        }
      }
      final order = tally.keys.toList();
      final sorted = List<String>.from(order)
        ..sort((a, b) {
          final c = tally[b]!.compareTo(tally[a]!);
          return c != 0 ? c : order.indexOf(a).compareTo(order.indexOf(b));
        });
      for (final area in sorted.take(5)) {
        final count = tally[area]!;
        spots.add(<String, dynamic>{
          'area': area,
          'insight':
              'Notatki wskazują na powtarzający się temat: ${area.toLowerCase()} ($count wpisów). Dołóż ćwiczenia rozwijające ten obszar.',
          'priority': count < 3 ? 'medium' : 'high',
        });
      }
    }

    final payload = <String, dynamic>{
      'weak_spots': spots,
      'generated_at': _nowIso(),
      'note_count': notes.length,
    };
    await LocalDb.setDoc('weak_spots', payload);
    return WeakSpotsPayload.fromJson(payload);
  }

  // ---------------- Profil ----------------
  static Future<Profile> getProfile() async {
    final doc = await LocalDb.getDoc('profile');
    if (doc == null) {
      return Profile.fromJson(<String, dynamic>{
        'name': '',
        'age': null,
        'position': '',
        'dominant_foot': '',
        'club': '',
        'jersey_number': null,
        'season_goal': '',
        'theme': 'dark',
        'updated_at': _nowIso(),
      });
    }
    return Profile.fromJson(doc);
  }

  static Future<Profile> updateProfile(Profile p) async {
    final data = p.toJson();
    data['updated_at'] = _nowIso();
    await LocalDb.setDoc('profile', data);
    await synchronizeCalendar();
    return Profile.fromJson(data);
  }

  // ---------------- Trener ----------------
  static Future<List<Drill>> drills() async {
    return kDrills.map(Drill.fromJson).toList();
  }

  /// Motywacja dnia (zmienia się codziennie).
  static Future<String> motivation() async {
    final now = DateTime.now();
    final ordinal = DateTime.utc(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime.utc(1, 1, 1)).inDays +
        1;
    return kMotivations[ordinal % kMotivations.length];
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

    if (Llm.enabled) {
      try {
        var prompt = 'Zawodnik: '
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
            ..writeln('Zaplanowane przez zawodnika w kalendarzu (PRIORYTET - te dni są zajęte):');
          for (final entry in scheduled.entries) {
            for (final e in entry.value) {
              final type = _s(e['type']);
              final label = type == 'match'
                  ? 'Mecz'
                  : type == 'club_training'
                      ? 'Trening klubowy'
                      : 'Trening';
              final time = _s(e['time']);
              final dur = _i(e['duration_min']) > 0 ? '${_i(e['duration_min'])} min' : 'brak danych';
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
                  'steps puste (zostanie uzupełnione automatycznie).');
            }
          }
          b.writeln('Te wydarzenia mają pierwszeństwo nad pozostałymi zasadami.');
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
          if (built.length == 7) days = built;
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
        if (_s(day['focus']) == 'Odpoczynek' || _clubDays(profile).contains(i + 1)) continue;
        final area = priorities[i % priorities.length];
        final matching = library.where((e) => _s(e['area']).toLowerCase() == area).toList();
        if (matching.isEmpty) continue;
        final exercise = matching[(week.monday.day + i) % matching.length];
        day['title'] = _s(exercise['title']);
        day['focus'] = _s(exercise['area']);
        day['duration_min'] = _i(exercise['duration_min']).clamp(10, 60);
        day['intensity'] = _s(exercise['intensity']);
        day['description'] = _s(exercise['goal']);
        day['steps'] = (exercise['steps'] as List?)?.map(_s).toList() ?? <String>[];
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
    };
    await LocalDb.setDoc('weekly_plan_${week.id}', plan);
    return WeeklyPlan.fromJson(plan);
  }

  /// Wysyła wiadomość do trenera i zwraca odpowiedź
  /// (model AI, a bez klucza - odpowiedź offline).
  /// Dane zawodnika dla trenera AI: profil, ostatnie treningi (także
  /// klubowe) i mecze z ocenami i notatkami oraz najbliższe plany.
  static Future<String> _playerContext() async {
    final profile = await LocalDb.getDoc('profile') ?? <String, dynamic>{};
    final trainings =
        _sortedBy(await LocalDb.list('trainings'), 'date', desc: true);
    final matches =
        _sortedBy(await LocalDb.list('matches'), 'date', desc: true);
    final events = await LocalDb.list('events');
    String clip(dynamic v) {
      final t = _s(v).trim().replaceAll('\n', ' ');
      return t.length > 300 ? '${t.substring(0, 300)}...' : t;
    }

    final b = StringBuffer()
      ..writeln(
          'DANE ZAWODNIKA (z aplikacji - odnoś się do nich, gdy to pomocne; '
          'nie wymyślaj wpisów, których tu nie ma):')
      ..writeln('Profil: wiek=${_orDefault(profile['age'], '-')}, '
          'pozycja=${_orDefault(profile['position'], '-')}, '
          'noga=${_orDefault(profile['dominant_foot'], '-')}, '
          'cel sezonu=${_orDefault(profile['season_goal'], '-')}. '
          'Treningi klubowe: ${_clubDays(profile).isEmpty ? 'brak' : (_clubDays(profile).toList()..sort()).map((d) => kPolishDays[d - 1]).join(', ')}.')
      ..writeln('Dzisiaj: ${todayIso()}.');

    final lastT = trainings.take(12).toList();
    b.writeln(lastT.isEmpty
        ? 'Treningi: brak zapisanych.'
        : 'Ostatnie treningi (od najnowszego):');
    for (final t in lastT) {
      final club = _s(t['kind']) == 'club_training';
      b.writeln(
          '- ${first10(_s(t['date']))} ${club ? 'TRENING KLUBOWY' : 'trening własny'}'
          '${_s(t['focus']).isNotEmpty ? ' (${_s(t['focus'])})' : ''}, '
          '${_i(t['duration_min'])} min, intensywność ${_s(t['intensity'])}, '
          'ocena ${_i(t['rating'])}/5'
          '${clip(t['went_well']).isNotEmpty ? '; dobrze: ${clip(t['went_well'])}' : ''}'
          '${clip(t['to_improve']).isNotEmpty ? '; do poprawy: ${clip(t['to_improve'])}' : ''}'
          '${clip(t['notes']).isNotEmpty ? '; notatki: ${clip(t['notes'])}' : ''}');
    }
    final lastM = matches.take(6).toList();
    if (lastM.isNotEmpty) b.writeln('Ostatnie mecze:');
    for (final m in lastM) {
      b.writeln(
          '- ${first10(_s(m['date']))} vs ${_orDefault(m['opponent'], '?')}'
          '${_s(m['result']).isNotEmpty ? ' wynik ${_s(m['result'])}' : ''}, '
          '${_i(m['minutes_played'])} min, gole ${_i(m['goals'])}, asysty ${_i(m['assists'])}, '
          'ocena ${_i(m['rating'])}/5'
          '${clip(m['went_well']).isNotEmpty ? '; dobrze: ${clip(m['went_well'])}' : ''}'
          '${clip(m['to_improve']).isNotEmpty ? '; do poprawy: ${clip(m['to_improve'])}' : ''}'
          '${clip(m['notes']).isNotEmpty ? '; notatki: ${clip(m['notes'])}' : ''}');
    }
    final today = todayIso();
    final upcoming = events
        .where((e) =>
            first10(_s(e['date'])).compareTo(today) >= 0 && e['done'] != true)
        .toList()
      ..sort((a, b) => _s(a['date']).compareTo(_s(b['date'])));
    final next = upcoming.take(6).toList();
    if (next.isNotEmpty) b.writeln('Najbliższe w kalendarzu:');
    for (final e in next) {
      b.writeln(
          '- ${first10(_s(e['date']))}${_s(e['time']).isNotEmpty ? ' ${_s(e['time'])}' : ''} '
          '${_s(e['type'])}: ${_s(e['title'])}');
    }
    return b.toString();
  }

  static Future<String> chat(String sessionId, String message) async {
    final all = await LocalDb.list('chat_messages');
    final session = all.where((m) => m['session_id'] == sessionId).toList();

    String reply;
    if (Llm.enabled) {
      final recent =
          session.length > 20 ? session.sublist(session.length - 20) : session;
      final context = await _playerContext();
      try {
        reply = await Llm.complete(
          system: '$kCoachSystem\n\n$context',
          messages: <Map<String, String>>[
            for (final m in recent)
              <String, String>{
                'role': _s(m['role']),
                'content': _s(m['content']),
              },
            <String, String>{'role': 'user', 'content': message},
          ],
        );
      } catch (e) {
        reply = await OfflineCoach.reply(message);
      }
    } else {
      reply = await OfflineCoach.reply(message);
    }

    await LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list('chat_messages');
      items.add(<String, dynamic>{
        'id': LocalDb.newId(),
        'session_id': sessionId,
        'role': 'user',
        'content': message,
        'created_at': _nowIso(),
      });
      items.add(<String, dynamic>{
        'id': LocalDb.newId(),
        'session_id': sessionId,
        'role': 'assistant',
        'content': reply,
        'created_at': _nowIso(),
      });
      final trimmed =
          items.length > 200 ? items.sublist(items.length - 200) : items;
      await LocalDb.saveList('chat_messages', trimmed);
    });
    return reply;
  }
}
