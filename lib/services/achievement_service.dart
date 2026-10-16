import '../utils.dart';

/// Odznaki wynikają wyłącznie z zapisanej historii; nie są osobno
/// przechowywane ani przyznawane za przyszłe, niewykonane plany.
class AchievementService {
  AchievementService._();

  static int asInt(dynamic value) => value is num ? value.toInt() : 0;
  static String day(dynamic date) => first10(date?.toString() ?? '');

  static int maxGoals(List<Map<String, dynamic>> matches) {
    var best = 0;
    for (final match in matches) {
      final goals = asInt(match['goals']);
      if (goals > best) best = goals;
    }
    return best;
  }

  static bool hasFiveStarRating(
      List<Map<String, dynamic>> trainings, List<Map<String, dynamic>> matches) {
    return [...trainings, ...matches]
        .any((entry) => asInt(entry['rating']) == 5);
  }

  /// Zrealizowany tydzień: siedem dni planu z zakończonego tygodnia.
  /// W dzień odpoczynku/regeneracji nie może być wpisanego treningu lub meczu;
  /// w każdy inny dzień musi istnieć faktycznie wykonana aktywność.
  /// Nie premiujemy więc trenowania przez siedem dni bez przerwy.
  static bool hasCompletedPlanWeek(
    Map<String, dynamic> database,
    List<Map<String, dynamic>> trainings,
    List<Map<String, dynamic>> matches, {
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final today = dateIso(DateTime(now.year, now.month, now.day));
    final activities = <String>{
      ...trainings.map((t) => day(t['date'])),
      ...matches.map((m) => day(m['date'])),
    };

    for (final entry in database.entries) {
      if (!entry.key.startsWith('weekly_plan_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final days = raw['days'];
      if (days is! List || days.length != 7) continue;
      var passed = true;
      final checked = <String>{};
      for (final value in days) {
        if (value is! Map) {
          passed = false;
          break;
        }
        final iso = day(value['date']);
        final parsed = DateTime.tryParse(iso);
        if (parsed == null || dateIso(parsed) != iso ||
            iso.compareTo(today) >= 0 || !checked.add(iso)) {
          // Dzień odpoczynku musi naprawdę minąć.
          passed = false;
          break;
        }
        final focus = (value['focus'] ?? '').toString().toLowerCase();
        final isRest = focus.contains('odpoczynek') ||
            focus.contains('regeneracj') || focus == 'rest';
        final didActivity = activities.contains(iso);
        if ((isRest && didActivity) || (!isRest && !didActivity)) {
          passed = false;
          break;
        }
      }
      if (passed && checked.length == 7) {
        final dates = checked.toList()..sort();
        final monday = DateTime.parse(dates.first);
        if (monday.weekday != DateTime.monday) continue;
        final expectedLast = dateIso(DateTime(monday.year, monday.month, monday.day + 6));
        if (dates.last == expectedLast) return true;
      }
    }
    return false;
  }
}
