import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dateIso formatuje datę jako RRRR-MM-DD', () {
    expect(dateIso(DateTime(2026, 5, 1)), '2026-05-01');
    expect(dateIso(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('Progress.fromJson parsuje odpowiedź backendu', () {
    final p = Progress.fromJson(<String, dynamic>{
      'total_trainings': 3,
      'total_matches': 1,
      'total_minutes': 150,
      'total_goals': 2,
      'total_assists': 1,
      'streak_days': 2,
      'avg_rating': 4,
      'skill_radar_all': <String, dynamic>{'Technika': 30},
      'skill_radar_recent': <String, dynamic>{'Technika': 50},
      'week_sessions': <dynamic>[0, 0, 1, 0, 0, 2, 1],
    });
    expect(p.totalTrainings, 3);
    expect(p.avgRating, 4.0);
    expect(p.skillRadarRecent['Technika'], 50);
    expect(p.weekSessions.length, 7);
  });
}
