import '../local_db.dart';
import '../models.dart';
import '../utils.dart';
import 'achievement_service.dart';
import 'streak_service.dart';
import 'skill_radar_service.dart';

/// Jedno źródło statystyk używane przez Dziennik i Postęp.
class ProgressCalculator {
  static int asInt(dynamic value) => value is num ? value.toInt() : 0;
  static String asString(dynamic value) => value == null ? '' : value.toString();

  static Future<Progress> calculate({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final trainings = await LocalDb.list('trainings');
    final matches = await LocalDb.list('matches');
    final totalMinutes = trainings.fold<int>(0, (a, t) => a + asInt(t['duration_min'])) + matches.fold<int>(0, (a, m) => a + asInt(m['minutes_played']));
    final totalGoals = matches.fold<int>(0, (a, m) => a + asInt(m['goals']));
    final totalAssists = matches.fold<int>(0, (a, m) => a + asInt(m['assists']));
    final ratings = <int>[...trainings.map((t) => asInt(t['rating'])), ...matches.map((m) => asInt(m['rating']))];
    final avgRating = ratings.isEmpty ? 0.0 : (ratings.reduce((a, b) => a + b) / ratings.length * 100).round() / 100;
    String day(Map<String, dynamic> e) => first10(asString(e['date']));
    final dates = <String>{...trainings.map(day).where((d) => d.isNotEmpty), ...matches.map(day).where((d) => d.isNotEmpty)};
    final streak = StreakService.calculate(dates, asOf: now);
    String dayAgo(int i) => dateIso(DateTime(now.year, now.month, now.day - i));
    final history = await LocalDb.exportAll();
    final completedPlanWeek = AchievementService.hasCompletedPlanWeek(
      history, trainings, matches, asOf: now,
    );
    final weekSessions = <int>[for (var i = 6; i >= 0; i--) trainings.where((t) => day(t) == dayAgo(i)).length + matches.where((m) => day(m) == dayAgo(i)).length];
    return Progress.fromJson(<String, dynamic>{
      'best_match_goals': AchievementService.maxGoals(matches),
      'has_top_rating': AchievementService.hasFiveStarRating(trainings, matches),
      'completed_plan_week': completedPlanWeek,
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

