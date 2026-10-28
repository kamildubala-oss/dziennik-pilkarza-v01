import '../utils.dart';

/// Odznaki wynikają wyłącznie z zapisanej historii; nie są osobno
/// przechowywane ani przyznawane za przyszłe, niewykonane plany.
class AchievementService {
  AchievementService._();

  static int asInt(dynamic value) => value is num ? value.toInt() : 0;
  static String day(dynamic date) => first10(date?.toString() ?? '');

  /// Replay history in activity-date order; ties follow the badge list order.
  static String latestBadgeTitle(Map<String, dynamic> database,
      List<Map<String, dynamic>> trainings, List<Map<String, dynamic>> matches,
      {DateTime? asOf}) {
    final dates = earnedDates(database, trainings, matches, asOf: asOf);
    if (dates.isEmpty) return '';
    var latest = '';
    var date = '';
    for (final entry in dates.entries) {
      if (entry.value.compareTo(date) >= 0) { latest = entry.key; date = entry.value; }
    }
    return latest;
  }

  static Map<String, String> earnedDates(Map<String, dynamic> database,
      List<Map<String, dynamic>> trainings, List<Map<String, dynamic>> matches,
      {DateTime? asOf}) {
    final today = dateIso(asOf ?? DateTime.now());
    final entries = <Map<String, dynamic>>[
      ...trainings.map((e) => {...e, '_match': false}),
      ...matches.map((e) => {...e, '_match': true}),
    ].where((e) => day(e['date']).isNotEmpty && day(e['date']).compareTo(today) <= 0).toList()
      ..sort((a, b) {
        final date = day(a['date']).compareTo(day(b['date']));
        return date != 0 ? date : (a['created_at'] ?? a['id'] ?? '').toString()
          .compareTo((b['created_at'] ?? b['id'] ?? '').toString());
      });
    var trainingCount = 0, matchCount = 0, minutes = 0, goals = 0, assists = 0;
    var hatTrick = false, topRating = false;
    final earned = <String>{};
    final datesEarned = <String, String>{};
    for (final entry in entries) {
      if (entry['_match'] == true) {
        matchCount++;
        minutes += asInt(entry['minutes_played']);
        goals += asInt(entry['goals']);
        assists += asInt(entry['assists']);
        hatTrick = hatTrick || asInt(entry['goals']) >= 3;
      } else {
        if (entry['kind'] != 'recovery') trainingCount++;
        minutes += asInt(entry['duration_min']);
      }
      topRating = topRating || asInt(entry['rating']) == 5;
      final conditions = <String, bool>{
        'Pierwszy trening': trainingCount >= 1, '10 treningów': trainingCount >= 10,
        '30 treningów': trainingCount >= 30, '100 treningów': trainingCount >= 100,
        'Pierwszy mecz': matchCount >= 1, '10 meczów': matchCount >= 10,
        '5 godzin aktywności': minutes >= 300, '20 godzin aktywności': minutes >= 1200,
        'Pierwszy gol': goals >= 1, 'Snajper': goals >= 5, 'Hat-trick': hatTrick,
        'Pierwsza asysta': assists >= 1, '10 asyst': assists >= 10, 'Ocena 5/5': topRating,
      };
      for (final badge in conditions.entries) {
        if (badge.value && earned.add(badge.key)) {
          datesEarned[badge.key] = day(entry['date']);
        }
      }
    }
    // A complete plan badge is earned after its final rest day has elapsed.
    String? firstCompletedWeek;
    for (final entry in database.entries) {
      if (!entry.key.startsWith('weekly_plan_') || entry.value is! Map) continue;
      final days = (entry.value as Map)['days'];
      if (days is! List || days.length != 7) continue;
      final dates = days.whereType<Map>().map((d) => day(d['date'])).toList()..sort();
      if (dates.length != 7) continue;
      final end = DateTime.tryParse(dates.last);
      if (end == null) continue;
      final earnedOn = DateTime(end.year, end.month, end.day + 1);
      final iso = dateIso(earnedOn);
      if (iso.compareTo(today) <= 0 && hasCompletedPlanWeek({entry.key: entry.value},
          trainings, matches, asOf: earnedOn) &&
          (firstCompletedWeek == null || iso.compareTo(firstCompletedWeek) < 0)) {
        firstCompletedWeek = iso;
      }
    }
    if (firstCompletedWeek != null) datesEarned['Tydzień według planu'] = firstCompletedWeek;
    return datesEarned;
  }

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
      ...trainings.where((t) => t['kind'] != 'recovery').map((t) => day(t['date'])),
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
