import '../local_db.dart';
import '../models.dart';
import '../utils.dart';

/// Oblicza serię kolejnych dni z wykonanym treningiem lub meczem.
/// Seria kończy się w ostatnim dniu, w którym zapisano aktywność,
/// więc wprowadzenie zaległych wpisów też daje poprawny wynik.
class StreakService {
  /// Liczy kolejne dni WYKONANYCH aktywności, zaczynając od najnowszego
  /// zarejestrowanego dnia. Nie wymaga treningu dziś ani wczoraj,
  /// ponieważ dziennik może być uzupełniany z opóźnieniem.
  ///
  /// Każda data jest liczona raz (również gdy jest kilka treningów dziennie).
  /// Przyszłe daty nie mogą sztucznie podnosić serii.
  static int calculate(Iterable<String> dates, {DateTime? asOf}) {
    final reference = asOf ?? DateTime.now();
    final today = dateIso(DateTime(reference.year, reference.month, reference.day));
    final days = <String>{};
    for (final value in dates) {
      final iso = first10(value);
      final date = DateTime.tryParse(iso);
      if (date == null || dateIso(date) != iso || iso.compareTo(today) > 0) {
        continue;
      }
      days.add(iso);
    }
    if (days.isEmpty) return 0;

    final latest = days.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    final lastDay = DateTime.parse(latest);
    var count = 0;
    for (var offset = 0; offset < days.length; offset++) {
      final day = dateIso(DateTime(lastDay.year, lastDay.month, lastDay.day - offset));
      if (!days.contains(day)) break;
      count++;
    }
    return count;
  }
}
/// Agreguje obszary umiejętności z wykonanych aktywności.
class SkillRadarService {
  static const Map<String, String> focusToAxis = <String, String>{
    'Prowadzenie': 'Technika',
    'Strzał': 'Strzał',
    'Decyzyjność': 'Taktyka',
    'Siła': 'Motoryka',
    'Mentalność': 'Mentalność',
  };
  static const List<String> axes = <String>['Technika', 'Strzał', 'Taktyka', 'Motoryka', 'Mentalność'];

  static double ratingWeight(dynamic r) {
    final v = (r is num ? r.toInt() : 3).clamp(1, 5);
    return 0.5 + (v - 1) * 0.175;
  }

  static Map<String, int> calculate(List<Map<String, dynamic>> trainings, List<Map<String, dynamic>> matches, {String? since}) {
    String str(dynamic v) => v == null ? '' : v.toString();
    String day(Map<String, dynamic> e) => first10(str(e['date']));
    final weights = <String, double>{for (final a in axes) a: 0.0};
    for (final t in trainings) {
      if (since != null && day(t).compareTo(since) < 0) continue;
      final raw = t['focuses'];
      final focuses = raw is List && raw.isNotEmpty ? raw.map(str).toList() : str(t['focus']).split(',').map((e) => e.trim()).toList();
      final share = focuses.isEmpty ? 0.0 : 1.0 / focuses.length;
      for (final focus in focuses) {
        final axis = focusToAxis[focus];
        if (axis != null) weights[axis] = weights[axis]! + ratingWeight(t['rating']) * share;
      }
    }
    for (final m in matches) {
      if (since != null && day(m).compareTo(since) < 0) continue;
      weights['Mentalność'] = weights['Mentalność']! + ratingWeight(m['rating']) * 0.5;
    }
    return <String, int>{for (final e in weights.entries) e.key: ((e.value / 10) * 100).toInt().clamp(0, 100).toInt()};
  }
}

/// Jedno źródło statystyk używane przez Dziennik i Postęp.
class ProgressCalculator {
  static int asInt(dynamic value) => value is num ? value.toInt() : 0;
  static String asString(dynamic value) => value == null ? '' : value.toString();

  static Future<Progress> calculate() async {
    final trainings = await LocalDb.list('trainings');
    final matches = await LocalDb.list('matches');
    final totalMinutes = trainings.fold<int>(0, (a, t) => a + asInt(t['duration_min'])) + matches.fold<int>(0, (a, m) => a + asInt(m['minutes_played']));
    final totalGoals = matches.fold<int>(0, (a, m) => a + asInt(m['goals']));
    final totalAssists = matches.fold<int>(0, (a, m) => a + asInt(m['assists']));
    final ratings = <int>[...trainings.map((t) => asInt(t['rating'])), ...matches.map((m) => asInt(m['rating']))];
    final avgRating = ratings.isEmpty ? 0.0 : (ratings.reduce((a, b) => a + b) / ratings.length * 100).round() / 100;
    String day(Map<String, dynamic> e) => first10(asString(e['date']));
    final dates = <String>{...trainings.map(day).where((d) => d.isNotEmpty), ...matches.map(day).where((d) => d.isNotEmpty)};
    final streak = StreakService.calculate(dates);
    final now = DateTime.now();
    String dayAgo(int i) => dateIso(DateTime(now.year, now.month, now.day - i));
    final weekSessions = <int>[for (var i = 6; i >= 0; i--) trainings.where((t) => day(t) == dayAgo(i)).length + matches.where((m) => day(m) == dayAgo(i)).length];
    return Progress.fromJson(<String, dynamic>{
      'total_trainings': trainings.length,
      'total_matches': matches.length,
      'total_minutes': totalMinutes,
      'total_goals': totalGoals,
      'total_assists': totalAssists,
      'streak_days': streak,
      'avg_rating': avgRating,
      'skill_radar_all': SkillRadarService.calculate(trainings, matches),
      'skill_radar_recent': SkillRadarService.calculate(trainings, matches, since: dayAgo(14)),
      'week_sessions': weekSessions,
    });
  }
}
