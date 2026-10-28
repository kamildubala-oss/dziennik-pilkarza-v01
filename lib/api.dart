import 'dart:convert';

import 'coach_content.dart';
import 'llm.dart';
import 'offline_coach.dart';
import 'local_db.dart';
import 'models.dart';
import 'utils.dart';
import 'services/progress_calculator.dart';
import 'services/coach_runtime.dart';
import 'services/progress_report.dart';

part 'repositories/training_repo.dart';
part 'repositories/calendar_repo.dart';
part 'services/plan_service.dart';
part 'services/coach_service.dart';
part 'services/recovery_service.dart';
part 'repositories/backup_service.dart';

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
  if (!const {'training', 'club_training', 'match', 'recovery'}.contains(_s(e['type']))) {
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
  static Future<List<Training>> listTrainings() => TrainingRepo.listTrainings();

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
  }) => TrainingRepo.createTraining(date: date, durationMin: durationMin, focuses: focuses, intensity: intensity, rating: rating, wentWell: wentWell, toImprove: toImprove, notes: notes, kind: kind, plannedEventId: plannedEventId, isPlanned: isPlanned);

  static Future<Training?> getTraining(String id) => TrainingRepo.getTraining(id);

  static Future<MatchEntry?> getMatch(String id) => TrainingRepo.getMatch(id);

  /// Pola wykonania w kalendarzu są projekcją rzeczywistego wpisu
  /// w dzienniku. Nie kopiujemy ID wydarzenia ani godziny planu.
  static Map<String, dynamic> _completedEventFields(Map<String, dynamic> linked) {
    const fields = <String>[
      'date', 'title', 'description', 'type', 'duration_min',
      'focus', 'focuses', 'intensity', 'rating',
      'opponent', 'result', 'minutes_played', 'goals', 'assists',
      'went_well', 'to_improve', 'notes', 'steps', 'recovery_plan',
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
  }) => TrainingRepo.updateTraining(id, date: date, durationMin: durationMin, focuses: focuses, intensity: intensity, rating: rating, wentWell: wentWell, toImprove: toImprove, notes: notes);

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
  }) => TrainingRepo.updateMatch(id, date: date, opponent: opponent, result: result, minutesPlayed: minutesPlayed, goals: goals, assists: assists, rating: rating, wentWell: wentWell, toImprove: toImprove, notes: notes);

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
  }) => TrainingRepo.rateClubTraining(e, focuses: focuses, rating: rating, wentWell: wentWell, toImprove: toImprove, notes: notes);

  // ---------------------------------------------------------------------
  // Eksport i kopia zapasowa
  // ---------------------------------------------------------------------

  static const String _backupApp = 'dziennik_pilkarza';

  /// Pełna kopia zapasowa (JSON) - do przywrócenia na tym lub innym telefonie.
  static Future<String> exportBackup() => BackupService.exportBackup();

  /// Sprawdza plik kopii i zwraca liczbę treningów/meczów/wydarzeń.
  /// Rzuca [ApiException], gdy plik nie jest kopią z tej aplikacji.
  static Map<String, int> inspectBackup(String json) => BackupService.inspectBackup(json);

  /// Przywraca dane z kopii (zastępuje obecne dane w aplikacji).
  static Future<void> importBackup(String json) => BackupService.importBackup(json);

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
  static Future<String> exportTrainingsCsv() => BackupService.exportTrainingsCsv();

  /// Mecze w CSV.
  static Future<String> exportMatchesCsv() => BackupService.exportMatchesCsv();

  static Future<void> deleteTraining(String id) => TrainingRepo.deleteTraining(id);

  // ---------------- Mecze ----------------
  static Future<List<MatchEntry>> listMatches() => TrainingRepo.listMatches();

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
  }) => TrainingRepo.createMatch(date: date, opponent: opponent, result: result, minutesPlayed: minutesPlayed, goals: goals, assists: assists, rating: rating, wentWell: wentWell, toImprove: toImprove, notes: notes, plannedEventId: plannedEventId, isPlanned: isPlanned);

  static Future<void> deleteMatch(String id) => TrainingRepo.deleteMatch(id);

  // ---------------- Kalendarz ----------------
  /// Jednorazowa synchronizacja przy uruchomieniu lub zmianie profilu.
  static Future<void> synchronizeCalendar() => CalendarRepo.synchronizeCalendar();

  /// Odczyt nie zmienia stanu aplikacji.
  static Future<List<EventItem>> listEvents() => CalendarRepo.listEvents();

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
      if (_s(e['source']) != 'club' || e['done'] == true ||
          e['club_override'] == true) return false;
      final d = DateTime.tryParse(first10(_s(e['date'])));
      if (d == null || first10(_s(e['date'])).compareTo(today) < 0) {
        return false;
      }
      return !days.contains(d.weekday);
    });
    if (events.length != before) changed = true;
    for (final e in events) {
      if (_s(e['source']) != 'club' || e['done'] == true ||
          e['club_override'] == true) continue;
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
  static Future<List<EventItem>> eventsForDay(String date) => CalendarRepo.eventsForDay(date);

  /// Zaplanowane, niewykonane treningi i mecze na dziś ("Dzisiejszy cel").
  static Future<List<EventItem>> todayGoals() => CalendarRepo.todayGoals();

  /// Dodaje dzień planu tygodnia do kalendarza jako zaplanowany trening.
  /// Zwraca false, jeśli ten dzień planu jest już w kalendarzu.
  static Future<bool> addPlanDayToCalendar(PlanDay d) => PlanService.addPlanDayToCalendar(d);

  /// Dodaje cały plan tygodnia (bez dni odpoczynku i dni, które już minęły).
  /// Zwraca liczbę dodanych treningów.
  static Future<int> addPlanWeekToCalendar(WeeklyPlan plan) => PlanService.addPlanWeekToCalendar(plan);

  /// Klucz dnia planu: "RRRR-MM-DD|tytuł".
  static String planKey(String date, String title) => PlanService.planKey(date, title);

  /// Wydarzenia w kalendarzu utworzone z planu tygodnia (klucz: [planKey]).
  /// Obejmuje też dni planu powiązane z ręcznymi zaplanowanymi
  /// treningami/meczami użytkownika.
  ///
  /// Dodatkowo dodaje indeks wszystkich wydarzeń (niezależnie od statusu
  /// wykonania) pod kluczem `id:<id>`, żeby dni planu mogły rozpoznać
  /// powiązane wydarzenie po ID, nawet jeśli zostało oznaczone jako
  /// wykonane lub ma powtarzający się tytuł.
  static Future<Map<String, EventItem>> planEvents() => PlanService.planEvents();

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
      'type': d.focus == 'Regeneracja' ? 'recovery' : d.focus == 'Mecz'
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
    if (t['kind'] == 'recovery') {
      final plan = t['recovery_plan'] is Map ? Map<String, dynamic>.from(t['recovery_plan'] as Map) : <String, dynamic>{};
      return {'id': LocalDb.newId(), 'date': _s(t['date']), 'time': '', 'type': 'recovery',
        'title': 'Regeneracja: ${_orDefault(plan['title'], 'Aktywny odpoczynek')}',
        'description': _s(plan['description']), 'duration_min': _i(t['duration_min']),
        'focus': 'Regeneracja', 'intensity': 'low', 'steps': RecoveryService.steps(plan),
        'recovery_plan': plan, 'done': true, 'source': 'trainings', 'source_id': _s(t['id']), 'created_at': _nowIso()};
    }
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
  }) => CalendarRepo.createEvent(date: date, time: time, type: type, title: title, description: description, details: details);

  /// Edycja wydarzenia bez wpisu w dzienniku (notatka, trening z planu).
  static Future<EventItem> updateEvent(
    String id, {
    required String date,
    required String time,
    required String title,
    required String description,
    Map<String, dynamic>? details,
  }) => CalendarRepo.updateEvent(id, date: date, time: time, title: title, description: description, details: details);

  /// Edycja planu bez tworzenia wpisu wykonanego treningu w dzienniku.
  static Future<EventItem> updatePlannedActivity(
    String id, {
    required String date,
    required String title,
    required String description,
    required Map<String, dynamic> details,
  }) => CalendarRepo.updatePlannedActivity(id, date: date, title: title, description: description, details: details);

  static Future<EventItem> toggleEvent(String id, bool done) => CalendarRepo.toggleEvent(id, done);

  /// Usuwa wydarzenie. Jeśli powstało z treningu lub meczu zapisanego
  /// w dzienniku, usuwa też ten wpis, żeby dziennik i kalendarz były zgodne.
  static Future<void> deleteEvent(String id, {bool deleteJournalEntry = true}) => CalendarRepo.deleteEvent(id, deleteJournalEntry: deleteJournalEntry);

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
  static Future<WeakSpotsPayload?> getWeakSpots() => CoachService.getWeakSpots();

  static Future<WeakSpotsPayload> analyzeWeakSpots() => CoachService.analyzeWeakSpots();

  // ---------------- Profil ----------------
  static Future<Profile> getProfile() => CoachService.getProfile();

  static Future<Profile> updateProfile(Profile p) => CoachService.updateProfile(p);

  // ---------------- Trener ----------------
  static Future<List<Drill>> drills() => CoachService.drills();

  /// Motywacja dnia (zmienia się codziennie).
  static Future<String> motivation() => CoachService.motivation();

  static Future<WeeklyPlan?> getWeeklyPlan() => PlanService.getWeeklyPlan();

  static Future<WeeklyPlan> generateWeeklyPlan() => PlanService.generateWeeklyPlan();

  /// Wysyła wiadomość do trenera i zwraca odpowiedź
  /// (model AI, a bez klucza - odpowiedź offline).
  /// Dane zawodnika dla trenera AI: profil, ostatnie treningi (także
  /// klubowe) i mecze z ocenami i notatkami oraz najbliższe plany.
  static Future<Map<String, dynamic>> generateRecovery(String date, int minutes) => RecoveryService.generate(date, minutes);
  static Future<Map<String, dynamic>?> recoveryRecord(String id) => RecoveryService.record(id);
  static Future<EventItem> saveRecovery(Map<String, dynamic> plan,
    {String? eventId, String? trainingId, bool complete = false}) =>
      RecoveryService.save(plan, eventId: eventId, trainingId: trainingId, complete: complete);

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
          '- ${first10(_s(t['date']))} ${t['kind'] == 'recovery' ? 'REGENERACJA' : club ? 'TRENING KLUBOWY' : 'trening własny'}'
          '${_s(t['focus']).isNotEmpty ? ' (${_s(t['focus'])})' : ''}, '
          '${_i(t['duration_min'])} min, intensywność ${_s(t['intensity'])}, '
          '${_i(t['rating']) > 0 ? 'ocena ${_i(t['rating'])}/5' : 'bez oceny'}'
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
          '${_i(m['rating']) > 0 ? 'ocena ${_i(m['rating'])}/5' : 'bez oceny'}'
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

  static Future<String> chat(String sessionId, String message) => CoachService.chat(sessionId, message);
}

