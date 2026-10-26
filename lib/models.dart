// Modele danych - odpowiadają typom z `src/api.ts` oraz modelom Pydantic backendu.

int _asInt(dynamic v, [int def = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

int? _asIntOrNull(dynamic v) => v is num ? v.toInt() : null;

double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

String _asString(dynamic v) => v == null ? '' : v.toString();

bool _asBool(dynamic v) => v == true;

List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

List<int> _asIntList(dynamic v) =>
    v is List ? v.map((e) => _asInt(e)).toList() : <int>[];

Map<String, int> _asIntMap(dynamic v) {
  final out = <String, int>{};
  if (v is Map) {
    v.forEach((key, value) {
      out[key.toString()] = _asInt(value);
    });
  }
  return out;
}

class Training {
  const Training({
    required this.id,
    required this.date,
    required this.durationMin,
    required this.focus,
    required this.intensity,
    required this.rating,
    required this.wentWell,
    required this.toImprove,
    required this.notes,
    required this.kind,
    required this.createdAt,
    this.focuses = const <String>[],
  });

  final String id;
  final String date;
  final int durationMin;

  /// Obszary treningu połączone przecinkiem (np. "Prowadzenie, Strzał").
  final String focus;

  /// Lista obszarów, nad którymi pracował zawodnik.
  final List<String> focuses;
  final String intensity; // low | medium | high
  /// 0 oznacza brak samooceny; wystawione oceny mają zakres 1–5.
  final int rating;
  final String wentWell;
  final String toImprove;
  final String notes;
  final String kind; // training | club_training
  final String createdAt;

  bool get isClub => kind == 'club_training';

  factory Training.fromJson(Map<String, dynamic> j) => Training(
        id: _asString(j['id']),
        date: _asString(j['date']),
        durationMin: _asInt(j['duration_min']),
        focus: _asString(j['focus']),
        focuses: _asStringList(j['focuses']).isNotEmpty
            ? _asStringList(j['focuses'])
            : _asString(j['focus'])
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
        intensity: _asString(j['intensity']),
        rating: _asInt(j['rating'], 0),
        wentWell: _asString(j['went_well']),
        toImprove: _asString(j['to_improve']),
        notes: _asString(j['notes']),
        kind: _asString(j['kind']),
        createdAt: _asString(j['created_at']),
      );
}

class MatchEntry {
  const MatchEntry({
    required this.id,
    required this.date,
    required this.opponent,
    required this.result,
    required this.minutesPlayed,
    required this.goals,
    required this.assists,
    required this.rating,
    required this.wentWell,
    required this.toImprove,
    required this.notes,
    required this.createdAt,
  });

  final String id;
  final String date;
  final String opponent;
  final String result;
  final int minutesPlayed;
  final int goals;
  final int assists;
  /// 0 oznacza brak samooceny; wystawione oceny mają zakres 1–5.
  final int rating;
  final String wentWell;
  final String toImprove;
  final String notes;
  final String createdAt;

  factory MatchEntry.fromJson(Map<String, dynamic> j) => MatchEntry(
        id: _asString(j['id']),
        date: _asString(j['date']),
        opponent: _asString(j['opponent']),
        result: _asString(j['result']),
        minutesPlayed: _asInt(j['minutes_played']),
        goals: _asInt(j['goals']),
        assists: _asInt(j['assists']),
        rating: _asInt(j['rating'], 0),
        wentWell: _asString(j['went_well']),
        toImprove: _asString(j['to_improve']),
        notes: _asString(j['notes']),
        createdAt: _asString(j['created_at']),
      );
}

class EventItem {
  const EventItem({
    required this.id,
    required this.date,
    required this.time,
    required this.type,
    required this.title,
    required this.description,
    required this.done,
    required this.createdAt,
    this.planned = false,
    this.source = '',
    this.sourceId = '',
    this.focus = '',
    this.durationMin = 0,
    this.intensity = '',
    this.steps = const <String>[],
    this.tip = '',
    this.plannedSource = '',
    this.details = const <String, dynamic>{},
  });

  final String id;
  final String date;
  final String time;
  final String type; // training | club_training | match | note
  final String title;
  final String description;
  final bool done;
  final String createdAt;

  /// Zaplanowany trening (z planu tygodnia lub trening klubowy).
  final bool planned;

  /// Pochodzenie: trainings | matches | plan | club | '' (ręcznie).
  final String source;
  final String sourceId;
  final String focus;
  final int durationMin;
  final String intensity;
  final List<String> steps;
  final String tip;

  /// Oryginalne źródło przed wykonaniem (np. 'plan', 'club').
  final String plannedSource;
  final Map<String, dynamic> details;

  bool get isTrainingType => type == 'training' || type == 'club_training';

  /// Zaplanowany i jeszcze niewykonany.
  bool get isPending => planned && !done;

  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
        id: _asString(j['id']),
        date: _asString(j['date']),
        time: _asString(j['time']),
        type: _asString(j['type']),
        title: _asString(j['title']),
        description: _asString(j['description']),
        done: _asBool(j['done']),
        createdAt: _asString(j['created_at']),
        planned: _asBool(j['planned']),
        source: _asString(j['source']),
        sourceId: _asString(j['source_id']),
        focus: _asString(j['focus']),
        durationMin: _asInt(j['duration_min']),
        intensity: _asString(j['intensity']),
        steps: _asStringList(j['steps']),
        tip: _asString(j['tip']),
        plannedSource: _asString(j['planned_source']),
        details: Map<String, dynamic>.from(j),
      );
}

class Drill {
  const Drill({
    required this.id,
    required this.title,
    required this.focus,
    required this.durationMin,
    required this.intensity,
    required this.source,
    required this.description,
    required this.steps,
  });

  final String id;
  final String title;
  final String focus;
  final int durationMin;
  final String intensity;
  final String source;
  final String description;
  final List<String> steps;

  factory Drill.fromJson(Map<String, dynamic> j) {
    final rawSteps = j['steps'];
    return Drill(
      id: _asString(j['id']),
      title: _asString(j['title']),
      focus: _asString(j['focus']),
      durationMin: _asInt(j['duration_min']),
      intensity: _asString(j['intensity']),
      source: _asString(j['source']),
      description: _asString(j['description']),
      steps: rawSteps is List
          ? rawSteps.map((e) => e.toString()).toList()
          : <String>[],
    );
  }
}

class PlanDay {
  const PlanDay({
    required this.date,
    required this.dayName,
    required this.focus,
    required this.title,
    required this.durationMin,
    required this.intensity,
    required this.description,
    this.steps = const <String>[],
    this.tip = '',
    this.calendarEventIds = const <String>[],
    this.extraEventIds = const <String>[],
  });

  final String date;
  final String dayName;
  final String focus;
  final String title;
  final int durationMin;
  final String intensity;
  final String description;

  /// Konkretne ćwiczenia krok po kroku.
  final List<String> steps;

  /// Wskazówka trenera.
  final String tip;

  /// ID zaplanowanych przez użytkownika wydarzeń w kalendarzu (pierwsza
  /// pozycja to wydarzenie główne, kolejne - dodatkowe).
  final List<String> calendarEventIds;

  /// Pozostałe wydarzenia tego dnia (poza głównym).
  final List<String> extraEventIds;

  bool get isRest => focus == 'Odpoczynek';

  factory PlanDay.fromJson(Map<String, dynamic> j) => PlanDay(
        date: _asString(j['date']),
        dayName: _asString(j['day_name']),
        focus: _asString(j['focus']),
        title: _asString(j['title']),
        durationMin: _asInt(j['duration_min']),
        intensity: _asString(j['intensity']),
        description: _asString(j['description']),
        steps: _asStringList(j['steps']),
        tip: _asString(j['tip']),
        calendarEventIds: _asStringList(j['calendar_event_ids']),
        extraEventIds: _asStringList(j['extra_event_ids']),
      );
}

class WeeklyPlan {
  const WeeklyPlan({
    required this.id,
    required this.weekStart,
    required this.days,
    required this.generatedAt,
    this.source = '',
    this.notice = '',
  });

  final String id;
  final String weekStart;
  final List<PlanDay> days;
  final String generatedAt;
  final String source;
  final String notice;

  factory WeeklyPlan.fromJson(Map<String, dynamic> j) {
    final rawDays = j['days'];
    return WeeklyPlan(
      id: _asString(j['id']),
      weekStart: _asString(j['week_start']),
      days: rawDays is List
          ? rawDays
              .map((e) => PlanDay.fromJson(e as Map<String, dynamic>))
              .toList()
          : <PlanDay>[],
      generatedAt: _asString(j['generated_at']),
      source: _asString(j['source']),
      notice: _asString(j['fallback_reason']),
    );
  }
}

class Progress {
  const Progress({
    required this.totalTrainings,
    required this.totalMatches,
    required this.totalMinutes,
    required this.totalGoals,
    required this.totalAssists,
    required this.streakDays,
    required this.avgRating,
    required this.skillRadarAll,
    required this.skillRadarRecent,
    required this.weekSessions,
    this.weekSessionTypes = const <Map<String, int>>[],
    this.latestBadgeTitle = '',
    this.bestMatchGoals = 0,
    this.hasTopRating = false,
    this.completedPlanWeek = false,
  });

  final int totalTrainings;
  final int totalMatches;
  final int totalMinutes;
  final int totalGoals;
  final int totalAssists;
  final int streakDays;
  /// 0 oznacza brak wystawionych ocen, a nie średnią ocenę 0/5.
  final double avgRating;
  final Map<String, int> skillRadarAll;
  final Map<String, int> skillRadarRecent;
  final List<int> weekSessions;
  final List<Map<String, int>> weekSessionTypes;
  final String latestBadgeTitle;
  final int bestMatchGoals;
  final bool hasTopRating;
  final bool completedPlanWeek;

  factory Progress.fromJson(Map<String, dynamic> j) {
    final rawWeek = j['week_sessions'];
    final rawTypes = j['week_session_types'];
    return Progress(
      latestBadgeTitle: _asString(j['latest_badge_title']),
      bestMatchGoals: _asInt(j['best_match_goals']),
      hasTopRating: j['has_top_rating'] == true,
      completedPlanWeek: j['completed_plan_week'] == true,
      totalTrainings: _asInt(j['total_trainings']),
      totalMatches: _asInt(j['total_matches']),
      totalMinutes: _asInt(j['total_minutes']),
      totalGoals: _asInt(j['total_goals']),
      totalAssists: _asInt(j['total_assists']),
      streakDays: _asInt(j['streak_days']),
      avgRating: _asDouble(j['avg_rating']),
      skillRadarAll: _asIntMap(j['skill_radar_all']),
      skillRadarRecent: _asIntMap(j['skill_radar_recent']),
      weekSessionTypes: rawTypes is List
          ? rawTypes.map((e) => _asIntMap(e)).toList()
          : <Map<String, int>>[],
      weekSessions: rawWeek is List
          ? rawWeek.map((e) => _asInt(e)).toList()
          : <int>[0, 0, 0, 0, 0, 0, 0],
    );
  }
}

class WeakSpot {
  const WeakSpot({
    required this.area,
    required this.insight,
    required this.priority,
  });

  final String area;
  final String insight;
  final String priority; // low | medium | high

  factory WeakSpot.fromJson(Map<String, dynamic> j) => WeakSpot(
        area: _asString(j['area']),
        insight: _asString(j['insight']),
        priority: _asString(j['priority']),
      );
}

class WeakSpotsPayload {
  const WeakSpotsPayload({
    required this.weakSpots,
    required this.generatedAt,
    this.source = '',
    this.notice = '',
    required this.noteCount,
  });

  final List<WeakSpot> weakSpots;
  final String generatedAt;
  final String source;
  final String notice;
  final int noteCount;

  factory WeakSpotsPayload.fromJson(Map<String, dynamic> j) {
    final raw = j['weak_spots'];
    return WeakSpotsPayload(
      weakSpots: raw is List
          ? raw
              .map((e) => WeakSpot.fromJson(e as Map<String, dynamic>))
              .toList()
          : <WeakSpot>[],
      generatedAt: _asString(j['generated_at']),
      source: _asString(j['source']),
      notice: _asString(j['fallback_reason']),
      noteCount: _asInt(j['note_count']),
    );
  }
}

class Profile {
  const Profile({
    required this.name,
    required this.age,
    required this.position,
    required this.dominantFoot,
    required this.club,
    required this.jerseyNumber,
    required this.seasonGoal,
    required this.theme,
    required this.updatedAt,
    this.jerseyColor = 0xFF2563EB,
    this.jerseyNumberColor = 0xFFFFFFFF,
    this.clubDays = const <int>[],
    this.clubTime = '',
    this.clubDurationMin = 90,
  });

  final String name;
  final int? age;
  final String position;
  final String dominantFoot;
  final String club;
  final int? jerseyNumber;
  final int jerseyColor;
  final int jerseyNumberColor;
  final String seasonGoal;
  final String theme;
  final String updatedAt;

  /// Dni treningów klubowych (1 = poniedziałek ... 7 = niedziela).
  final List<int> clubDays;

  /// Godzina treningu klubowego (HH:MM), może być pusta.
  final String clubTime;

  /// Czas trwania treningu klubowego w minutach.
  final int clubDurationMin;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: _asString(j['name']),
        age: _asIntOrNull(j['age']),
        position: _asString(j['position']),
        dominantFoot: _asString(j['dominant_foot']),
        club: _asString(j['club']),
        jerseyNumber: _asIntOrNull(j['jersey_number']),
        jerseyColor: _asInt(j['jersey_color'], 0xFF2563EB),
        jerseyNumberColor: _asInt(j['jersey_number_color'], 0xFFFFFFFF),
        seasonGoal: _asString(j['season_goal']),
        theme: _asString(j['theme']),
        updatedAt: _asString(j['updated_at']),
        clubDays: _asIntList(j['club_days']),
        clubTime: _asString(j['club_time']),
        clubDurationMin: _asInt(j['club_duration_min'], 90),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'age': age,
        'position': position,
        'dominant_foot': dominantFoot,
        'club': club,
        'jersey_number': jerseyNumber,
        'jersey_color': jerseyColor,
        'jersey_number_color': jerseyNumberColor,
        'season_goal': seasonGoal,
        'theme': theme,
        'updated_at': updatedAt,
        'club_days': clubDays,
        'club_time': clubTime,
        'club_duration_min': clubDurationMin,
      };
}
