import '../local_db.dart';
import '../models.dart';
import '../utils.dart';
import 'achievement_service.dart';
import 'streak_service.dart';
import 'skill_radar_service.dart';
import 'week_plan_progress.dart';

/// Jedno źródło statystyk używane przez Dziennik i Postęp.
class ProgressCalculator {
  static int asInt(dynamic value) => value is num ? value.toInt() : 0;
  static String asString(dynamic value) =>
      value == null ? '' : value.toString();

  static Future<Progress> calculate({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final trainings = await LocalDb.list('trainings');
    final matches = await LocalDb.list('matches');
    final totalMinutes =
        trainings.fold<int>(0, (a, t) => a + asInt(t['duration_min'])) +
        matches.fold<int>(0, (a, m) => a + asInt(m['minutes_played']));
    final totalGoals = matches.fold<int>(0, (a, m) => a + asInt(m['goals']));
    final totalAssists = matches.fold<int>(
      0,
      (a, m) => a + asInt(m['assists']),
    );
    final ratings = <int>[
      ...trainings.map((t) => asInt(t['rating'])),
      ...matches.map((m) => asInt(m['rating'])),
    ].where((r) => r >= 1 && r <= 5).toList();
    final avgRating = ratings.isEmpty
        ? 0.0
        : (ratings.reduce((a, b) => a + b) / ratings.length * 100).round() /
              100;
    String day(Map<String, dynamic> e) => first10(asString(e['date']));
    final dates = <String>{
      ...trainings.map(day).where((d) => d.isNotEmpty),
      ...matches.map(day).where((d) => d.isNotEmpty),
    };
    final streak = StreakService.calculate(dates, asOf: now);
    String dayAgo(int i) => dateIso(DateTime(now.year, now.month, now.day - i));
    final history = await LocalDb.exportAll();
    final completedPlanWeek = AchievementService.hasCompletedPlanWeek(
      history,
      trainings,
      matches,
      asOf: now,
    );
    final weekSessions = <int>[
      for (var i = 6; i >= 0; i--)
        trainings.where((t) => day(t) == dayAgo(i)).length +
            matches.where((m) => day(m) == dayAgo(i)).length,
    ];
    final events = await LocalDb.list('events');
    final planDays = <Map<String, dynamic>>[];
    for (final entry in history.entries) {
      if (!entry.key.startsWith('weekly_plan_') || entry.value is! Map)
        continue;
      final days = (entry.value as Map)['days'];
      if (days is List)
        planDays.addAll(
          days.whereType<Map>().map((d) => Map<String, dynamic>.from(d)),
        );
    }
    final recovery = (await LocalDb.getDoc('recovery_days'))?['dates'];
    final recoveryDays = recovery is List
        ? recovery.map(asString).toSet()
        : <String>{};
    final realization = WeekPlanProgress.calculate(
      events,
      planDays,
      recoveryDays,
      trainings,
      matches,
      asOf: now,
    );
    final byType = <String, List<int>>{
      for (final type in ['training', 'club_training', 'match'])
        type: [
          for (var i = 6; i >= 0; i--)
            type == 'match'
                ? matches.where((m) => day(m) == dayAgo(i)).length
                : trainings
                      .where(
                        (t) =>
                            day(t) == dayAgo(i) &&
                            (asString(t['kind']) == 'club_training'
                                    ? 'club_training'
                                    : 'training') ==
                                type,
                      )
                      .length,
        ],
    };
    return Progress.fromJson(<String, dynamic>{
      'best_match_goals': AchievementService.maxGoals(matches),
      'has_top_rating': AchievementService.hasFiveStarRating(
        trainings,
        matches,
      ),
      'completed_plan_week': completedPlanWeek,
      'total_trainings': trainings.length,
      'total_matches': matches.length,
      'total_minutes': totalMinutes,
      'total_goals': totalGoals,
      'total_assists': totalAssists,
      'streak_days': streak,
      'avg_rating': avgRating,
      'rated_count': ratings.length,
      'week_planned': realization.total,
      'week_completed': realization.done,
      'week_by_type': byType,
      'confirmed_recovery_days': recoveryDays.toList(),
      'skill_radar_previous': SkillRadarService.calculate(
        trainings,
        matches,
        since: dayAgo(27),
        until: dayAgo(14),
      ),
      'skill_radar_all': SkillRadarService.calculate(trainings, matches),
      'skill_radar_recent': SkillRadarService.calculate(
        trainings,
        matches,
        since: dayAgo(13),
        until: dayAgo(0),
      ),
      'week_sessions': weekSessions,
    });
  }
}
