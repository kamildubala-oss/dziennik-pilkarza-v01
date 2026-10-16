import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/services/achievement_service.dart';
import 'package:dziennik_pilkarza/services/progress_calculator.dart';
import 'package:dziennik_pilkarza/services/user_errors.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> record(String date, {int min = 45, int rating = 3}) =>
    <String, dynamic>{
      'id': 'r-$date', 'date': date,
      'duration_min': min, 'rating': rating,
      'focuses': <String>['Siła'], 'focus': 'Siła',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  setUp(() async => (await SharedPreferences.getInstance()).clear());

  test('Wiek 8–21: pole opcjonalne, litery i wartości skrajne odrzucane', () {
    expect(ageFieldError(''), isNull);
    expect(ageFieldError('12'), isNull);
    expect(ageFieldError('21'), isNull);
    expect(ageFieldError('siedem'), isNotNull);
    expect(ageFieldError('7'), isNotNull);
    expect(ageFieldError('22'), isNotNull);
  });

  test('Odznaka: hat-trick wymaga trzech goli W JEDNYM meczu', () {
    expect(AchievementService.maxGoals(<Map<String, dynamic>>[
      <String, dynamic>{'goals': 1}, <String, dynamic>{'goals': 2},
    ]), 2);
    expect(AchievementService.maxGoals(<Map<String, dynamic>>[
      <String, dynamic>{'goals': 1}, <String, dynamic>{'goals': 3},
    ]), 3);
  });

  test('Pierwsza ocena 5/5 dotyczy rzeczywistego wpisu treningu albo meczu', () {
    expect(AchievementService.hasFiveStarRating([record('2026-10-01')], []), false);
    expect(AchievementService.hasFiveStarRating([record('2026-10-01', rating: 5)], []), true);
    expect(AchievementService.hasFiveStarRating([], [
      <String, dynamic>{'rating': 5},
    ]), true);
  });

  test('Tydzień z regeneracją: wykonane dni treningowe, odpoczynek bez treningu', () {
    final monday = DateTime(2026, 10, 5);
    final days = <Map<String, dynamic>>[
      for (var i = 0; i < 7; i++)
        <String, dynamic>{
          'date': dateIso(DateTime(monday.year, monday.month, monday.day + i)),
          'focus': i == 2 || i == 6 ? 'Odpoczynek' : 'Siła',
        },
    ];
    final workouts = <Map<String, dynamic>>[
      for (var i in <int>[0, 1, 3, 4, 5])
        record(dateIso(DateTime(2026, 10, 5 + i))),
    ];
    final db = <String, dynamic>{
      'weekly_plan_2026-W41': <String, dynamic>{'days': days}
    };
    expect(AchievementService.hasCompletedPlanWeek(
      db, workouts, [], asOf: DateTime(2026, 10, 15),
    ), true);
    // Trening w dzień odpoczynku nie pozwala zdobyć odznaki.
    expect(AchievementService.hasCompletedPlanWeek(
      db, [...workouts, record('2026-10-07')], [],
      asOf: DateTime(2026, 10, 15),
    ), false);
    // Brak wykonania dnia aktywnego też oznacza nieukończony plan.
    expect(AchievementService.hasCompletedPlanWeek(
      db, workouts.take(4).toList(), [],
      asOf: DateTime(2026, 10, 15),
    ), false);
    // Tygodnia trwającego jeszcze w przyszłości nie nagradzamy.
    expect(AchievementService.hasCompletedPlanWeek(
      db, workouts, [], asOf: DateTime(2026, 10, 9),
    ), false);
  });

  test('ProgressCalculator wylicza progi z rzeczywistych wpisów', () async {
    final workouts = <Map<String, dynamic>>[record('2026-10-10', min: 120, rating: 5)];
    final matches = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'm1', 'date': '2026-10-11', 'minutes_played': 180,
        'goals': 3, 'assists': 10, 'rating': 4,
      },
    ];
    await LocalDb.saveList('trainings', workouts);
    await LocalDb.saveList('matches', matches);
    final p = await ProgressCalculator.calculate();
    expect(p.totalMinutes, 300);
    expect(p.totalAssists, 10);
    expect(p.bestMatchGoals, 3);
    expect(p.hasTopRating, true);
    expect(p.completedPlanWeek, false);
  });

  test('Stare modele postępu pozostają kompatybilne (nowe pola opcjonalne)', () {
    final p = Progress.fromJson(<String, dynamic>{
      'total_trainings': 1, 'total_minutes': 60,
    });
    expect(p.bestMatchGoals, 0);
    expect(p.hasTopRating, false);
    expect(p.completedPlanWeek, false);
  });
}
